import 'dart:io';

import 'package:btox/attachments/pictures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('pictures'));
  tearDown(() => dir.delete(recursive: true));

  Future<String> write(String name, List<int> bytes) async {
    final file = path.join(dir.path, name);
    await File(file).writeAsBytes(bytes);
    return file;
  }

  test('a photo goes shrunk, without where it was taken', () async {
    final photo = img.Image(width: 3000, height: 2000)
      ..exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(52, 1);
    final file = await write('photo.jpg', img.encodeJpg(photo));
    expect(
      img.decodeJpg(File(file).readAsBytesSync())!.exif.gpsIfd.isEmpty,
      isFalse,
    );

    final (bytes, extension) = (await sendablePicture(
      file,
      width: 3000,
      height: 2000,
    ))!;
    final sent = img.decodeJpg(bytes)!;
    expect((extension, sent.width, sent.height), ('.jpg', 2048, 1365));
    expect(sent.exif.isEmpty, isTrue);
  });

  test('GIFs and PNGs that fit go as they are', () async {
    final small = img.Image(width: 10, height: 10);
    expect(
      await sendablePicture(
        await write('a.gif', img.encodeGif(small)),
        width: 10,
        height: 10,
      ),
      isNull,
    );
    expect(
      await sendablePicture(
        await write('a.png', img.encodePng(small)),
        width: 10,
        height: 10,
      ),
      isNull,
    );
  });
}
