import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/capture/capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads legacy color fields as camera metadata', () async {
    SharedPreferences.setMockInitialValues({
      'color.illuminant': 'd50',
      'color.measurementCondition': 'm3',
    });

    final loaded = await CameraCaptureSettingsService.load();

    expect(loaded.lighting, CameraLighting.d50);
    expect(loaded.opticalFilter, CameraOpticalFilter.polarizer);
  });

  test('camera lighting and filter persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    const selected = CameraCaptureSettings(
      lighting: CameraLighting.d65,
      opticalFilter: CameraOpticalFilter.uvCut,
    );

    await CameraCaptureSettingsService.save(selected);
    final loaded = await CameraCaptureSettingsService.load();

    expect(loaded.lighting, CameraLighting.d65);
    expect(loaded.opticalFilter, CameraOpticalFilter.uvCut);
  });
}
