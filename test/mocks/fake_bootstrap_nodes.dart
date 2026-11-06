import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/crypto.dart';
import 'package:riverpod/riverpod.dart';

BootstrapNodeList fakeBootstrapNodesProvider(Ref ref) => BootstrapNodeList(
  nodes: [
    BootstrapNode(
      ipv4: '127.0.0.1',
      port: 33445,
      publicKey: PublicKey.fromJson(
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      ),
      tcpPorts: [33446],
    ),
  ],
);
