/// Lines with an unknown command are sent as they are.
sealed class ChatCommand {
  const ChatCommand();

  factory ChatCommand.of(String line) {
    if (_command.firstMatch(line) case final match?) {
      if (_commands[match[1]] case final command?) {
        return command(match[2]!);
      }
    }
    return Say(line);
  }
}

/// A plain message.
final class Say extends ChatCommand {
  final String text;

  const Say(this.text);
}

/// An action, sent with `/me`.
final class Act extends ChatCommand {
  final String text;

  const Act(this.text);
}

// E.g. `/me waves`.
final _command = RegExp(r'^/(\w+)\s+(.*)$', dotAll: true);

const _commands = <String, ChatCommand Function(String)>{'me': Act.new};
