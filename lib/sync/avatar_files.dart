import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/db/database.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:convert/convert.dart' show hex;
import 'package:crypto/crypto.dart' show sha256;

const _logger = Logger(['AvatarFiles']);

const maxAvatarSize = 64 * 1024;

typedef _Key = (FriendNumber, FileNumber);

final class _Incoming {
  final BlobId blob;
  final int size;
  final Future<void> Function() kept;
  final bytes = BytesBuilder();

  _Incoming(this.blob, this.size, this.kept);
}

/// Kept in memory until stored, as avatars are small.
final class AvatarFiles implements ToxFiles {
  final Database _db;
  final Tox _tox;
  final Id<Profiles> _profileId;
  final _incoming = <_Key, _Incoming>{};
  final _outgoing = <_Key, Uint8List>{};

  AvatarFiles(this._db, this._tox, this._profileId);

  bool moves(FriendNumber friendNumber, FileNumber fileNumber) =>
      _incoming.containsKey((friendNumber, fileNumber)) ||
      _outgoing.containsKey((friendNumber, fileNumber));

  /// Calls [kept] once [blob] is stored.
  void receive(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    BlobId blob,
    int size,
    Future<void> Function() kept,
  ) {
    final key = (friendNumber, fileNumber);
    _incoming[key] = _Incoming(blob, size, kept);
    _control(key, FileControl.resume);
  }

  void decline(FriendNumber friendNumber, FileNumber fileNumber) =>
      _control((friendNumber, fileNumber), FileControl.cancel);

  /// With no [blob], an empty file says there's none.
  void send(FriendNumber friendNumber, BlobId? blob, Uint8List bytes) {
    try {
      final fileNumber = _tox.fileSend(
        friendNumber,
        FileKind.avatar,
        bytes.length,
        FileId(blob?.bytes ?? Uint8List(32)),
        // Some clients read an avatar without a name as none.
        blob == null
            ? Uint8List(0)
            : utf8.encode('${hex.encode(blob.bytes)}.png'),
      );
      if (bytes.isNotEmpty) {
        _outgoing[(friendNumber, fileNumber)] = bytes;
      }
    } on ApiException catch (e) {
      _logger.w('Failed to send an avatar: $e');
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
    final incoming = _incoming[key];
    if (incoming == null) {
      return;
    }
    if (data.isNotEmpty) {
      if (position != incoming.bytes.length ||
          position + data.length > incoming.size) {
        _incoming.remove(key);
        _control(key, FileControl.cancel);
        return;
      }
      incoming.bytes.add(data);
      return;
    }
    _incoming.remove(key);
    final bytes = incoming.bytes.takeBytes();
    if (bytes.length != incoming.size ||
        BlobId(Uint8List.fromList(sha256.convert(bytes).bytes)) !=
            incoming.blob) {
      _logger.w('An avatar is not the one offered');
      return;
    }
    _logger.unawaited('keep an avatar', () async {
      await _db.setAvatar(_profileId, incoming.blob, bytes);
      await incoming.kept();
    }());
  }

  @override
  void requested(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    int position,
    int length,
  ) {
    final key = (friendNumber, fileNumber);
    final bytes = _outgoing[key];
    if (bytes == null) {
      return;
    }
    if (length == 0 || position + length > bytes.length) {
      _outgoing.remove(key);
      return;
    }
    try {
      _tox.fileSendChunk(
        friendNumber,
        fileNumber,
        position,
        Uint8List.sublistView(bytes, position, position + length),
      );
    } on ApiException catch (e) {
      _logger.w('Failed to send an avatar chunk: $e');
    }
  }

  @override
  void controlled(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    FileControl control,
  ) {
    if (control == FileControl.cancel) {
      _incoming.remove((friendNumber, fileNumber));
      _outgoing.remove((friendNumber, fileNumber));
    }
  }

  void friendOffline(FriendNumber friendNumber) {
    _incoming.removeWhere((key, _) => key.$1 == friendNumber);
    _outgoing.removeWhere((key, _) => key.$1 == friendNumber);
  }

  void _control(_Key key, FileControl control) {
    try {
      _tox.fileControl(key.$1, key.$2, control);
    } on ApiException catch (e) {
      _logger.w('Failed to control avatar file ${key.$2}: $e');
    }
  }
}
