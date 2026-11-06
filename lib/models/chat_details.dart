import 'package:btox/models/chat_merge.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_details.freezed.dart';

@freezed
abstract class ChatMember with _$ChatMember {
  const factory ChatMember({
    required PublicKey pk,
    String? name,
    Role? role,
    UserStatus? status,
  }) = _ChatMember;
}

/// What a chat's details page shows, beyond its summary.
@freezed
abstract class ChatDetails with _$ChatDetails {
  const factory ChatDetails({
    required ChatSummary summary,
    // A friend's.
    String? statusMessage,
    UserStatus? status,
    // A group's or conference's.
    String? topic,
    // What the others in it see us as.
    required PublicKey selfKey,
    String? selfName,
    Role? selfRole,
    // Who else is in it, while Tox says. Null for friend chats, and where the
    // account's Tox isn't running.
    List<ChatMember>? members,
    // Where it has a relay bot.
    RelayedNames? relayed,
    // A group's settings, which only its founder may change.
    Privacy? privacy,
    int? peerLimit,
    // Empty for none.
    String? password,
    bool? topicLock,
    VoiceState? voiceState,
  }) = _ChatDetails;

  const ChatDetails._();

  /// [live] is only used while the account's Tox is [running].
  factory ChatDetails.of(
    ChatSummary summary,
    PublicKey selfKey,
    AccountState account,
    Facts? live, {
    required bool running,
    RelayedNames? relayed,
  }) {
    T? fact<T>(Facts? facts, Subject subject, T? Function(FactValue) pick) =>
        facts?.find(subject, pick);
    String? topicOf(FactValue v) => v is TopicValue ? v.topic : null;
    Role? roleOf(FactValue v) => v is RoleValue ? v.role : null;
    PublicKey? keyOf(FactValue v) => v is SelfKeyValue ? v.key : null;
    UserStatus? statusOf(FactValue v) => v is StatusValue ? v.status : null;

    final ChatId chat;
    switch (summary.key) {
      case final PublicKey pk:
        final friend = Subject.friend(pk);
        return ChatDetails(
          summary: summary,
          selfKey: selfKey,
          statusMessage: fact(
            account.facts,
            friend,
            (v) => v is StatusMessageValue ? v.message : null,
          ),
          status: fact(live, friend, statusOf),
        );
      case final GroupChatId id:
        chat = ChatId.group(id);
      case final ConferenceId id:
        chat = ChatId.conference(id);
      default:
        return ChatDetails(summary: summary, selfKey: selfKey);
    }
    final subject = Subject.chat(chat);
    // Conferences have only a title, their name.
    T? kept<T>(T? Function(FactValue) pick) =>
        chat is GroupChat ? fact(account.facts, subject, pick) : null;
    return ChatDetails(
      summary: summary,
      topic: kept(topicOf),
      selfKey: fact(account.facts, subject, keyOf) ?? selfKey,
      selfName:
          fact(
            account.facts,
            subject,
            (v) => v is SelfNameValue ? v.name : null,
          ) ??
          account.name,
      selfRole: fact(account.facts, subject, roleOf),
      members: live != null && running
          ? ([
              for (final peer in live.subjects)
                if (peer case PeerSubject(chat: final c, :final pk)
                    when c == chat)
                  ChatMember(
                    pk: pk,
                    name: live.nameOf(peer),
                    role: live.find(peer, roleOf),
                    status: live.find(peer, statusOf),
                  ),
            ]..sort(_byRoleThenName))
          : null,
      relayed: relayed,
      privacy: kept((v) => v is PrivacyValue ? v.privacy : null),
      peerLimit: kept((v) => v is PeerLimitValue ? v.limit : null),
      password: kept((v) => v is PasswordValue ? v.password : null),
      topicLock: kept((v) => v is TopicLockValue ? v.locked : null),
      voiceState: kept((v) => v is VoiceStateValue ? v.voiceState : null),
    );
  }

  /// As Tox allows: anyone but observers, or only moderators while the topic
  /// is locked.
  bool get maySetTopic => switch (selfRole) {
    Role.founder || Role.moderator => true,
    Role.user => topicLock != true,
    Role.observer || null => false,
  };

  /// The roles we may give [member], as Tox allows: the founder can change
  /// anyone else, moderators only users and observers.
  List<Role> rolesFor(ChatMember member) => [
    if (mayRemove(member))
      for (final role
          in selfRole == Role.founder
              ? const [Role.moderator, Role.user, Role.observer]
              : const [Role.user, Role.observer])
        if (role != (member.role ?? Role.user)) role,
  ];

  /// Whether we may remove [member] from the group, as for [rolesFor].
  bool mayRemove(ChatMember member) =>
      switch ((selfRole, member.role ?? Role.user)) {
        (Role.founder, final theirs) => theirs != Role.founder,
        (Role.moderator, Role.user || Role.observer) => true,
        _ => false,
      };
}

// One whose role Tox hasn't said yet shows as an ordinary member, so sorts
// as one.
int _byRoleThenName(ChatMember a, ChatMember b) {
  final role = (a.role ?? Role.user).index.compareTo(
    (b.role ?? Role.user).index,
  );
  return role != 0
      ? role
      : (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
}
