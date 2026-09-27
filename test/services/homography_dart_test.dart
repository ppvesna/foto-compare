import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_compare/services/homography_dart.dart';

void main() {
  test('sequential web alignment preserves the canonical result', () async {
    final source = img.Image(width: 320, height: 240);
    img.fill(source, color: img.ColorRgb8(242, 242, 242));
    img.fillRect(
      source,
      x1: 70,
      y1: 50,
      x2: 250,
      y2: 190,
      color: img.ColorRgb8(30, 110, 160),
    );
    final bytes = Uint8List.fromList(img.encodePng(source));
    const points = [
      Offset(20, 20),
      Offset(300, 20),
      Offset(300, 220),
      Offset(20, 220),
    ];

    final result = await dartAlignByAnchors(bytes, bytes, points, points);

    expect(result, isNotNull);
    expect(result!.homography, hasLength(9));
    expect(result.reprojError, lessThan(0.001));
    final reference = img.decodePng(result.refCanonicalBytes);
    final aligned = img.decodePng(result.alignedBytes);
    expect(reference, isNotNull);
    expect(aligned, isNotNull);
    expect(reference!.width, canonicalDim(100));
    expect(reference.height % 27, 0);
    expect(aligned!.width, reference.width);
    expect(aligned.height, reference.height);
  });
}
