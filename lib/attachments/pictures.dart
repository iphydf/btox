import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:btox/platform/any_platform.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

const maxPictureSide = 2048;

const _jpegQuality = 85;

/// Smaller pictures keep their size.
(int, int) fittedSize(int width, int height) {
  final scale = min(1.0, maxPictureSide / max(width, height));
  return (max(1, (width * scale).round()), max(1, (height * scale).round()));
}

/// Shrinks the picture, turns it upright and strips its metadata (e.g. where
/// it was taken). Returns null for GIFs and small PNGs, which are sent as they
/// are to keep their animation and transparency.
Future<(Uint8List, String)?> sendablePicture(
  String file, {
  required int width,
  required int height,
}) async {
  final png = switch (path.extension(file).toLowerCase()) {
    '.gif' => null,
    '.png' => true,
    _ => false,
  };
  if (png == null || png && max(width, height) <= maxPictureSide) {
    return null;
  }
  final bytes = AnyPlatform.instance.isLinux || AnyPlatform.instance.isWindows
      ? await Isolate.run(() => _encoded(file, png: png))
      : await _compressed(file, width, height, png: png);
  return bytes == null ? null : (bytes, png ? '.png' : '.jpg');
}

// The codec scales by the smaller of the two ratios, so both limits are the
// shorter side.
Future<Uint8List?> _compressed(
  String file,
  int width,
  int height, {
  required bool png,
}) {
  final (fittedWidth, fittedHeight) = fittedSize(width, height);
  final limit = min(fittedWidth, fittedHeight);
  return FlutterImageCompress.compressWithFile(
    file,
    minWidth: limit,
    minHeight: limit,
    quality: _jpegQuality,
    format: png ? CompressFormat.png : CompressFormat.jpeg,
  );
}

// For platforms the codec doesn't support.
Uint8List? _encoded(String file, {required bool png}) {
  final decoded = img.decodeImage(File(file).readAsBytesSync());
  if (decoded == null) {
    return null;
  }
  final upright = img.bakeOrientation(decoded);
  final (width, height) = fittedSize(upright.width, upright.height);
  final fitted = width == upright.width
      ? upright
      : img.copyResize(upright, width: width, height: height);
  // Otherwise the encoder writes the remaining metadata.
  fitted.exif = img.ExifData();
  return png
      ? img.encodePng(fitted)
      : img.encodeJpg(fitted, quality: _jpegQuality);
}
