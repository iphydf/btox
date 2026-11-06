import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/widgets/confirm_dialog.dart';
import 'package:btox/widgets/database_write.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['RemoveChat']);

/// Asks whether to leave [chat], a group or conference, then leaves it.
Future<void> leaveChat(
  BuildContext context,
  WidgetRef ref,
  ChatSummary chat,
) async {
  final l10n = AppLocalizations.of(context)!;
  final name = chat.name ?? l10n.defaultContactName;
  final leave = await confirm(
    context,
    title: l10n.leaveChat,
    message: l10n.leaveChatMessage(name),
    action: l10n.leave,
  );
  if (!leave || !context.mounted) {
    return;
  }
  _logger.i('Leaving ${chat.ref.graph}');
  final messenger = ScaffoldMessenger.of(context);
  // The home device leaves, and tells the others.
  final wish = Wish(
    subject: Subject.chat(chat.chatId!),
    value: const FactValue.joined(false),
  );
  if (await ref.write(context, (db) => db.addIntent(chat.ref.profile, wish))) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.chatLeft(name))));
  }
}

/// Asks whether to delete [friend], and their chat too, then does. Whether
/// it did.
Future<bool> deleteContact(
  BuildContext context,
  WidgetRef ref,
  ChatSummary chat,
  PublicKey friend,
) async {
  final l10n = AppLocalizations.of(context)!;
  final name = chat.name ?? l10n.defaultContactName;
  final deleteChat = await confirmWithOption(
    context,
    title: l10n.deleteContact,
    message: l10n.deleteContactMessage(name),
    action: l10n.delete,
    option: l10n.deleteChatToo,
  );
  if (deleteChat == null || !context.mounted) {
    return false;
  }
  _logger.i('Deleting contact $name');
  final messenger = ScaffoldMessenger.of(context);
  final deleted = await ref.write(
    context,
    (db) => db.addIntent(
      chat.ref.profile,
      UnwantFriend(pk: friend),
      deleteChat: deleteChat,
    ),
  );
  if (deleted) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.contactDeleted(name))));
  }
  return deleted;
}
