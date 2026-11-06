import 'dart:convert';

import 'package:btox/api/toxcore/tox_constants.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_details.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_merge.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart' show Profiles;
import 'package:btox/pages/group_pages.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/drafts.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/widgets/chat_avatar.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:btox/widgets/confirm_dialog.dart';
import 'package:btox/widgets/copy_text.dart';
import 'package:btox/widgets/database_write.dart';
import 'package:btox/widgets/dates.dart';
import 'package:btox/widgets/load_failed.dart';
import 'package:btox/widgets/mute_chat.dart';
import 'package:btox/widgets/remove_chat.dart';
import 'package:btox/widgets/text_dialog.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How long ago a relayed name was seen to show without asking.
const _recentlySeen = Duration(days: 30);
// Where a ListTile's title starts, after its leading widget.
const _listTileTitleInset = 72.0;

/// Who a chat is with: a friend, or the people in a group or conference.
final class ChatDetailsPage extends ConsumerWidget {
  final ChatRef chat;

  const ChatDetailsPage({super.key, required this.chat});

  static Route<void> route(ChatRef chat) =>
      MaterialPageRoute(builder: (_) => ChatDetailsPage(chat: chat));

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(),
    body: switch (ref.watch(chatDetailsProvider(chat))) {
      AsyncData(value: final details) => _Details(details: details),
      AsyncError() => const LoadFailed(),
      _ => const Center(child: CircularProgressIndicator()),
    },
  );
}

final class _Details extends ConsumerWidget {
  final ChatDetails details;

  const _Details({required this.details});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final summary = details.summary;
    final about = details.topic ?? details.statusMessage;
    final members = details.members;
    final relayed = details.relayed;
    final error = theme.colorScheme.error;
    final merged =
        (ref.watch(chatMergeProvider(summary.ref))?.sides.length ?? 0) > 1;
    final group = switch (summary.key) {
      final GroupChatId id when !summary.closed => ChatId.group(id),
      _ => null,
    };
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const SizedBox(height: 8),
        Center(child: ChatAvatar.of(summary, online: summary.online, size: 80)),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            summary.name ?? l10n.defaultContactName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        if (about != null && about.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              about,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_statusText(l10n, details.status) case final status?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              status,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
        if (!summary.closed) _Mute(chat: summary),
        // Tox only sends files to friends.
        if (summary.key is PublicKey && !summary.closed)
          _PicturesAsQoi(chat: summary.ref),
        if (summary.key case final PublicKey pk)
          _Key(
            title: l10n.publicKey,
            value: pk.toJson(),
            copied: l10n.publicKeyCopied,
          ),
        if (switch (summary.key) {
              final GroupChatId id => ChatId.group(id),
              final ConferenceId id => ChatId.conference(id),
              _ => null,
            }
            case final chat? when !summary.closed)
          _InviteFriends(chat: chat, profile: summary.ref.profile),
        if (group != null && details.maySetTopic)
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.changeTopic),
            onTap: () async {
              final topic = await askText(
                context,
                title: l10n.groupTopic,
                initial: details.topic ?? '',
                multiline: true,
                validator: (text) =>
                    utf8.encode(text.trim()).length > toxGroupMaxTopicLength
                    ? l10n.topicTooLong
                    : null,
              );
              if (topic != null && context.mounted) {
                await wantFact(
                  context,
                  ref,
                  summary.ref.profile,
                  Subject.chat(group),
                  FactValue.topic(topic.trim()),
                );
              }
            },
          ),
        if (group != null && details.selfRole == Role.founder)
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(l10n.groupSettings),
            onTap: () =>
                Navigator.push(context, GroupSettingsPage.route(summary.ref)),
          ),
        if (summary.key case final GroupChatId id)
          _Key(
            title: l10n.chatId,
            value: id.toJson(),
            copied: l10n.chatIdCopied,
          ),
        if (summary.key is! PublicKey) ...[
          const Divider(),
          if (members == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.membersWhileOnline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.chatMembers(members.length + 1),
                style: theme.textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: CircleIdenticon(bytes: details.selfKey),
              title: Text(details.selfName ?? l10n.defaultContactName),
              subtitle: _subtitle([
                l10n.you,
                _roleText(l10n, details.selfRole),
              ]),
            ),
            for (final member in members) ...[
              ListTile(
                leading: CircleIdenticon(bytes: member.pk),
                title: Text(memberName(l10n, member.name, member.pk)),
                subtitle: _subtitle([
                  _roleText(l10n, member.role),
                  _statusText(l10n, member.status),
                ]),
                // Conferences have no private messages.
                trailing: summary.key is GroupChatId
                    ? IconButton(
                        icon: const Icon(Icons.lock_outline),
                        tooltip: l10n.messagePrivately,
                        onPressed: () {
                          ref
                                  .read(chatDraftProvider(summary.ref))
                                  .privately
                                  .value =
                              member.pk;
                          Navigator.of(context).pop();
                        },
                      )
                    : null,
                onTap:
                    group != null &&
                        (details.mayRemove(member) ||
                            details.rolesFor(member).isNotEmpty)
                    ? () => _moderate(context, ref, details, group, member)
                    : null,
              ),
              if (relayed != null && member.pk == relayed.bot)
                _SeenNames(relayed: relayed, underBot: true),
            ],
          ],
          if (relayed != null &&
              !(members?.any((m) => m.pk == relayed.bot) ?? false))
            _SeenNames(relayed: relayed, underBot: false),
        ],
        if (switch (summary.key) {
              final PublicKey friend => ListTile(
                leading: Icon(Icons.delete_outline, color: error),
                title: Text(l10n.deleteContact, style: TextStyle(color: error)),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  if (await deleteContact(context, ref, summary, friend)) {
                    navigator.popUntil((route) => route.isFirst);
                  }
                },
              ),
              // Leaving a merged chat would leave only one of its chats.
              _ when summary.chatId != null && !summary.closed && !merged =>
                ListTile(
                  leading: Icon(Icons.logout, color: error),
                  title: Text(l10n.leaveChat, style: TextStyle(color: error)),
                  onTap: () => leaveChat(context, ref, summary),
                ),
              _ => null,
            }
            case final remove?) ...[
          const Divider(),
          remove,
        ],
      ],
    );
  }
}

/// Who has spoken through a relay bot, not who is there now.
final class _SeenNames extends HookWidget {
  final RelayedNames relayed;
  final bool underBot;

  const _SeenNames({required this.relayed, required this.underBot});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final all = useState(false);
    final since = clock.now().subtract(_recentlySeen);
    final shown = all.value
        ? relayed.seen
        : relayed.seen.where((s) => s.last.isAfter(since)).toList();
    final padding = EdgeInsets.only(
      left: underBot ? _listTileTitleInset : 16,
      right: 16,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: padding,
          child: Text(
            l10n.seenThrough(relayed.name),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final seen in shown)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: padding,
            title: Text(seen.name),
            trailing: Text(
              recentText(context, seen.last),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (shown.length < relayed.seen.length)
          ListTile(
            dense: true,
            contentPadding: padding,
            title: Text(
              l10n.showMoreSeen(relayed.seen.length - shown.length),
              style: TextStyle(color: theme.colorScheme.primary),
            ),
            onTap: () => all.value = true,
          ),
      ],
    );
  }
}

final class _Mute extends ConsumerWidget {
  final ChatSummary chat;

  const _Mute({required this.chat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return switch (chat.mute) {
      null => ListTile(
        leading: const Icon(Icons.notifications_off_outlined),
        title: Text(l10n.muteChat),
        onTap: () => muteChat(context, ref, chat),
      ),
      final mute => ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: Text(l10n.unmuteChat),
        subtitle: Text(mutedText(context, mute)),
        onTap: () => unmuteChat(context, ref, chat.ref),
      ),
    };
  }
}

final class _PicturesAsQoi extends ConsumerWidget {
  final ChatRef chat;

  const _PicturesAsQoi({required this.chat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return SwitchListTile(
      secondary: const Icon(Icons.image_outlined),
      title: Text(l10n.sendPicturesAsQoi),
      subtitle: Text(l10n.sendPicturesAsQoiHint),
      value: ref.watch(pictureFormatProvider(chat)) == PictureEncoding.qoi,
      onChanged: (qoi) async {
        final scope = Scope.conversation(chat.graph);
        await ref.write(
          context,
          (db) => db.addIntent(
            chat.profile,
            qoi
                ? SettingContent(
                    scope: scope,
                    setting: const Kept(
                      Setting.pictureFormat(PictureEncoding.qoi),
                    ),
                  )
                : ClearSetting(scope: scope, kind: Setting.pictureFormatKind),
          ),
        );
      },
    );
  }
}

/// A friend's public key, or a group's chat ID that others join it by.
final class _Key extends StatelessWidget {
  final String title;
  final String value;
  final String copied;

  const _Key({required this.title, required this.value, required this.copied});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      title: Text(title),
      subtitle: Text(value, style: const TextStyle(fontFamily: 'monospace')),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        tooltip: l10n.copy,
        onPressed: () => copyText(ScaffoldMessenger.of(context), value, copied),
      ),
    );
  }
}

/// Offers what we may do to [member] of [group]: give them another role, or
/// remove them.
Future<void> _moderate(
  BuildContext context,
  WidgetRef ref,
  ChatDetails details,
  ChatId group,
  ChatMember member,
) async {
  final l10n = AppLocalizations.of(context)!;
  final error = Theme.of(context).colorScheme.error;
  final name = memberName(l10n, member.name, member.pk);
  final picked = await showModalBottomSheet<FactValue>(
    context: context,
    // As tall as it needs, and scrolls where the screen isn't.
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleIdenticon(bytes: member.pk),
              title: Text(name),
              subtitle: _subtitle([_roleText(l10n, member.role)]),
            ),
            const Divider(),
            for (final role in details.rolesFor(member))
              ListTile(
                leading: Icon(switch (role) {
                  Role.moderator => Icons.shield_outlined,
                  Role.observer => Icons.visibility_outlined,
                  Role.founder || Role.user => Icons.person_outline,
                }),
                title: Text(switch (role) {
                  Role.moderator => l10n.makeModerator,
                  Role.observer => l10n.makeObserver,
                  Role.founder || Role.user => l10n.makeUser,
                }),
                onTap: () => Navigator.pop(sheet, FactValue.role(role)),
              ),
            if (details.mayRemove(member))
              ListTile(
                leading: Icon(Icons.person_remove_outlined, color: error),
                title: Text(l10n.removeMember, style: TextStyle(color: error)),
                onTap: () =>
                    Navigator.pop(sheet, const FactValue.present(false)),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) {
    return;
  }
  if (picked is PresentValue &&
      !await confirm(
        context,
        title: l10n.removeMember,
        message: l10n.removeMemberMessage(name),
        action: l10n.remove,
      )) {
    return;
  }
  if (context.mounted) {
    await wantFact(
      context,
      ref,
      details.summary.ref.profile,
      Subject.peer(group, member.pk),
      picked,
    );
  }
}

// Ordinary users and online friends need no label.
String? _roleText(AppLocalizations l10n, Role? role) => switch (role) {
  Role.founder => l10n.roleFounder,
  Role.moderator => l10n.roleModerator,
  Role.observer => l10n.roleObserver,
  Role.user || null => null,
};

String? _statusText(AppLocalizations l10n, UserStatus? status) =>
    switch (status) {
      UserStatus.away => l10n.statusAway,
      UserStatus.busy => l10n.statusBusy,
      UserStatus.online || null => null,
    };

Widget? _subtitle(List<String?> parts) => switch (parts.nonNulls.join(' · ')) {
  '' => null,
  final text => Text(text),
};

/// Only online friends can be invited.
final class _InviteFriends extends ConsumerWidget {
  final ChatId chat;
  final Id<Profiles> profile;

  const _InviteFriends({required this.chat, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: const Icon(Icons.person_add_outlined),
      title: Text(l10n.inviteFriends),
      onTap: () async {
        final friends = [
          for (final chat
              in ref.read(chatsForProfileProvider(profile)).value ??
                  const <ChatSummary>[])
            if (chat.key is PublicKey && chat.online == true) chat,
        ];
        final friend = await showDialog<ChatSummary>(
          context: context,
          builder: (dialog) => SimpleDialog(
            title: Text(l10n.inviteFriends),
            children: [
              if (friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.noFriendsOnline),
                ),
              for (final friend in friends)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialog, friend),
                  child: Text(friend.name ?? l10n.defaultContactName),
                ),
            ],
          ),
        );
        if (friend == null || !context.mounted) {
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        final invited = l10n.invitedFriend(
          friend.name ?? l10n.defaultContactName,
        );
        final content = InviteToChat(
          chat: chat,
          friend: friend.key as PublicKey,
        );
        if (await ref.write(context, (db) => db.addIntent(profile, content))) {
          messenger.showSnackBar(SnackBar(content: Text(invited)));
        }
      },
    );
  }
}
