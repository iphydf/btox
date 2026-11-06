import 'package:btox/messages/chat_command.dart';
import 'package:flutter_test/flutter_test.dart';

String described(ChatCommand command) => switch (command) {
  Say(:final text) => 'say $text',
  Act(:final text) => 'act $text',
};

void main() {
  test('reads the commands it knows, and says the rest as it is', () {
    expect(
      [
        for (final line in ['/me waves', '/me\nwaves', '/shrug ok', 'hi /me'])
          described(ChatCommand.of(line)),
      ],
      ['act waves', 'act waves', 'say /shrug ok', 'say hi /me'],
    );
  });
}
