import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_compare/services/compare_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('preliminary Delta E samples level 2 and exact keeps native map',
      () async {
    final reference = _fixtureImage(changed: false);
    final sample = _fixtureImage(changed: true);

    final preliminary = await CompareService.compare(
      reference,
      sample,
      pixelStep: 2,
      includeGeometry: false,
    );
    final exact = await CompareService.compare(
      reference,
      sample,
      pixelStep: 1,
      includeGeometry: false,
    );

    final preliminaryMap = img.decodeImage(preliminary.diffL3!);
    final exactMap = img.decodeImage(exact.diffL3!);

    expect(preliminary.totalPixels, 24 * 16);
    expect(exact.totalPixels, 24 * 16);
    expect(preliminaryMap, isNotNull);
    expect(preliminaryMap!.width, 12);
    expect(preliminaryMap.height, 8);
    expect(exactMap, isNotNull);
    expect(exactMap!.width, 24);
    expect(exactMap.height, 16);
    expect(preliminary.meanDeltaE, greaterThan(0));
    expect(exact.meanDeltaE, greaterThan(0));
  });
}

Uint8List _fixtureImage({required bool changed}) {
  final image = img.Image(width: 24, height: 16, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(230, 230, 230, 255));
  img.fillRect(
    image,
    x1: 4,
    y1: 4,
    x2: 19,
    y2: 11,
    color: changed
        ? img.ColorRgba8(180, 55, 70, 255)
        : img.ColorRgba8(40, 100, 180, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}
