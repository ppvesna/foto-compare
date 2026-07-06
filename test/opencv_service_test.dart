import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_compare/services/opencv_service.dart';

void main() {
  test('alignByAnchors calculates transform even when image bytes match',
      () async {
    final bytes = _fixtureImage();
    final refPoints = <Offset>[
      const Offset(40, 40),
      const Offset(180, 40),
      const Offset(180, 120),
      const Offset(40, 120),
    ];
    final srcPoints = refPoints.map((p) => p + const Offset(10, 5)).toList();

    final result = await OpenCvService.alignByAnchors(
      bytes,
      bytes,
      refPoints,
      srcPoints,
    );

    expect(result, isNotNull);
    expect(result!.reprojError, lessThan(1.5));
    expect(result.quality, 'excellent');
  });
}

Uint8List _fixtureImage() {
  final image = img.Image(width: 220, height: 160, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(245, 245, 242, 255));
  img.fillRect(
    image,
    x1: 34,
    y1: 34,
    x2: 186,
    y2: 126,
    color: img.ColorRgba8(20, 20, 20, 255),
  );
  img.fillRect(
    image,
    x1: 42,
    y1: 42,
    x2: 178,
    y2: 118,
    color: img.ColorRgba8(245, 245, 242, 255),
  );
  img.fillCircle(
    image,
    x: 110,
    y: 80,
    radius: 24,
    color: img.ColorRgba8(40, 120, 200, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}
