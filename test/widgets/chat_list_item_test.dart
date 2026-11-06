import 'dart:typed_data';

import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/widgets/chat_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/test_app.dart';

void main() {
  testWidgets('a friend typing shows dots in place of the last message', (
    tester,
  ) async {
    final bob = PublicKey(Uint8List(32)..[0] = 2);
    Future<void> show({required bool typing}) => tester.pumpWidget(
      testApp(
        Material(
          child: ChatListItem(
            chat: ChatSummary(
              ref: ChatRef(
                Id(1),
                GraphId.friend(PublicKey(Uint8List(32)), bob),
              ),
              name: 'Bob',
              key: bob,
              typing: typing,
              last: ChatEntry(
                event: EventId(Uint8List(32)),
                mine: false,
                content: const TextContent(text: 'hi'),
                timestamp: DateTime(2026),
              ),
            ),
            onTap: (_) {},
          ),
        ),
      ),
    );

    await show(typing: false);
    expect(find.text('hi'), findsOneWidget);

    await show(typing: true);
    await tester.pump();
    expect(find.text('hi'), findsNothing);
    // The row reads out as one, with the name first.
    expect(find.bySemanticsLabel(RegExp('Bob is typing')), findsOneWidget);
  });
}
