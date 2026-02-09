import 'dart:convert';

import 'package:btox/models/bootstrap_nodes.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bootstrap_nodes.g.dart';

@Riverpod(keepAlive: true)
http.Client httpClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
}

@Riverpod(keepAlive: true)
Future<BootstrapNodeList> bootstrapNodes(Ref ref) async {
  final client = ref.watch(httpClientProvider);
  final response = await client.get(Uri.parse('https://nodes.tox.chat/json'));
  if (response.statusCode == 200) {
    return BootstrapNodeList.fromJson(jsonDecode(response.body));
  } else {
    throw Exception('Failed to load bootstrap nodes');
  }
}
