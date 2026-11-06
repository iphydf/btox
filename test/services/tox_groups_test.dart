import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart' as api;
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/services/tox_groups.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/home.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final _me = PublicKey(Uint8List(32));
final _chatId = GroupChatId(Uint8List.fromList(List.filled(32, 7)));
final _bob = PublicKey(Uint8List.fromList(List.filled(32, 2)));

/// A fake Tox with one group. Methods the tests don't use throw.
final class _GroupTox extends api.Tox {
  String? group;
  final sent = <String>[];
  var left = false;

  @override
  api.GroupNumber groupNew(
    api.GroupPrivacyState privacyState,
    Uint8List groupName,
    Uint8List name,
  ) {
    group = utf8.decode(groupName);
    return const api.GroupNumber(0);
  }

  @override
  GroupChatId groupGetChatId(api.GroupNumber groupNumber) => _chatId;
  @override
  Uint8List groupGetName(api.GroupNumber groupNumber) => utf8.encode(group!);
  @override
  Uint8List groupGetTopic(api.GroupNumber groupNumber) => utf8.encode('plans');
  @override
  Uint8List groupSelfGetName(api.GroupNumber groupNumber) => utf8.encode('Me');
  @override
  api.GroupRole groupSelfGetRole(api.GroupNumber groupNumber) =>
      api.GroupRole.founder;
  @override
  api.GroupPrivacyState groupGetPrivacyState(api.GroupNumber groupNumber) =>
      api.GroupPrivacyState.private;
  @override
  int groupGetPeerLimit(api.GroupNumber groupNumber) => 100;
  @override
  Uint8List groupGetPassword(api.GroupNumber groupNumber) => Uint8List(0);
  @override
  api.GroupTopicLock groupGetTopicLock(api.GroupNumber groupNumber) =>
      api.GroupTopicLock.enabled;
  @override
  api.GroupVoiceState groupGetVoiceState(api.GroupNumber groupNumber) =>
      api.GroupVoiceState.all;
  @override
  PublicKey groupSelfGetPublicKey(api.GroupNumber groupNumber) => _me;
  @override
  Uint8List groupGetSavedata(api.GroupNumber groupNumber) =>
      utf8.encode('state of $group');
  @override
  api.GroupNumber groupLoadSavedata(Uint8List savedata) {
    group = utf8.decode(savedata).replaceFirst('state of ', '');
    return const api.GroupNumber(0);
  }

  @override
  api.GroupMessageId groupSendMessage(
    api.GroupNumber groupNumber,
    api.MessageType type,
    Uint8List message,
  ) {
    sent.add(utf8.decode(message));
    return api.GroupMessageId(sent.length);
  }

  @override
  void groupLeave(api.GroupNumber groupNumber, Uint8List partMessage) =>
      left = true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
  @override
  PublicKey groupPeerGetPublicKey(
    api.GroupNumber groupNumber,
    api.GroupPeerNumber groupPeerNumber,
  ) => _bob;
  @override
  Uint8List groupPeerGetName(
    api.GroupNumber groupNumber,
    api.GroupPeerNumber groupPeerNumber,
  ) => utf8.encode('Bob');
  @override
  api.UserStatus groupPeerGetStatus(
    api.GroupNumber groupNumber,
    api.GroupPeerNumber peer,
  ) => api.UserStatus.away;
  @override
  api.GroupRole groupPeerGetRole(
    api.GroupNumber groupNumber,
    api.GroupPeerNumber peer,
  ) => api.GroupRole.user;
}

void main() {
  late Database db;
  late Id<Profiles> profileId;
  late Home home;
  late _GroupTox tox;
  late List<(GraphId, EventContent, String?)> incoming;

  ToxGroups groupsOf(_GroupTox tox) => ToxGroups(
    tox,
    db,
    profileId,
    home,
    (_) => null,
    (_) => null,
    () => 'Me',
    (chat, content, {title, sender}) => incoming.add((chat, content, title)),
  );

  setUp(() async {
    db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    profileId = await db.addProfile(
      ProfilesCompanion.insert(
        settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: _me,
        nospam: ToxAddressNospam(0),
      ),
    );
    home = await Home.load(db, await db.watchProfile(profileId).first);
    tox = _GroupTox();
    incoming = [];
  });

  Future<NewEvent> asked(EventContent content, [GraphId? graph]) async =>
      (await home.record(graph ?? home.account, content))!;

  final chat = Subject.chat(ChatId.group(_chatId));

  test('founds a group the pages ask for, and keeps it for Tox', () async {
    final groups = groupsOf(tox);
    final founding = await asked(
      const NewChat(
        kind: ChatKind.group,
        name: 'Lab',
        privacy: Privacy.private,
      ),
    );
    await groups.written([founding]);
    expect(tox.group, 'Lab');
    expect(home.state.facts.of(chat), contains(const FactValue.name('Lab')));
    expect(home.state.facts.of(chat), contains(const FactValue.joined(true)));
    expect(
      [
        for (final (_, event) in home.store.eventsIn(home.account))
          if (event.content case ChatJoined(:final chat?)) chat,
      ],
      [ChatId.group(_chatId)],
    );
    expect(await db.getChatSaves(profileId, ChatKind.group), [
      utf8.encode('state of Lab'),
    ]);

    // A restarted Tox loads the group back from the saved state.
    final again = _GroupTox();
    await groupsOf(again).load();
    expect(again.group, 'Lab');
  });

  test('sends and receives in a group, and leaves it', () async {
    final groups = groupsOf(tox);
    await groups.written([
      await asked(
        const NewChat(
          kind: ChatKind.group,
          name: 'Lab',
          privacy: Privacy.private,
        ),
      ),
    ]);
    final graph = ChatId.group(_chatId).graph;

    final send = await asked(
      Send(
        sender: 'Me',
        message: utf8.encode('hi all'),
        kind: api.MessageType.normal,
      ),
      graph,
    );
    await groups.written([send]);
    expect(tox.sent, ['hi all']);
    expect(
      home.store.eventsIn(graph).map((e) => e.$2.content),
      contains(Sent(intent: send.$1)),
    );

    groups.handleEvent(
      const ToxEventGroupPeerJoin(
        groupNumber: api.GroupNumber(0),
        peerId: api.GroupPeerNumber(3),
      ),
    );
    groups.handleEvent(
      ToxEventGroupMessage(
        groupNumber: api.GroupNumber(0),
        peerId: api.GroupPeerNumber(3),
        messageType: api.MessageType.normal,
        message: utf8.encode('hi Me'),
        messageId: api.GroupMessageId(1),
      ),
    );
    await pumpEventQueue();
    expect(incoming.single.$1, graph);
    expect(incoming.single.$3, 'Lab');
    expect(
      incoming.single.$2,
      isA<Received>()
          .having((r) => r.from, 'from', _bob)
          .having((r) => r.sender, 'sender', 'Bob'),
    );

    await groups.written([
      await asked(Wish(subject: chat, value: const FactValue.joined(false))),
    ]);
    expect(tox.left, isTrue);
    expect(home.state.facts.of(chat), contains(const FactValue.joined(false)));
    expect(await db.getChatSaves(profileId, ChatKind.group), isEmpty);
  });
}
