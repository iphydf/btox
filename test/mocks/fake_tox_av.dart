import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/api/toxcore/tox_av.dart';

final class FakeToxAv extends ToxAv {
  final events = <AvEvent>[];

  /// (friend number, audio bit rate), for calls and answers.
  final calls = <(int, int)>[];
  final answers = <(int, int)>[];
  final controls = <(int, CallControl)>[];
  final frames = <(int, Int16List)>[];
  final videoBitRates = <(int, int)>[];
  final videoFrames = <(int, int, int)>[];
  ApiException? error;

  void _check() {
    if (error case final error?) {
      throw error;
    }
  }

  @override
  List<AvEvent> iterate() {
    final iterated = [...events];
    events.clear();
    return iterated;
  }

  @override
  int iterationInterval() => 20;

  @override
  void call(FriendNumber friendNumber, int audioBitRate, int videoBitRate) {
    _check();
    calls.add((friendNumber.value, audioBitRate));
  }

  @override
  void answer(FriendNumber friendNumber, int audioBitRate, int videoBitRate) =>
      answers.add((friendNumber.value, audioBitRate));

  @override
  void callControl(FriendNumber friendNumber, CallControl control) {
    _check();
    controls.add((friendNumber.value, control));
  }

  @override
  void audioSendFrame(
    FriendNumber friendNumber,
    Int16List pcm,
    int sampleCount,
    int channels,
    int samplingRate,
  ) {
    _check();
    frames.add((friendNumber.value, pcm));
  }

  @override
  void videoSendFrame(
    FriendNumber friendNumber,
    int width,
    int height,
    Uint8List y,
    Uint8List u,
    Uint8List v,
  ) {
    _check();
    videoFrames.add((friendNumber.value, width, height));
  }

  @override
  void videoSetBitRate(FriendNumber friendNumber, int bitRate) {
    _check();
    videoBitRates.add((friendNumber.value, bitRate));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
