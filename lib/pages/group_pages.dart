import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_constants.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_details.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart' show Profiles;
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/widgets/database_write.dart';
import 'package:btox/widgets/load_failed.dart';
import 'package:btox/widgets/text_dialog.dart';
import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum _Founding { privateGroup, publicGroup, conference }

final class NewGroupPage extends HookConsumerWidget {
  final Id<Profiles> profile;

  const NewGroupPage({super.key, required this.profile});

  static Route<void> route(Id<Profiles> profile) =>
      MaterialPageRoute(builder: (_) => NewGroupPage(profile: profile));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final name = useTextEditingController();
    final founding = useState(_Founding.privateGroup);
    // Only the home device's Tox has conferences.
    final linked = ref.watch(
      profileProvider(profile).select((p) => p.value?.home != null),
    );

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) {
        return;
      }
      final content = NewChat(
        kind: founding.value == _Founding.conference
            ? ChatKind.conference
            : ChatKind.group,
        name: name.text.trim(),
        privacy: founding.value == _Founding.publicGroup
            ? Privacy.public
            : Privacy.private,
      );
      final navigator = Navigator.of(context);
      if (await ref.write(context, (db) => db.addIntent(profile, content))) {
        navigator.pop();
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.newGroup)),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton(
              segments: [
                ButtonSegment(
                  value: _Founding.privateGroup,
                  label: Text(l10n.privateGroup),
                ),
                ButtonSegment(
                  value: _Founding.publicGroup,
                  label: Text(l10n.publicGroup),
                ),
                if (linked)
                  ButtonSegment(
                    value: _Founding.conference,
                    label: Text(l10n.conference),
                  ),
              ],
              selected: {founding.value},
              onSelectionChanged: (chosen) => founding.value = chosen.single,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: name,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.groupName),
              validator: (text) => switch (utf8.encode(text?.trim() ?? '')) {
                [] => l10n.groupNameEmpty,
                final bytes when bytes.length > toxGroupMaxGroupNameLength =>
                  l10n.groupNameTooLong,
                _ => null,
              },
              onFieldSubmitted: (_) => submit(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: FilledButton(
                  onPressed: submit,
                  child: Text(l10n.create),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class JoinGroupPage extends HookConsumerWidget {
  final Id<Profiles> profile;

  const JoinGroupPage({super.key, required this.profile});

  static Route<void> route(Id<Profiles> profile) =>
      MaterialPageRoute(builder: (_) => JoinGroupPage(profile: profile));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final chatId = useTextEditingController();
    final password = useTextEditingController();

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) {
        return;
      }
      final content = JoinChat(
        chatId: GroupChatId(Uint8List.fromList(hex.decode(chatId.text.trim()))),
        password: password.text.isEmpty ? null : password.text,
      );
      final navigator = Navigator.of(context);
      if (await ref.write(context, (db) => db.addIntent(profile, content))) {
        navigator.pop();
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.joinGroup)),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: chatId,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.chatId),
              validator: (text) =>
                  RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(text?.trim() ?? '')
                  ? null
                  : l10n.chatIdInvalid,
            ),
            TextFormField(
              controller: password,
              decoration: InputDecoration(
                labelText: l10n.groupPassword,
                helperText: l10n.groupPasswordHelper,
              ),
              validator: (text) =>
                  utf8.encode(text ?? '').length > toxGroupMaxPasswordSize
                  ? l10n.groupPasswordTooLong
                  : null,
              onFieldSubmitted: (_) => submit(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: FilledButton(
                  onPressed: submit,
                  child: Text(l10n.joinInvite),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks the home device to make Tox match: pages then show what Tox says.
Future<bool> wantFact(
  BuildContext context,
  WidgetRef ref,
  Id<Profiles> profile,
  Subject subject,
  FactValue value,
) => ref.write(
  context,
  (db) => db.addIntent(profile, Wish(subject: subject, value: value)),
);

// Tox counts members in a uint16_t.
const _maxPeerLimit = 0xffff;

/// What only a group's founder may change.
final class GroupSettingsPage extends ConsumerWidget {
  final ChatRef chat;

  const GroupSettingsPage({super.key, required this.chat});

  static Route<void> route(ChatRef chat) =>
      MaterialPageRoute(builder: (_) => GroupSettingsPage(chat: chat));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupSettings)),
      body: switch (ref.watch(chatDetailsProvider(chat))) {
        AsyncData(
          value: ChatDetails(summary: ChatSummary(key: final GroupChatId id)) &&
              final details,
        ) =>
          _GroupSettings(chat: chat, id: id, details: details),
        AsyncData() || AsyncError() => const LoadFailed(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

final class _GroupSettings extends ConsumerWidget {
  final ChatRef chat;
  final GroupChatId id;
  final ChatDetails details;

  const _GroupSettings({
    required this.chat,
    required this.id,
    required this.details,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    Future<void> want(FactValue value) => wantFact(
      context,
      ref,
      chat.profile,
      Subject.chat(ChatId.group(id)),
      value,
    );
    final private = details.privacy == Privacy.private;
    final password = details.password ?? '';
    return ListView(
      children: [
        SwitchListTile(
          title: Text(l10n.privateGroup),
          subtitle: Text(
            private ? l10n.privateGroupHint : l10n.publicGroupHint,
          ),
          value: private,
          onChanged: (on) =>
              want(FactValue.privacy(on ? Privacy.private : Privacy.public)),
        ),
        SwitchListTile(
          title: Text(l10n.topicLock),
          subtitle: Text(l10n.topicLockHint),
          value: details.topicLock ?? false,
          onChanged: (on) => want(FactValue.topicLock(on)),
        ),
        ListTile(
          title: Text(l10n.whoCanSpeak),
          subtitle: Text(
            _voiceText(l10n, details.voiceState ?? VoiceState.everyone),
          ),
          onTap: () async {
            final voice = await showDialog<VoiceState>(
              context: context,
              builder: (dialog) => SimpleDialog(
                title: Text(l10n.whoCanSpeak),
                children: [
                  for (final voice in VoiceState.values)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialog, voice),
                      child: Text(_voiceText(l10n, voice)),
                    ),
                ],
              ),
            );
            if (voice != null) {
              await want(FactValue.voiceState(voice));
            }
          },
        ),
        ListTile(
          title: Text(l10n.peerLimit),
          subtitle: Text('${details.peerLimit ?? ''}'),
          onTap: () async {
            final limit = await askText(
              context,
              title: l10n.peerLimit,
              initial: '${details.peerLimit ?? ''}',
              number: true,
              validator: (text) => switch (int.tryParse(text)) {
                final n? when n >= 1 && n <= _maxPeerLimit => null,
                _ => l10n.peerLimitInvalid(_maxPeerLimit),
              },
            );
            if (limit != null) {
              await want(FactValue.peerLimit(int.parse(limit)));
            }
          },
        ),
        ListTile(
          title: Text(l10n.groupPassword),
          subtitle: Text(
            password.isEmpty ? l10n.groupPasswordOff : l10n.groupPasswordOn,
          ),
          onTap: () async {
            final entered = await askText(
              context,
              title: l10n.groupPassword,
              initial: password,
              helper: l10n.groupPasswordEmptyForNone,
              validator: (text) =>
                  utf8.encode(text).length > toxGroupMaxPasswordSize
                  ? l10n.groupPasswordTooLong
                  : null,
            );
            if (entered != null) {
              await want(FactValue.password(entered));
            }
          },
        ),
      ],
    );
  }
}

String _voiceText(AppLocalizations l10n, VoiceState voice) => switch (voice) {
  VoiceState.everyone => l10n.voiceEveryone,
  VoiceState.moderators => l10n.voiceModerators,
  VoiceState.founder => l10n.voiceFounder,
};
