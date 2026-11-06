import 'dart:typed_data';

import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/providers/map_tile.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/widgets/chat_item.dart';
import 'package:btox/widgets/chat_location_bubble.dart';
import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:btox/widgets/sender_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_tile_provider.dart';
import '../mocks/test_app.dart';

ChatEntry _entry(
  int minute, {
  bool mine = false,
  String? sender,
  PublicKey? from,
  bool notice = false,
}) => ChatEntry(
  event: EventId(Uint8List(32)..[0] = minute),
  sender: sender,
  from: from,
  mine: mine,
  content: const TextContent(text: 'hi'),
  timestamp: DateTime(2026, 10, 20, 12, minute),
  notice: notice,
);

ChatEntry _happened(int minute, EventContent happened, {int day = 20}) =>
    ChatEntry(
      event: EventId(Uint8List(32)..[0] = minute),
      mine: false,
      notice: true,
      content: const TextContent(text: ''),
      happened: happened,
      timestamp: DateTime(2026, 10, day, 12, minute),
    );

PublicKey _key(int n) => PublicKey(Uint8List(32)..fillRange(0, 32, n));

void main() {
  test('three or more joins and leaves on a day show as one line', () {
    final entries = [
      _happened(0, PeerJoined(peer: _key(1), name: 'Ann')),
      _happened(1, PeerJoined(peer: _key(2), name: 'Bob')),
      _entry(2),
      _happened(3, PeerJoined(peer: _key(1), name: 'Ann')),
      _happened(4, PeerLeft(peer: _key(2), name: 'Bob')),
      _happened(5, PeerJoined(peer: _key(3), name: 'Cid')),
      _happened(6, PeerJoined(peer: _key(1), name: 'Ann')),
      _happened(7, PeerLeft(peer: _key(3), name: 'Cid'), day: 21),
    ];
    expect(comingRuns(entries, entries.length), [1, 1, 1, 4, 0, 0, 0, 1]);
    // Those waiting below the reader don't join a run above them.
    expect(comingRuns(entries, 5), [1, 1, 1, 1, 1, 1, 1, 1]);
    expect(comingRuns(entries, 6), [1, 1, 1, 3, 0, 0, 1, 1]);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      comingsText(l10n, entries.sublist(3, 7)),
      'Ann and Cid joined \u00b7 Bob left',
    );
    expect(
      comingsText(
        lookupAppLocalizations(const Locale('de')),
        entries.sublist(3, 7),
      ),
      'Ann und Cid sind beigetreten \u00b7 Bob hat den Chat verlassen',
    );
    expect(
      comingsText(l10n, [
        for (var i = 1; i <= 5; i++)
          _happened(i, PeerJoined(peer: _key(i), name: 'P$i')),
      ]),
      'P1, P2 and 3 others joined',
    );
  });

  test('messages an author sends one after another make a run', () {
    expect(inRun(_entry(0), _entry(1)), isTrue);
    expect(inRun(_entry(0, sender: 'Bob'), _entry(1, sender: 'Bob')), isTrue);
    // Renamed, but the same key.
    final bob = PublicKey(Uint8List(32)..[0] = 2);
    expect(
      inRun(
        _entry(0, sender: 'Bob', from: bob),
        _entry(1, sender: 'Robert', from: bob),
      ),
      isTrue,
    );
    expect(
      inRun(
        _entry(0, sender: 'Bob', from: bob),
        _entry(1, sender: 'Bob', from: PublicKey(Uint8List(32))),
      ),
      isFalse,
    );

    expect(inRun(_entry(0), _entry(1, mine: true)), isFalse);
    expect(inRun(_entry(0, sender: 'Bob'), _entry(1, sender: 'Eve')), isFalse);
    expect(inRun(_entry(0), _entry(1, notice: true)), isFalse);
    // Too long after.
    expect(inRun(_entry(0), _entry(10)), isFalse);
  });

  testWidgets("a group message's sender shows in its run's first bubble", (
    tester,
  ) async {
    final chat = ChatRef(const Id(1), GraphId(Uint8List(32)));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Column(
            children: [
              ChatItem(
                chat: chat,
                entry: _entry(0, sender: 'Bob'),
                joinsBelow: true,
              ),
              ChatItem(
                chat: chat,
                entry: _entry(1, sender: 'Bob'),
                joinsAbove: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(ChatTextBubble).first,
        matching: find.text('Bob'),
      ),
      findsOneWidget,
    );
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('a sender keeps their colour when they rename themselves', (
    tester,
  ) async {
    final bob = PublicKey(Uint8List(32)..[0] = 2);
    await tester.pumpWidget(
      testApp(
        Column(
          children: [
            SenderName('Bob', author: bob),
            SenderName('Robert', author: bob),
          ],
        ),
      ),
    );
    Color? colour(String name) =>
        tester.widget<Text>(find.text(name)).style?.color;
    expect(colour('Robert'), colour('Bob'));
  });

  testWidgets('a friend typing shows as dots, read out by name', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(const ChatTyping(name: 'Bob')));
    await tester.pump();
    expect(find.bySemanticsLabel('Bob is typing'), findsOneWidget);
  });

  testWidgets('a location shows as a map', (tester) async {
    final fakeTileProvider = FakeTileProvider();
    await tester.pumpWidget(
      testApp(
        ChatItem(
          chat: ChatRef(const Id(1), GraphId(Uint8List(32))),
          entry: ChatEntry(
            event: EventId(Uint8List(32)),
            mine: true,
            // Greenwich Observatory
            content: const LocationContent(
              latitude: 51.476853468836715,
              longitude: -0.0005210189094241177,
            ),
            timestamp: DateTime(2026, 10, 20, 12),
          ),
        ),
        overrides: [mapTileProvider.overrideWith((ref, _) => fakeTileProvider)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChatLocationBubble), findsOneWidget);
    expect(fakeTileProvider.requests, hasLength(16));
    expect(fakeTileProvider.requests.first, TileCoordinates(4094, 2723, 13));
  });

  testWidgets("a group member's location shows under their name", (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        ChatItem(
          chat: ChatRef(const Id(1), GraphId(Uint8List(32))),
          entry: ChatEntry(
            event: EventId(Uint8List(32)),
            sender: 'Bob',
            from: PublicKey(Uint8List(32)..[0] = 2),
            mine: false,
            content: const LocationContent(latitude: 51.48, longitude: 0),
            timestamp: DateTime(2026, 10, 20, 12),
          ),
        ),
        overrides: [
          mapTileProvider.overrideWith((ref, _) => FakeTileProvider()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SenderName), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
  });
}
