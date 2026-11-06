import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/proxy_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Accepts one connection and returns its first request, after answering the
/// SOCKS5 greeting if [socks5].
Future<(int, Future<List<int>>)> _fakeProxy({required bool socks5}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final request = server.first.then((client) async {
    final received = <int>[];
    final done = Completer<List<int>>();
    client.listen((data) {
      received.addAll(data);
      if (socks5 && received.length == 3) {
        client.add([5, 0]);
        received.clear();
      } else if (!done.isCompleted &&
          (socks5
              ? received.length > 4 && received.length >= 7 + received[4]
              : utf8.decode(received).contains('\r\n'))) {
        done.complete(received);
      }
    });
    final bytes = await done.future;
    client.destroy();
    await server.close();
    return bytes;
  });
  return (server.port, request);
}

void main() {
  test('a SOCKS5 proxy resolves the host name', () async {
    final (port, request) = await _fakeProxy(socks5: true);
    final client = proxyClient(
      NetworkSettings(proxyType: ProxyType.socks5, proxyPort: port),
    );
    addTearDown(client.close);
    unawaited(
      client
          .get(Uri.parse('https://nodes.tox.chat/json'))
          .catchError((_) => http.Response('', 500)),
    );

    final name = utf8.encode('nodes.tox.chat');
    expect(await request, [5, 1, 0, 3, name.length, ...name, 1, 187]);
  });

  test('an HTTP proxy tunnels to the host name', () async {
    final (port, request) = await _fakeProxy(socks5: false);
    final client = proxyClient(
      NetworkSettings(proxyType: ProxyType.http, proxyPort: port),
    );
    addTearDown(client.close);
    unawaited(
      client
          .get(Uri.parse('https://nodes.tox.chat/json'))
          .catchError((_) => http.Response('', 500)),
    );

    expect(
      utf8.decode(await request),
      startsWith('CONNECT nodes.tox.chat:443 '),
    );
  });
}
