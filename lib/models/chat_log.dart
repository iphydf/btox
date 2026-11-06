import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/messages/message_format.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/persistence.dart' show FileState;
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/sync/store.dart';

/// The key [formats] give a message, which stays the same when it's sent
/// again.
MessageKey? keyOf(EventContent content, MessageFormats formats) =>
    switch (content) {
      Received(from: null, :final message) => formats.keyOf(
        message,
        friend: true,
      ),
      _ => null,
    };

/// Whether [content] is someone else's message or file, which counts as
/// unread until read and notifies.
bool isIncoming(EventContent content) => switch (content) {
  Received() || ReceivedPrivately() || FileStarted(incoming: true) => true,
  _ => false,
};

/// A message a chat's notification lists, with its [sender] where that isn't
/// the chat's friend, as in a group.
typedef NotifiedMessage = ({String? sender, String text, DateTime time});

/// Whether [text] names one of [names], as a word, in any case.
bool mentions(String text, Iterable<String> names) => names.any(
  (name) =>
      name.isNotEmpty &&
      RegExp(
        '(?<![\\p{L}\\p{N}_])${RegExp.escape(name)}(?![\\p{L}\\p{N}_])',
        caseSensitive: false,
        unicode: true,
      ).hasMatch(text),
);

/// Of [messages], those that notify at [now] in a chat [mute] mutes: all
/// where it doesn't hold, else those naming one of [names] where it lets
/// mentions through.
List<NotifiedMessage> notifying(
  List<NotifiedMessage> messages,
  Mute? mute,
  DateTime now,
  Iterable<String> names,
) => switch (mute) {
  final mute? when mute.holdsAt(now) =>
    mute.mentions
        ? [
            for (final message in messages)
              if (mentions(message.text, names)) message,
          ]
        : const [],
  _ => messages,
};

/// What to call someone in a chat: their name, or while they have none, the
/// start of their key, which tells them apart.
String memberName(AppLocalizations l10n, String? name, PublicKey? key) =>
    switch ((name, key)) {
      (final name?, _) when name.isNotEmpty => name,
      (_, final key?) => key.toJson().substring(0, 8),
      _ => l10n.defaultContactName,
    };

/// What [entry] says: for a notice of something that happened, in the
/// reader's language.
String noticeText(AppLocalizations l10n, ChatEntry entry) {
  String named(String name, PublicKey? key) => memberName(l10n, name, key);
  return switch (entry.happened) {
    PeerJoined(:final peer, :final name) => l10n.memberJoined(
      named(name, peer),
    ),
    PeerLeft(:final peer, :final name) => l10n.memberLeft(named(name, peer)),
    PeerRenamed(:final peer, :final old, :final name) => l10n.memberRenamed(
      named(old, peer),
      named(name, peer),
    ),
    TopicSet(name: '', by: null, :final topic) => l10n.topicSetBySomeone(topic),
    TopicSet(:final by, :final name, :final topic) => l10n.topicSet(
      named(name, by),
      topic,
    ),
    TitleSet(name: '', by: null, :final title) => l10n.titleSetBySomeone(title),
    TitleSet(:final by, :final name, :final title) => l10n.titleSet(
      named(name, by),
      title,
    ),
    Moderated(name: '', by: null, :final peer, :final peerName, role: null) =>
      l10n.memberKickedBySomeone(named(peerName, peer)),
    Moderated(
      :final by,
      :final name,
      :final peer,
      :final peerName,
      role: null,
    ) =>
      l10n.memberKicked(named(name, by), named(peerName, peer)),
    Moderated(name: '', by: null, :final peer, :final peerName, :final role?) =>
      l10n.memberRoleBySomeone(named(peerName, peer), role.name),
    Moderated(
      :final by,
      :final name,
      :final peer,
      :final peerName,
      :final role?,
    ) =>
      l10n.memberRole(named(name, by), named(peerName, peer), role.name),
    _ => entry.content.plainText,
  };
}

/// Who of [run] joined and who left, as one line.
String comingsText(AppLocalizations l10n, List<ChatEntry> run) {
  // Each once, by key.
  final came = <PublicKey, String>{};
  final went = <PublicKey, String>{};
  for (final entry in run) {
    switch (entry.happened) {
      case PeerJoined(:final peer, :final name):
        came.putIfAbsent(peer, () => name);
      case PeerLeft(:final peer, :final name):
        went.putIfAbsent(peer, () => name);
      default:
        break;
    }
  }
  String names(Map<PublicKey, String> all) {
    final named = [
      for (final MapEntry(key: key, value: name) in all.entries)
        memberName(l10n, name, key),
    ];
    return switch (named) {
      [final a] => a,
      [final a, final b] => l10n.namesTwo(a, b),
      [final a, final b, final c] => l10n.namesThree(a, b, c),
      [final a, final b, ...final more] => l10n.namesMore(a, b, more.length),
      [] => '',
    };
  }

  String people(Map<PublicKey, String> who) =>
      who.length == 1 ? 'one' : 'other';
  return [
    if (came.isNotEmpty) l10n.membersJoined(names(came), people(came)),
    if (went.isNotEmpty) l10n.membersLeft(names(went), people(went)),
  ].join(' \u00b7 ');
}

/// The text for an invite to a chat from the friend named [from].
String inviteText(AppLocalizations l10n, AccountInvite invite, String? from) {
  final friend = from ?? l10n.defaultContactName;
  return switch (invite.kind) {
    ChatKind.group => l10n.groupInvite(friend, invite.name),
    ChatKind.conference => l10n.conferenceInvite(friend),
  };
}

/// What a notification of incoming [content] says, without its sender.
String notificationText(EventContent content, MessageFormats formats) =>
    switch (content) {
      Received(:final from, :final message) =>
        formats.read(message, friend: from == null).text,
      ReceivedPrivately(:final message) =>
        formats.read(message, friend: false).text,
      FileStarted(:final name) => '📎 $name',
      _ => '',
    };

/// Spots messages that repeat an earlier one: the first message with a key
/// shows, and later ones with it don't, aren't unread and don't notify.
final class Repeats {
  final _seen = <MessageKey>{};

  bool isRepeat(MessageKey? key) => key != null && !_seen.add(key);
}

/// Spots messages that repeat an earlier one of their chat in a store,
/// whatever order they came in: it keeps the first message with each key
/// of each chat, reading the chat's events as they're added.
final class EarlierRepeats {
  final EventStore _store;
  MessageFormats? _formats;
  final _first = <GraphId, Map<MessageKey, (int, EventId)>>{};
  // How many of each chat's events have been read.
  final _read = <GraphId, int>{};

  EarlierRepeats(this._store);

  /// Whether [event] repeats an earlier message of its chat as [formats]
  /// read them.
  bool repeats(EventId id, SyncEvent event, MessageFormats formats) {
    if (formats != _formats) {
      _formats = formats;
      _first.clear();
      _read.clear();
    }
    final key = keyOf(event.content, formats);
    if (key == null) {
      return false;
    }
    final graph = event.graph;
    final first = _first.putIfAbsent(graph, () => {});
    for (final (earlierId, earlier) in _store.eventsFrom(
      graph,
      _read[graph] ?? 0,
    )) {
      if (keyOf(earlier.content, formats) case final earlierKey?) {
        if (first[earlierKey] case final known?
            when compareRanks(known, (earlier.rank, earlierId)) < 0) {
          continue;
        }
        first[earlierKey] = (earlier.rank, earlierId);
      }
    }
    _read[graph] = _store.countIn(graph);
    return compareRanks(first[key]!, (event.rank, id)) < 0;
  }

  /// Forgets [graph]'s messages, as its store did.
  void forget(GraphId graph) {
    _first.remove(graph);
    _read.remove(graph);
  }
}

typedef _Placed = ({EventId id, SyncEvent event, int time});

/// A chat's entries, from its events in display order: by rank, then
/// effective time, then ID. An event's effective time is never before its
/// parents', so a fast clock can't move it back in history. Events that come
/// after those already shown are added, and anything else shows them again.
final class ChatLog {
  final MessageFormats _formats;
  final _effective = <EventId, int>{};
  final _index = <EventId, int>{};
  var _entries = <ChatEntry>[];
  var _shown = const <ChatEntry>[];
  var _repeats = Repeats();
  _Placed? _last;

  ChatLog(this._formats);

  List<ChatEntry> update(List<(EventId, SyncEvent)> events) {
    final fresh = [
      for (final e in events)
        if (!_effective.containsKey(e.$1)) e,
    ];
    var placed = _place(fresh);
    final last = _last;
    if (events.length != _effective.length + fresh.length ||
        (last != null &&
            placed.isNotEmpty &&
            _compare(placed.first, last) < 0)) {
      _effective.clear();
      _index.clear();
      _entries = [];
      _repeats = Repeats();
      _last = null;
      placed = _place(events);
    } else if (placed.isEmpty) {
      return _shown;
    }
    for (final p in placed) {
      _effective[p.id] = p.time;
      _add(p.id, p.event);
    }
    _last = placed.lastOrNull;
    return _shown = List.unmodifiable(_entries);
  }

  List<_Placed> _place(List<(EventId, SyncEvent)> events) {
    final byRank = events.toList()
      ..sort((a, b) {
        final rank = a.$2.rank.compareTo(b.$2.rank);
        return rank != 0 ? rank : a.$1.compareTo(b.$1);
      });
    final times = <EventId, int>{};
    final placed = <_Placed>[];
    for (final (id, event) in byRank) {
      var time = event.time;
      for (final parent in event.parents) {
        if ((times[parent] ?? _effective[parent]) case final t? when t > time) {
          time = t;
        }
      }
      times[id] = time;
      placed.add((id: id, event: event, time: time));
    }
    return placed..sort(_compare);
  }

  static int _compare(_Placed a, _Placed b) {
    final rank = a.event.rank.compareTo(b.event.rank);
    if (rank != 0) {
      return rank;
    }
    final time = a.time.compareTo(b.time);
    return time != 0 ? time : a.id.compareTo(b.id);
  }

  void _add(EventId id, SyncEvent event) {
    final entry = entryOf(id, event, _formats);
    if (entry != null && !_repeats.isRepeat(keyOf(event.content, _formats))) {
      _index[id] = _entries.length;
      _entries.add(entry);
    }
    void update(EventId target, ChatEntry Function(ChatEntry) change) {
      if (_index[target] case final i?) {
        _entries[i] = change(_entries[i]);
      }
    }

    switch (event.content) {
      case Sent(:final intent):
        update(intent, (e) => e.copyWith(state: ChatContentState.sent));
      case Delivered(:final intent):
        update(
          intent,
          (e) => e.copyWith(
            state: ChatContentState.delivered,
            delivered: _timeOf(event),
          ),
        );
      case FileEnded(:final file, :final ok, :final blob):
        update(
          file,
          (e) => e.copyWith(
            delivered: ok && e.mine ? _timeOf(event) : null,
            file: FileProgress(
              state: ok ? FileState.done : FileState.cancelled,
              blob: blob,
            ),
          ),
        );
      case final CallEnded end:
        update(end.call, (e) => endedAs(e, end));
      case FileAnswered(:final file, :final accepted):
        update(
          file,
          (e) => e.file?.state == FileState.offered
              ? e.copyWith(
                  file: FileProgress(
                    state: accepted ? FileState.active : FileState.cancelled,
                  ),
                )
              : e,
        );
      default:
        break;
    }
  }
}

ChatEntry endedAs(ChatEntry entry, CallEnded end) => switch (entry.content) {
  final CallContent content => entry.copyWith(
    content: content.copyWith(
      ended: true,
      duration: end.duration,
      declined: end.declined,
    ),
  ),
  _ => entry,
};

bool _isAction(MessageType kind) => kind == MessageType.action;

DateTime _timeOf(SyncEvent event) =>
    DateTime.fromMillisecondsSinceEpoch(event.time, isUtc: true);

/// The entry [event] shows as in its chat, if it shows as one, with friends'
/// messages read in [formats].
ChatEntry? entryOf(EventId id, SyncEvent event, MessageFormats formats) {
  final timestamp = _timeOf(event);
  return switch (event.content) {
    // Only group senders have keys. In friend chats it's the friend.
    Received(:final from, :final sender, :final message, :final kind) =>
      ChatEntry(
        event: id,
        sender: from == null ? null : sender,
        from: from,
        mine: false,
        action: _isAction(kind),
        content: contentOfMessage(
          formats.read(message, friend: from == null).text,
        ),
        timestamp: timestamp,
      ),
    Send(:final message, :final kind) => ChatEntry(
      event: id,
      mine: true,
      action: _isAction(kind),
      content: contentOfMessage(plainText(message)),
      timestamp: timestamp,
      state: ChatContentState.pending,
    ),
    ReceivedPrivately(
      :final from,
      :final sender,
      :final message,
      :final kind,
    ) =>
      ChatEntry(
        event: id,
        sender: sender,
        from: from,
        privately: from,
        mine: false,
        action: _isAction(kind),
        content: contentOfMessage(formats.read(message, friend: false).text),
        timestamp: timestamp,
      ),
    SendPrivately(:final to, :final message, :final kind) => ChatEntry(
      event: id,
      privately: to,
      mine: true,
      action: _isAction(kind),
      content: contentOfMessage(plainText(message)),
      timestamp: timestamp,
      state: ChatContentState.pending,
    ),
    Notice(:final text) => ChatEntry(
      event: id,
      mine: false,
      notice: true,
      content: TextContent(text: text),
      timestamp: timestamp,
    ),
    PeerJoined() ||
    PeerLeft() ||
    PeerRenamed() ||
    TopicSet() ||
    TitleSet() ||
    Moderated() => ChatEntry(
      event: id,
      mine: false,
      notice: true,
      content: const TextContent(text: ''),
      happened: event.content,
      timestamp: timestamp,
    ),
    Call(:final incoming, :final video) => ChatEntry(
      event: id,
      mine: !incoming,
      notice: true,
      content: CallContent(incoming: incoming, video: video),
      timestamp: timestamp,
    ),
    FileStarted(:final name, :final size, :final incoming) => ChatEntry(
      event: id,
      mine: !incoming,
      content: FileContent(name: name, size: size),
      timestamp: timestamp,
      file: FileProgress(state: incoming ? FileState.offered : null),
    ),
    _ => null,
  };
}
