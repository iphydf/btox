import 'package:btox/models/built_in_nodes.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/tox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the built-in list has TCP relays to start from', () {
    expect(
      bootstrapNodesToUse(builtInBootstrapNodes.nodes, const NetworkSettings()),
      isNotEmpty,
    );
  });
}
