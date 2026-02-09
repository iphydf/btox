import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiException', () {
    test('toString() with functionName and args', () {
      const exn = ApiException(Tox_Err_New.TOX_ERR_NEW_MALLOC, 'tox_new', [
        'arg1',
        123,
      ]);
      expect(
        exn.toString(),
        'ApiException: Tox_Err_New.TOX_ERR_NEW_MALLOC in tox_new with args [arg1, 123]',
      );
    });

    test('toString() without functionName', () {
      const exn = ApiException(Tox_Err_New.TOX_ERR_NEW_MALLOC);
      expect(exn.toString(), 'ApiException: Tox_Err_New.TOX_ERR_NEW_MALLOC');
    });
  });

  test('ToxConstants constructor', () {
    const constants = ToxConstants(
      addressSize: 38,
      conferenceIdSize: 32,
      fileIdLength: 32,
      groupChatIdSize: 32,
      groupMaxCustomLosslessPacketLength: 100,
      groupMaxCustomLossyPacketLength: 100,
      groupMaxGroupNameLength: 100,
      groupMaxMessageLength: 100,
      groupMaxPartLength: 100,
      groupMaxPasswordSize: 100,
      groupMaxTopicLength: 100,
      groupPeerPublicKeySize: 32,
      hashLength: 32,
      maxCustomPacketSize: 100,
      maxFilenameLength: 100,
      maxFriendRequestLength: 100,
      maxHostnameLength: 100,
      maxMessageLength: 100,
      maxNameLength: 100,
      maxStatusMessageLength: 100,
      nospamSize: 4,
      publicKeySize: 32,
      secretKeySize: 32,
    );
    expect(constants.addressSize, 38);
  });
}
