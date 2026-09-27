import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/capture/capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('camera calibration fits Lab and density from training patches', () {
    final now = DateTime.utc(2026, 9, 27);
    final profile = CameraCalibrationProfile(
      id: 'profile-1',
      name: 'Studio D50',
      camera: 'USB camera',
      lens: '35 mm',
      lighting: 'D50',
      opticalFilter: 'UV-cut',
      measurementCondition: CalibrationMeasurementCondition.m1,
      patches: [
        _patch('white', 255, 255, 255),
        _patch('black', 0, 0, 0),
        _patch('red', 255, 0, 0),
        _patch('green', 0, 255, 0),
        _patch('blue', 0, 0, 255),
        _patch('gray', 128, 128, 128),
        _patch('validation-1', 64, 180, 220, validation: true),
        _patch('validation-2', 210, 80, 40, validation: true),
      ],
      model: null,
      enabled: false,
      createdAt: now,
      updatedAt: now,
    );

    final model = CameraCalibrationFitter.fit(profile);
    final lab = model.labForRgb(64, 180, 220);
    final density = model.densityForRgb(64, 180, 220);

    expect(lab.l, closeTo(_l(64, 180, 220), 0.0001));
    expect(lab.a, closeTo(_a(64, 180, 220), 0.0001));
    expect(lab.b, closeTo(_b(64, 180, 220), 0.0001));
    expect(density, isNotNull);
    expect(density!.c, closeTo(_dc(64, 180, 220), 0.0001));
    expect(model.validationMeanDeltaE, closeTo(0, 0.0001));
    expect(model.validationDensityMae, closeTo(0, 0.0001));
  });

  test('camera calibration profile persists as the active profile', () async {
    final now = DateTime.utc(2026, 9, 27);
    final profile = CameraCalibrationProfile(
      id: 'profile-1',
      name: 'Studio D50',
      camera: 'USB camera',
      lens: '35 mm',
      lighting: 'D50',
      opticalFilter: 'UV-cut',
      measurementCondition: CalibrationMeasurementCondition.m1,
      patches: [_patch('white', 255, 255, 255)],
      model: null,
      enabled: false,
      createdAt: now,
      updatedAt: now,
    );

    await CameraCalibrationProfileService.save(profile);
    final loaded = await CameraCalibrationProfileService.loadActive();

    expect(loaded?.id, 'profile-1');
    expect(loaded?.patches.single.label, 'white');
    expect(loaded?.measurementCondition, CalibrationMeasurementCondition.m1);
  });
}

CameraCalibrationPatch _patch(
  String label,
  double red,
  double green,
  double blue, {
  bool validation = false,
}) {
  return CameraCalibrationPatch(
    id: label,
    label: label,
    red: red,
    green: green,
    blue: blue,
    labL: _l(red, green, blue),
    labA: _a(red, green, blue),
    labB: _b(red, green, blue),
    densityC: _dc(red, green, blue),
    densityM: _dm(red, green, blue),
    densityY: _dy(red, green, blue),
    densityK: _dk(red, green, blue),
    validation: validation,
  );
}

double _n(double value) => value / 255;
double _l(double r, double g, double b) =>
    10 + 30 * _n(r) + 40 * _n(g) + 20 * _n(b);
double _a(double r, double g, double b) =>
    -5 + 50 * _n(r) - 30 * _n(g) + 10 * _n(b);
double _b(double r, double g, double b) =>
    2 - 10 * _n(r) + 20 * _n(g) + 40 * _n(b);
double _dc(double r, double g, double b) =>
    0.1 + 1.2 * _n(r) + 0.1 * _n(g) + 0.2 * _n(b);
double _dm(double r, double g, double b) =>
    0.2 + 0.1 * _n(r) + 1.1 * _n(g) + 0.1 * _n(b);
double _dy(double r, double g, double b) =>
    0.15 + 0.1 * _n(r) + 0.2 * _n(g) + 1.0 * _n(b);
double _dk(double r, double g, double b) =>
    0.05 + 0.3 * _n(r) + 0.5 * _n(g) + 0.2 * _n(b);
