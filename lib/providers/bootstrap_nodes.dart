import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/built_in_nodes.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bootstrap_nodes.g.dart';

/// The nodes Tox starts from: the list bTox was released with.
@riverpod
BootstrapNodeList bootstrapNodes(Ref ref) => builtInBootstrapNodes;
