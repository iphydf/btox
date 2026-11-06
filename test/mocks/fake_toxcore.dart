// Fake implementation of the Tox class for testing purposes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart' as api;
import 'package:btox/api/toxcore/tox_av.dart' as api;
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';

import 'fake_tox_av.dart';

const _logger = Logger(['FakeToxcore']);

final _address = ToxAddress.fromString(
  '52602D8D81573725A77F602A53CD1CD8C2156595E8C3310EAC3552E99B7FB50D897BC532A375',
);

/// Implements the parts of toxcore that tests use; the rest throws.
final class FakeToxcore extends api.Tox {
  String name = 'Yanciman';

  String statusMessage = 'Producing works of art in Kannywood';

  @override
  bool isAlive = true;

  bool throwOnBootstrap = false;
  // Thrown by the next iterate, as for events that can't be read.
  Object? iterateError;
  final List<Event> _events = [];

  final List<PublicKey> friends = [];

  final List<(ToxAddress, String)> friendRequests = [];

  final List<int> deletedFriends = [];

  /// (friend number, message ID, text)
  final List<(int, int, String)> sentMessages = [];

  final Set<int> unreachableFriends = {};
  // Friends Tox doesn't see online yet, so it takes no packets for them.
  final Set<int> unconnectedFriends = {};

  /// How many more messages Tox takes before its queue is full, if limited.
  int? sendQueueRoom;

  final List<(int, int, api.FileControl)> fileControls = [];
  final List<(int, int, String)> fileSends = [];
  // By file number, as fileSends.
  final List<(api.FileKind, FileId?)> fileSendKinds = [];
  final List<(int, int, int, Uint8List)> fileChunks = [];
  final List<(int, int, int)> fileSeeks = [];
  // Of files friends send, by friend number and file number, else made up
  // from those.
  final Map<(int, int), Uint8List> fileIds = {};
  // How many more chunks find the send queue full.
  int fullChunkQueues = 0;
  // Where each file's next chunk must start, as Tox takes them in order.
  final _nextChunk = <(int, int), int>{};
  final List<(int, Uint8List)> losslessPackets = [];
  // By friend, in order.
  final List<(int, bool)> typingTold = [];

  int _nextMessageId = 0;

  var _connection = api.Connection.none;

  void pushEvent(Event event) {
    if (event case ToxEventSelfConnectionStatus(:final connectionStatus)) {
      _connection = connectionStatus;
    }
    _events.add(event);
  }

  final av = FakeToxAv();

  @override
  api.ToxAv startAv() => av;

  @override
  api.Connection selfGetConnectionStatus() => _connection;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  int iterationInterval() => 20;

  @override
  ToxAddress selfGetAddress() => _address;

  @override
  void selfSetNospam(int nospam) {}

  @override
  void selfSetName(Uint8List name) => this.name = utf8.decode(name);

  @override
  void selfSetStatusMessage(Uint8List statusMessage) =>
      this.statusMessage = utf8.decode(statusMessage);

  @override
  api.FriendNumber friendAdd(ToxAddress address, Uint8List message) {
    final friendNumber = friendAddNorequest(address.publicKey);
    friendRequests.add((address, utf8.decode(message)));
    return friendNumber;
  }

  @override
  api.FriendNumber friendAddNorequest(PublicKey publicKey) {
    final existing = friends.indexOf(publicKey);
    if (existing != -1 && !deletedFriends.contains(existing)) {
      throw const api.ApiException(api.FriendAddError.alreadySent);
    }
    friends.add(publicKey);
    return api.FriendNumber(friends.length - 1);
  }

  int tcpRelaysAdded = 0;

  @override
  void addTcpRelay(String host, int port, PublicKey publicKey) {
    if (throwOnBootstrap) {
      throw const api.ApiException(api.BootstrapError.badHost);
    }
    tcpRelaysAdded++;
  }

  @override
  void bootstrap(String host, int port, PublicKey publicKey) {
    if (throwOnBootstrap) {
      throw const api.ApiException(api.BootstrapError.badHost);
    }
  }

  @override
  void friendDelete(api.FriendNumber friendNumber) =>
      deletedFriends.add(friendNumber.value);

  @override
  void selfSetTyping(api.FriendNumber friendNumber, bool typing) =>
      typingTold.add((friendNumber.value, typing));

  @override
  PublicKey friendGetPublicKey(api.FriendNumber friendNumber) {
    final n = friendNumber.value;
    if (n < friends.length) {
      return friends[n];
    }
    return PublicKey(Uint8List.fromList(List.filled(32, n + 1)));
  }

  @override
  List<Event> iterate() {
    if (iterateError case final error?) {
      iterateError = null;
      throw error;
    }
    final result = List<Event>.from(_events);
    _events.clear();
    return result;
  }

  @override
  void kill() {
    _logger.d('Killing Tox instance');
    isAlive = false;
  }

  @override
  void friendSendLosslessPacket(api.FriendNumber friendNumber, Uint8List data) {
    if (unconnectedFriends.contains(friendNumber.value)) {
      throw const api.ApiException(
        api.FriendCustomPacketError.friendNotConnected,
      );
    }
    losslessPackets.add((friendNumber.value, data));
  }

  @override
  api.FriendMessageId friendSendMessage(
    api.FriendNumber friendNumber,
    api.MessageType type,
    Uint8List message,
  ) {
    if (friendNumber.value >= friends.length) {
      throw const api.ApiException(api.FriendSendMessageError.friendNotFound);
    }
    if (unreachableFriends.contains(friendNumber.value)) {
      throw const api.ApiException(
        api.FriendSendMessageError.friendNotConnected,
      );
    }
    if (sendQueueRoom case final room?) {
      if (room == 0) {
        throw const api.ApiException(api.FriendSendMessageError.sendQueueFull);
      }
      sendQueueRoom = room - 1;
    }
    final messageId = _nextMessageId++;
    sentMessages.add((friendNumber.value, messageId, utf8.decode(message)));
    return api.FriendMessageId(messageId);
  }

  @override
  void fileControl(
    api.FriendNumber friendNumber,
    api.FileNumber fileNumber,
    api.FileControl control,
  ) => fileControls.add((friendNumber.value, fileNumber.value, control));

  @override
  api.FileNumber fileSend(
    api.FriendNumber friendNumber,
    api.FileKind kind,
    int fileSize,
    FileId? fileId,
    Uint8List filename,
  ) {
    fileSends.add((friendNumber.value, fileSize, utf8.decode(filename)));
    fileSendKinds.add((kind, fileId));
    _nextChunk[(friendNumber.value, fileSends.length - 1)] = 0;
    return api.FileNumber(fileSends.length - 1);
  }

  @override
  void fileSeek(
    api.FriendNumber friendNumber,
    api.FileNumber fileNumber,
    int position,
  ) => fileSeeks.add((friendNumber.value, fileNumber.value, position));

  @override
  FileId fileGetFileId(
    api.FriendNumber friendNumber,
    api.FileNumber fileNumber,
  ) => FileId(
    fileIds[(friendNumber.value, fileNumber.value)] ??
        (Uint8List(32)
          ..[0] = friendNumber.value
          ..[1] = fileNumber.value),
  );

  @override
  void fileSendChunk(
    api.FriendNumber friendNumber,
    api.FileNumber fileNumber,
    int position,
    Uint8List data,
  ) {
    final key = (friendNumber.value, fileNumber.value);
    if (position != (_nextChunk[key] ?? position)) {
      throw const api.ApiException(api.FileSendChunkError.wrongPosition);
    }
    if (fullChunkQueues > 0) {
      fullChunkQueues--;
      throw const api.ApiException(api.FileSendChunkError.sendQueueFull);
    }
    _nextChunk[key] = position + data.length;
    fileChunks.add((friendNumber.value, fileNumber.value, position, data));
  }
}
