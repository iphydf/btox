import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/proxy_client.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'http_client.g.dart';

@riverpod
http.Client httpClient(Ref ref, NetworkSettings network) {
  final client = proxyClient(network);
  ref.onDispose(client.close);
  return client;
}
