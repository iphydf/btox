import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_api.dart';
import 'package:btox/api/toxcore/tox_av.dart';
import 'package:btox/api/toxcore/tox_enums.dart';
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/api/toxcore/tox_ids.dart';

export 'package:btox/api/toxcore/tox_api.dart';
export 'package:btox/api/toxcore/tox_enums.dart';
export 'package:btox/api/toxcore/tox_errors.dart';
export 'package:btox/api/toxcore/tox_ids.dart';

/// A running Tox: toxcore's functions, plus its events and its end.
abstract class Tox implements ToxApi {
  const Tox();

  bool get isAlive;

  List<Event> iterate();

  /// Started on first use. It ends with this Tox.
  ToxAv startAv();

  /// Returns a group's state, to save it without the rest of Tox's savedata.
  Uint8List groupGetSavedata(GroupNumber groupNumber);

  /// Loads a group saved by [groupGetSavedata] and returns its group number.
  GroupNumber groupLoadSavedata(Uint8List savedata);

  void kill();
}

/// Thrown by [Tox.iterate].
enum IterateOptionsNewError {
  malloc(1);

  final int value;

  const IterateOptionsNewError(this.value);

  static IterateOptionsNewError fromValue(int value) => switch (value) {
    1 => malloc,
    _ => throw ArgumentError.value(value, 'IterateOptionsNewError'),
  };
}

/// Thrown by [Tox.groupLoadSavedata].
enum GroupLoadError {
  malformed(1);

  final int value;

  const GroupLoadError(this.value);

  static GroupLoadError fromValue(int value) => switch (value) {
    1 => malformed,
    _ => throw ArgumentError.value(value, 'GroupLoadError'),
  };
}

abstract interface class ToxFiles {
  void chunk(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    int position,
    Uint8List data,
  );
  void requested(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    int position,
    int length,
  );
  void controlled(
    FriendNumber friendNumber,
    FileNumber fileNumber,
    FileControl control,
  );
}
