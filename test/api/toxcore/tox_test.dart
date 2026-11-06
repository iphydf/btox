import 'package:btox/api/toxcore/tox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiException', () {
    test('toString() with functionName', () {
      const exn = ApiException(NewError.malloc, 'tox_new');
      expect(exn.toString(), 'ApiException: NewError.malloc in tox_new');
    });

    test('toString() without functionName', () {
      const exn = ApiException(NewError.malloc);
      expect(exn.toString(), 'ApiException: NewError.malloc');
    });
  });
}
