import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('bootstrapNodes fetches and parses nodes correctly', () async {
    const jsonResponse = '''
    {
      "nodes": [
        {
          "ipv4": "127.0.0.1",
          "port": 33445,
          "public_key": "0000000000000000000000000000000000000000000000000000000000000000",
          "tcp_ports": [33446],
          "ipv6": "",
          "maintainer": "test",
          "location": "test",
          "status_udp": true,
          "status_tcp": true,
          "version": "1.0",
          "motd": "test",
          "last_ping": 123456789
        }
      ],
      "last_refresh": 123,
      "last_scan": 456
    }
    ''';

    final mockClient = MockClient((request) async {
      return http.Response(jsonResponse, 200);
    });

    final container = ProviderContainer(
      overrides: [httpClientProvider.overrideWithValue(mockClient)],
    );

    final nodes = await container.read(bootstrapNodesProvider.future);

    expect(nodes.nodes.length, 1);
    expect(nodes.nodes[0].ipv4, '127.0.0.1');
  });
}
