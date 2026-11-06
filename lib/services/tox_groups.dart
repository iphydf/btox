import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/api/toxcore/tox_constants.dart';
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/logger.dart';
import 'package:btox/messages/split_message.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/services/tox_facts.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/home.dart';

const _logger = Logger(['ToxGroups']);

final class _Group {
  final GroupChatId id;
  final peers = <GroupPeerNumber, PublicKey>{};

  _Group(this.id);

  ChatId get chat => ChatId.group(id);
}

/// Runs the account's groups in this device's own Tox.
///
/// Each group is saved separately, so Tox can rejoin it without the rest of
/// its savedata.
final class ToxGroups {
  final Tox _tox;
  final Database _db;
  final Id<Profiles> _profileId;
  final Home _home;
  final FriendNumber? Function(PublicKey) _friendNumberOf;
  final PublicKey? Function(FriendNumber) _publicKeyOf;
  final String Function() _nickname;

  final void Function(
    GraphId chat,
    EventContent content, {
    String? title,
    String? sender,
  })
  _incoming;

  final _groups = <GroupNumber, _Group>{};

  // Invites by group number, while joining.
  final _joining = <GroupNumber, EventId>{};

  ToxGroups(
    this._tox,
    this._db,
    this._profileId,
    this._home,
    this._friendNumberOf,
    this._publicKeyOf,
    this._nickname,
    this._incoming,
  );

  Future<void> load() async {
    for (final state in await _db.getChatSaves(_profileId, ChatKind.group)) {
      try {
        await _joined(_tox.groupLoadSavedata(state));
      } on ApiException catch (e) {
        _logger.w('A kept group did not load: $e');
      }
    }
  }

  void handleEvent(Event event) {
    _logger.unawaited('handle a group event', _handle(event));
  }

  Future<void> _handle(Event event) async {
    switch (event) {
      case ToxEventGroupInvite(
        :final friendNumber,
        :final inviteData,
        :final groupName,
      ):
        if (_publicKeyOf(friendNumber) case final from?) {
          await _home.record(
            _home.account,
            ChatInvite(
              from: from,
              kind: ChatKind.group,
              name: utf8.decode(groupName, allowMalformed: true),
              invite: inviteData,
            ),
          );
        }
      case ToxEventGroupSelfJoin(:final groupNumber):
        if (_joining.remove(groupNumber) case final invite?) {
          final chat = ChatId.group(_tox.groupGetChatId(groupNumber));
          await _home.record(
            _home.account,
            InviteJoined(invite: invite, chat: chat),
          );
        }
        await _joined(groupNumber);
      case ToxEventGroupJoinFail(:final groupNumber, :final failType):
        if (_joining.remove(groupNumber) case final invite?) {
          await _home.record(
            _home.account,
            InviteJoined(
              invite: invite,
              needsPassword: failType == GroupJoinFail.invalidPassword,
            ),
          );
        }
        await _gone(groupNumber, leave: true);
      case ToxEventGroupPeerJoin(:final groupNumber, :final peerId):
        if (_groups[groupNumber] case final group?) {
          final pk = _tox.groupPeerGetPublicKey(groupNumber, peerId);
          group.peers[peerId] = pk;
          await _db.updateLiveFacts(_profileId, [
            (Subject.peer(group.chat, pk), const FactValue.present(true)),
            ..._peerFacts(groupNumber, group, peerId),
          ]);
          await _save(groupNumber);
        }
      case ToxEventGroupPeerExit(:final groupNumber, :final peerId):
        if (_groups[groupNumber] case final group?) {
          if (group.peers.remove(peerId) case final pk?) {
            await _db.updateLiveFacts(_profileId, [
              (Subject.peer(group.chat, pk), const FactValue.present(false)),
            ]);
          }
        }
      case ToxEventGroupPeerName(:final groupNumber, :final peerId) ||
          ToxEventGroupPeerStatus(:final groupNumber, :final peerId):
        if (_groups[groupNumber] case final group?) {
          await _db.updateLiveFacts(
            _profileId,
            _peerFacts(groupNumber, group, peerId),
          );
        }
      case ToxEventGroupModeration(
        :final groupNumber,
        :final targetPeerId,
        :final modType,
      ):
        if (_groups[groupNumber] case final group?) {
          final self = _tox.groupSelfGetPeerId(groupNumber);
          if (targetPeerId == self && modType == GroupModEvent.kick) {
            await _gone(groupNumber, leave: true);
          } else {
            await _db.updateLiveFacts(
              _profileId,
              _peerFacts(groupNumber, group, targetPeerId),
            );
            await _chatFacts(groupNumber, group);
            await _save(groupNumber);
          }
        }
      case ToxEventGroupMessage(
        :final groupNumber,
        :final peerId,
        :final messageType,
        :final message,
      ):
        if (_groups[groupNumber] case final group?) {
          final from = group.peers[peerId];
          final sender = _peerName(groupNumber, peerId);
          _incoming(
            group.chat.graph,
            Received(
              from: from,
              sender: sender,
              message: message,
              kind: messageType,
            ),
            title: _name(groupNumber),
            sender: sender,
          );
        }
      case ToxEventGroupPrivateMessage(
        :final groupNumber,
        :final peerId,
        :final messageType,
        :final message,
      ):
        if (_groups[groupNumber] case final group?) {
          if (group.peers[peerId] case final from?) {
            final sender = _peerName(groupNumber, peerId);
            _incoming(
              group.chat.graph,
              ReceivedPrivately(
                from: from,
                sender: sender,
                message: message,
                kind: messageType,
              ),
              title: _name(groupNumber),
              sender: sender,
            );
          }
        }
      case ToxEventGroupTopic(:final groupNumber) ||
          ToxEventGroupPrivacyState(:final groupNumber) ||
          ToxEventGroupPeerLimit(:final groupNumber) ||
          ToxEventGroupPassword(:final groupNumber) ||
          ToxEventGroupTopicLock(:final groupNumber) ||
          ToxEventGroupVoiceState(:final groupNumber):
        if (_groups[groupNumber] case final group?) {
          await _chatFacts(groupNumber, group);
          await _save(groupNumber);
        }
      default:
        break;
    }
  }

  /// Called once the pages' intents are account events.
  Future<void> written(List<NewEvent> events) async {
    for (final (id, event, _) in events) {
      try {
        await _carryOut(id, event);
      } on ApiException catch (e) {
        _logger.w('Tox refused ${event.content.runtimeType}: $e');
      }
    }
  }

  Future<void> _carryOut(EventId id, SyncEvent event) async {
    switch (event.content) {
      case NewChat(kind: ChatKind.group, :final name, :final privacy):
        final number = _tox.groupNew(
          privacy.tox,
          utf8.encode(name),
          utf8.encode(_nickname()),
        );
        await _home.record(
          _home.account,
          ChatJoined(intent: id, chat: await _joined(number)),
        );
      case NewChat():
        // This Tox has no conferences, so the intent ends without a chat.
        await _home.record(_home.account, ChatJoined(intent: id));
      case JoinChat(:final chatId, :final password):
        _tox.groupJoin(
          chatId,
          utf8.encode(_nickname()),
          utf8.encode(password ?? ''),
        );
        await _home.record(
          _home.account,
          ChatJoined(intent: id, chat: ChatId.group(chatId)),
        );
      case AnswerInvite(:final invite, join: true, :final password):
        if (_home.store[invite]?.content case ChatInvite(
          :final from,
          kind: ChatKind.group,
          invite: final data,
        )) {
          if (_friendNumberOf(from) case final friendNumber?) {
            final number = _tox.groupInviteAccept(
              friendNumber,
              data,
              utf8.encode(_nickname()),
              utf8.encode(password ?? ''),
            );
            _joining[number] = invite;
          }
        }
      case InviteToChat(chat: GroupChat(:final id), :final friend):
        if ((_numberOf(id), _friendNumberOf(friend)) case (
          final number?,
          final friendNumber?,
        )) {
          _tox.groupInviteFriend(number, friendNumber);
        }
      case Wish(:final subject, :final value):
        await _wish(subject, value);
      case Send(:final message, :final kind) when _chatOf(event.graph) != null:
        final number = _chatOf(event.graph)!;
        for (final part in splitMessage(message, toxGroupMaxMessageLength)) {
          _tox.groupSendMessage(number, kind, part);
        }
        await _home.sent(id);
      case SendPrivately(:final to, :final message, :final kind)
          when _chatOf(event.graph) != null:
        final number = _chatOf(event.graph)!;
        final peer = _peerOf(number, to);
        if (peer != null) {
          for (final part in splitMessage(message, toxGroupMaxMessageLength)) {
            _tox.groupSendPrivateMessage(number, peer, kind, part);
          }
          await _home.sent(id);
        }
      default:
        break;
    }
  }

  Future<void> _wish(Subject subject, FactValue value) async {
    switch ((subject, value)) {
      case (ChatSubject(chat: GroupChat(:final id)), _)
          when _numberOf(id) != null:
        final number = _numberOf(id)!;
        switch (value) {
          case JoinedValue(joined: false):
            await _gone(number, leave: true);
            return;
          case TopicValue(:final topic):
            _tox.groupSetTopic(number, utf8.encode(topic));
          case SelfNameValue(:final name) when name.isNotEmpty:
            _tox.groupSelfSetName(number, utf8.encode(name));
          case PrivacyValue(:final privacy):
            _tox.groupSetPrivacyState(number, privacy.tox);
          case PeerLimitValue(:final limit):
            _tox.groupSetPeerLimit(number, limit);
          case PasswordValue(:final password):
            _tox.groupSetPassword(number, utf8.encode(password));
          case TopicLockValue(:final locked):
            _tox.groupSetTopicLock(
              number,
              locked ? GroupTopicLock.enabled : GroupTopicLock.disabled,
            );
          case VoiceStateValue(:final voiceState):
            _tox.groupSetVoiceState(number, voiceState.tox);
          default:
            return;
        }
        await _chatFacts(number, _groups[number]!);
        await _save(number);
      case (PeerSubject(chat: GroupChat(:final id), :final pk), _)
          when _numberOf(id) != null:
        final number = _numberOf(id)!;
        final peer = _peerOf(number, pk);
        if (peer == null) {
          return;
        }
        switch (value) {
          case PresentValue(present: false):
            _tox.groupKickPeer(number, peer);
          case RoleValue(:final role):
            _tox.groupSetRole(number, peer, role.tox);
          default:
            break;
        }
      default:
        break;
    }
  }

  Future<ChatId> _joined(GroupNumber number) async {
    final group = _groups[number] ??= _Group(_tox.groupGetChatId(number));
    await _chatFacts(number, group);
    await _save(number);
    return group.chat;
  }

  Future<void> _gone(GroupNumber number, {required bool leave}) async {
    final group = _groups.remove(number);
    if (leave) {
      try {
        _tox.groupLeave(number, Uint8List(0));
      } on ApiException catch (e) {
        _logger.w('Tox did not leave group $number: $e');
      }
    }
    if (group == null) {
      return;
    }
    await _db.forgetChat(_profileId, group.chat);
    await _db.updateLiveFacts(_profileId, [
      for (final pk in group.peers.values)
        (Subject.peer(group.chat, pk), const FactValue.present(false)),
    ]);
    await _home.fact(Subject.chat(group.chat), const FactValue.joined(false));
  }

  Future<void> _chatFacts(GroupNumber number, _Group group) async {
    final subject = Subject.chat(group.chat);
    for (final value in [
      const FactValue.joined(true),
      FactValue.name(_name(number)),
      FactValue.topic(_text(_tox.groupGetTopic(number))),
      FactValue.selfName(_text(_tox.groupSelfGetName(number))),
      FactValue.role(_tox.groupSelfGetRole(number).fact),
      FactValue.privacy(_tox.groupGetPrivacyState(number).fact),
      FactValue.peerLimit(_tox.groupGetPeerLimit(number)),
      FactValue.password(_text(_tox.groupGetPassword(number))),
      FactValue.topicLock(
        _tox.groupGetTopicLock(number) == GroupTopicLock.enabled,
      ),
      FactValue.voiceState(_tox.groupGetVoiceState(number).fact),
      FactValue.selfKey(_tox.groupSelfGetPublicKey(number)),
    ]) {
      await _home.fact(subject, value);
    }
  }

  List<Fact> _peerFacts(
    GroupNumber number,
    _Group group,
    GroupPeerNumber peer,
  ) {
    final pk = group.peers[peer];
    if (pk == null) {
      return const [];
    }
    final subject = Subject.peer(group.chat, pk);
    return [
      (subject, FactValue.name(_peerName(number, peer))),
      (subject, FactValue.status(_tox.groupPeerGetStatus(number, peer).fact)),
      (subject, FactValue.role(_tox.groupPeerGetRole(number, peer).fact)),
    ];
  }

  Future<void> _save(GroupNumber number) async {
    if (_groups[number] case final group?) {
      await _db.saveChat(_profileId, group.chat, _tox.groupGetSavedata(number));
    }
  }

  GroupNumber? _numberOf(GroupChatId id) => [
    for (final MapEntry(key: number, value: group) in _groups.entries)
      if (group.id == id) number,
  ].firstOrNull;

  GroupNumber? _chatOf(GraphId graph) => [
    for (final MapEntry(key: number, value: group) in _groups.entries)
      if (group.chat.graph == graph) number,
  ].firstOrNull;

  GroupPeerNumber? _peerOf(GroupNumber number, PublicKey pk) => [
    for (final MapEntry(key: peer, value: key)
        in _groups[number]!.peers.entries)
      if (key == pk) peer,
  ].firstOrNull;

  String _name(GroupNumber number) => _text(_tox.groupGetName(number));

  String _peerName(GroupNumber number, GroupPeerNumber peer) =>
      _text(_tox.groupPeerGetName(number, peer));

  static String _text(Uint8List bytes) =>
      utf8.decode(bytes, allowMalformed: true);
}
