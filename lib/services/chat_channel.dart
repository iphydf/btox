import 'dart:ui';

import 'package:btox/logger.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/services/isolate_channel.dart';
import 'package:clock/clock.dart';

const _logger = Logger(['ChatChannel']);

const _portName = 'btox-chats';

// More often than the service's typing timeout.
const _typingEvery = Duration(seconds: 1);

typedef TypingIn = void Function(GraphId chat, {required bool typing});

/// Receives chat notices from the UI, which may be in another isolate.
final class ChatHost {
  static final instance = ChatHost._();

  final _typing = <Id<Profiles>, TypingIn>{};
  Publisher? _publisher;

  ChatHost._();

  void add(Id<Profiles> profile, TypingIn typing) {
    _typing[profile] = typing;
    _publisher ??= Publisher(
      _portName,
      current: (_) => null,
      onMessage: _receive,
    );
  }

  void remove(Id<Profiles> profile) => _typing.remove(profile);

  void _receive(Object? message) {
    switch (message) {
      case ['typing', int profile, String chat, bool typing]:
        _typing[Id<Profiles>(profile)]?.call(
          GraphId.fromJson(chat),
          typing: typing,
        );
      default:
        _logger.w('Unknown chat command: $message');
    }
  }
}

/// Sends at most one typing notice per [_typingEvery].
final class TypingNotice {
  final ChatRef chat;
  DateTime? _told;

  TypingNotice(this.chat);

  void typing({required bool typing}) {
    final now = clock.now();
    final told = _told;
    final tell = typing
        ? told == null || now.difference(told) >= _typingEvery
        : told != null;
    if (!tell) {
      return;
    }
    _told = typing ? now : null;
    IsolateNameServer.lookupPortByName(
      _portName,
    )?.send(['typing', chat.profile.value, chat.graph.toJson(), typing]);
  }
}
