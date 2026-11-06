import 'package:btox/api/toxcore/tox_constants.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/crypto.dart';
import 'package:flutter/material.dart';

final _hex = RegExp(r'^[0-9A-Fa-f]*$');
final _scheme = RegExp('^tox:', caseSensitive: false);

/// Links and QR codes have a `tox:` prefix.
String toxIdOf(String text) => text.trim().replaceFirst(_scheme, '');

final class ToxIdField extends StatelessWidget {
  final TextEditingController controller;
  // Our own keys, which can't be added.
  final Set<PublicKey> own;

  const ToxIdField({super.key, required this.controller, this.own = const {}});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextFormField(
        key: const Key('toxId'),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (text) {
          final value = toxIdOf(text ?? '');
          if (value.length != toxAddressSize * 2 || !_hex.hasMatch(value)) {
            final msg = AppLocalizations.of(
              context,
            )!.toxIdLengthError(toxAddressSize * 2);
            return '$msg (${value.length}/${toxAddressSize * 2})';
          }
          final address = ToxAddress.fromString(value);
          if (!address.hasValidChecksum) {
            return AppLocalizations.of(context)!.toxIdChecksumError;
          }
          if (own.contains(address.publicKey)) {
            return AppLocalizations.of(context)!.ownToxIdError;
          }
          return null;
        },
        decoration: InputDecoration(
          border: UnderlineInputBorder(),
          labelText: AppLocalizations.of(context)!.toxId,
        ),
        controller: controller,
        textInputAction: TextInputAction.next,
        autofocus: true,
      ),
    );
  }
}
