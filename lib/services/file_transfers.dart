import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/attachments/attachments.dart';
import 'package:btox/db/database.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/app_defaults.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/sync/event.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

const _logger = Logger(['FileTransfers']);

/// A friend's file, by friend number and file number.
typedef _Key = (FriendNumber, FileNumber);

/// An offered file being recorded, and how it ended meanwhile, if it did.
final class _Arrival {
  FileState? ended;
}

/// How soon a chunk Tox had no room for is sent again.
const chunkRetryDelay = Duration(milliseconds: 20);

final class _Transfer {
  final Id<Transfers> id;
  final GraphId chat;
  final EventId event;
  final int size;
  final String path;
  Attachment? file;
  int transferred = 0;
  DateTime saved = clock.now();
  // Chunks Tox asked for, by position and length, not yet sent.
  final chunks = Queue<(int, int)>();
  // Set while Tox has no room for the first of them.
  Timer? retry;

  _Transfer(this.id, this.chat, this.event, this.size, this.path);
}

/// Moves files between one profile's Tox and its attachments directory. Each
/// starts with an event in its chat, and its end is one too.
final class FileTransfers implements ToxFiles {
  final Database _db;
  final Tox _tox;
  final Id<Profiles> _profileId;
  final Future<String> Function() _directory;
  final Future<NewEvent?> Function(GraphId graph, EventContent content) _record;
  final _incoming = <_Key, _Transfer>{};
  final _outgoing = <_Key, _Transfer>{};
  // Offered files being recorded. A friend may offer another under the same
  // number once one ended, which then takes its place.
  final _arriving = <_Key, _Arrival>{};
  var _disposed = false;

  /// Larger files wait until accepted.
  int autoAcceptSize = defaultAutoAcceptFileSize;

  FileTransfers(
    this._db,
    this._tox,
    this._profileId,
    this._directory,
    this._record,
  );

  void dispose() {
    _disposed = true;
    for (final transfer in [..._incoming.values, ..._outgoing.values]) {
      transfer.file?.close();
    }
    _incoming.clear();
    _outgoing.clear();
  }

  Future<void> offered(
    GraphId chat,
    String sender,
    FriendNumber friendNumber,
    FileNumber fileNumber,
    FileKind kind,
    int size,
    String name,
  ) async {
    if (kind != FileKind.data || !filesSupported) {
      decline(friendNumber, fileNumber);
      return;
    }
    final key = (friendNumber, fileNumber);
    final fileId = _fileIdOf(key);
    final arrival = _arriving[key] = _Arrival();
    final _Transfer transfer;
    final bool accept;
    if (fileId == null
            ? null
            : await _db.unfinishedTransfer(_profileId, chat, fileId, size)
        case Transfer(
          :final id,
          event: final event?,
          :final path,
          :final transferred,
        )) {
      // Sent again after it stopped, it goes on where it stopped, accepted
      // if it was.
      transfer = _Transfer(id, chat, event, size, path);
      accept = transferred > 0 || size <= autoAcceptSize;
      await _db.setTransferState(
        id,
        accept ? FileState.active : FileState.offered,
      );
    } else {
      final path = newAttachmentPath(await _directory(), name);
      accept = size <= autoAcceptSize;
      final started = await _record(
        chat,
        FileStarted(sender: sender, name: name, size: size, incoming: true),
      );
      if (started == null) {
        _arrived(key, arrival);
        decline(friendNumber, fileNumber);
        return;
      }
      final (event, _, _) = started;
      final id = await _db.addTransfer(
        TransfersCompanion.insert(
          profileId: _profileId,
          graph: chat,
          event: Value(event),
          incoming: true,
          name: name,
          size: size,
          path: path,
          state: accept ? FileState.active : FileState.offered,
          fileId: Value(fileId),
        ),
      );
      transfer = _Transfer(id, chat, event, size, path);
    }
    _arrived(key, arrival);
    final ended = arrival.ended;
    if (_disposed) {
      // Ended when the profile next starts.
      return;
    }
    if (ended != null) {
      _stop(transfer, ended);
      return;
    }
    _incoming[key] = transfer;
    if (accept) {
      _accept(key);
    }
  }

  FileId? _fileIdOf(_Key key) {
    try {
      return _tox.fileGetFileId(key.$1, key.$2);
    } on ApiException catch (e) {
      _logger.w('No ID for file ${key.$2}: $e');
      return null;
    }
  }

  void decline(FriendNumber friendNumber, FileNumber fileNumber) =>
      _control(friendNumber, fileNumber, FileControl.cancel);

  /// Called when the user accepts, declines or cancels files.
  void transfersChanged(List<Transfer> transfers) {
    final states = {for (final t in transfers) t.id: t.state};
    for (final MapEntry(:key, value: transfer) in [..._incoming.entries]) {
      switch (states[transfer.id]) {
        case FileState.active when transfer.file == null:
          _accept(key);
        case FileState.cancelled:
          _control(key.$1, key.$2, FileControl.cancel);
          _incoming.remove(key);
          _cancel(transfer);
        default:
          break;
      }
    }
    for (final MapEntry(:key, value: transfer) in [..._outgoing.entries]) {
      if (states[transfer.id] == FileState.cancelled) {
        _control(key.$1, key.$2, FileControl.cancel);
        _outgoing.remove(key);
        _cancel(transfer);
      }
    }
    // The sender offers a cancelled file again as a new one, so drop what
    // arrived.
    for (final Transfer(:incoming, :state, :path) in transfers) {
      if (incoming && state == FileState.cancelled && attachmentExists(path)) {
        _logger.unawaited('delete $path', deleteAttachment(path));
      }
    }
  }

  @override
  void chunk(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    int position,
    Uint8List data,
  ) {
    final key = (friendNumber, fileNumber);
    final transfer = _incoming[key];
    if (transfer == null) {
      return;
    }
    if (data.isEmpty) {
      _incoming.remove(key);
      _finish(transfer);
      return;
    }
    transfer.file?.write(position, data);
    _progress(transfer, position + data.length);
  }

  @override
  void requested(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    int position,
    int length,
  ) {
    final key = (friendNumber, fileNumber);
    final transfer = _outgoing[key];
    if (transfer == null) {
      return;
    }
    if (length == 0) {
      _outgoing.remove(key);
      _finish(transfer);
      return;
    }
    transfer.chunks.add((position, length));
    if (transfer.retry == null) {
      _sendChunks(key, transfer);
    }
  }

  /// Sends the chunks Tox asked for, in order: it asks for each only once,
  /// ahead of time, and takes each only after the one before. One it had no
  /// room for holds back the rest until it goes.
  void _sendChunks(_Key key, _Transfer transfer) {
    transfer.retry = null;
    final (friendNumber, fileNumber) = key;
    while (_outgoing[key] == transfer && transfer.chunks.isNotEmpty) {
      final (position, length) = transfer.chunks.first;
      try {
        final data = transfer.file!.read(position, length);
        _tox.fileSendChunk(friendNumber, fileNumber, position, data);
        _progress(transfer, position + length);
      } on ApiException catch (e) {
        if (e.error == FileSendChunkError.sendQueueFull) {
          transfer.retry = Timer(
            chunkRetryDelay,
            () => _sendChunks(key, transfer),
          );
          return;
        }
        _logger.w('Failed to send a file chunk: $e');
      }
      transfer.chunks.removeFirst();
    }
  }

  void _arrived(_Key key, _Arrival arrival) {
    if (identical(_arriving[key], arrival)) {
      _arriving.remove(key);
    }
  }

  @override
  void controlled(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    FileControl control,
  ) {
    if (control != FileControl.cancel) {
      return;
    }
    final key = (friendNumber, fileNumber);
    _arriving[key]?.ended = FileState.cancelled;
    for (final transfers in [_incoming, _outgoing]) {
      if (transfers.remove(key) case final transfer?) {
        _cancel(transfer);
      }
    }
  }

  /// Sends [transfer], one of ours that started, unless it's on its way.
  void send(Transfer transfer, FriendNumber friendNumber) {
    final event = transfer.event;
    if (event == null ||
        transfer.incoming ||
        transfer.state != FileState.active ||
        _outgoing.values.any((t) => t.id == transfer.id)) {
      return;
    }
    final outgoing = _Transfer(
      transfer.id,
      transfer.graph,
      event,
      transfer.size,
      transfer.path,
    );
    final Attachment file;
    try {
      file = outgoing.file = Attachment.open(transfer.path);
    } catch (e) {
      _logger.w('Cannot read ${transfer.path}: $e');
      _cancel(outgoing);
      return;
    }
    try {
      final fileNumber = _tox.fileSend(
        friendNumber,
        FileKind.data,
        transfer.size,
        // The same each time, so the friend can go on from where it stopped.
        FileId(event.bytes),
        utf8.encode(transfer.name),
      );
      _outgoing[(friendNumber, fileNumber)] = outgoing;
    } on ApiException catch (e) {
      file.close();
      _logger.w('Failed to send file ${transfer.id}: $e');
    }
  }

  /// Toxcore drops a friend's transfers when they go offline.
  void friendOffline(FriendNumber friendNumber) {
    for (final MapEntry(:key, value: arrival) in _arriving.entries) {
      if (key.$1 == friendNumber) {
        arrival.ended = FileState.paused;
      }
    }
    for (final key in [..._incoming.keys.where((k) => k.$1 == friendNumber)]) {
      _stop(_incoming.remove(key)!, FileState.paused);
    }
    for (final key in [..._outgoing.keys.where((k) => k.$1 == friendNumber)]) {
      final transfer = _outgoing.remove(key)!;
      transfer.file?.close();
      _logger.unawaited('restart file', _db.setTransferred(transfer.id, 0));
    }
  }

  void _accept(_Key key) {
    final transfer = _incoming[key]!;
    try {
      // What arrived before, if it stopped, stays.
      final file = transfer.file = Attachment.resume(transfer.path);
      if (file.length case final had when had > 0 && had < transfer.size) {
        _tox.fileSeek(key.$1, key.$2, had);
        transfer.transferred = had;
      }
    } catch (e) {
      _logger.e('Cannot write ${transfer.path}: $e');
      _control(key.$1, key.$2, FileControl.cancel);
      _cancel(_incoming.remove(key)!);
      return;
    }
    _control(key.$1, key.$2, FileControl.resume);
  }

  void _finish(_Transfer transfer) {
    transfer.file?.close();
    _logger.unawaited(
      'finish file',
      _db.setTransferState(
        transfer.id,
        FileState.done,
        transferred: transfer.size,
      ),
    );
    _ended(transfer, ok: true);
  }

  void _cancel(_Transfer transfer) => _stop(transfer, FileState.cancelled);

  void _stop(_Transfer transfer, FileState state) {
    transfer.file?.close();
    _logger.unawaited(
      'stop file',
      _db.setTransferState(
        transfer.id,
        state,
        transferred: transfer.transferred,
      ),
    );
    _ended(transfer, ok: false);
  }

  void _ended(_Transfer transfer, {required bool ok}) =>
      _record(transfer.chat, FileEnded(file: transfer.event, ok: ok));

  void _control(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    FileControl control,
  ) {
    try {
      _tox.fileControl(friendNumber, fileNumber, control);
    } on ApiException catch (e) {
      _logger.w('Failed to control file $fileNumber: $e');
    }
  }

  void _progress(_Transfer transfer, int transferred) {
    transfer.transferred = transferred;
    final now = clock.now();
    if (now.difference(transfer.saved) > progressSaveInterval) {
      transfer.saved = now;
      _logger.unawaited(
        'save progress',
        _db.setTransferred(transfer.id, transferred),
      );
    }
  }
}
