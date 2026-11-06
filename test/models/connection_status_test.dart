import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/models/connection_status.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const online = ConnectionStatus(connection: Connection.udp);
  const connecting = ConnectionStatus(connection: Connection.none);

  test('the summary counts accounts online', () {
    expect(connectionSummaryText([online]), 'Online');
    expect(connectionSummaryText([online, online]), '2 accounts online');
    expect(
      connectionSummaryText([online, connecting]),
      '1 of 2 accounts online',
    );
  });

  test('the lines name each account', () {
    final alice = Id<Profiles>(1);
    final bob = Id<Profiles>(2);
    final names = {alice: 'Alice', bob: 'Bob'};
    expect(connectionStatusLines({alice: online}, names), isEmpty);
    expect(connectionStatusLines({alice: online, bob: connecting}, names), [
      'Alice: Online',
      'Bob: Connecting…',
    ]);
  });
}
