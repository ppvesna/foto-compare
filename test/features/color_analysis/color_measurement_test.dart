import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_compare/features/color_analysis/color_analysis.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CIEDE2000 matches the published Sharma reference pair', () {
    const first = LabColor(50, 2.6772, -79.7751);
    const second = LabColor(50, 0, -82.7485);

    final value = ColorDifferenceCalculator.deltaE(
      first,
      second,
      DeltaEFormula.ciede2000,
    );

    expect(value, closeTo(2.0425, 0.0001));
  });

  test('all Delta E formulas return zero for equal Lab values', () {
    const color = LabColor(53.2, 18.4, -7.9);

    for (final formula in DeltaEFormula.values) {
      expect(
        ColorDifferenceCalculator.deltaE(color, color, formula),
        closeTo(0, 0.0000001),
        reason: formula.name,
      );
    }
  });

  test('point aperture samples a larger circular area at 5 mm', () {
    final image = img.Image(width: 21, height: 21, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(120, 130, 140, 255));

    final small = ColorMeasurementEngine.measurePoint(
      image,
      x: 10,
      y: 10,
      settings: ColorMeasurementSettings.defaults,
      pixelsPerMm: 1,
    );
    final large = ColorMeasurementEngine.measurePoint(
      image,
      x: 10,
      y: 10,
      settings: ColorMeasurementSettings.defaults.copyWith(
        aperture: MeasurementAperture.mm5,
      ),
      pixelsPerMm: 1,
    );

    expect(small.sampledPixels, 5);
    expect(large.sampledPixels, greaterThan(small.sampledPixels));
  });

  test('image-relative optical density follows CMY filter channels', () {
    final density = OpticalDensityMeasurement.imageRelativeFromRgb(
      255 / 40,
      255 / 20,
      255 / 10,
    );

    expect(density.cyan, closeTo(1.60205999, 0.000001));
    expect(density.magenta, closeTo(1.30102999, 0.000001));
    expect(density.yellow, closeTo(1.0, 0.000001));
    expect(density.black, greaterThan(1.0));
  });

  test('white image has zero image-relative optical density', () {
    final density = OpticalDensityMeasurement.imageRelativeFromRgb(
      255,
      255,
      255,
    );

    expect(density.cyan, closeTo(0, 0.000001));
    expect(density.magenta, closeTo(0, 0.000001));
    expect(density.yellow, closeTo(0, 0.000001));
    expect(density.black, closeTo(0, 0.000001));
  });

  test('measurement profile persists locally', () async {
    const selected = ColorMeasurementSettings(
      deltaEFormula: DeltaEFormula.ciede2000,
      aperture: MeasurementAperture.mm5,
    );

    await ColorMeasurementSettingsService.save(selected);
    final loaded = await ColorMeasurementSettingsService.load();

    expect(loaded.deltaEFormula, DeltaEFormula.ciede2000);
    expect(loaded.aperture, MeasurementAperture.mm5);
  });
}
