import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/capture/capture.dart';
import 'package:photo_compare/screens/camera_calibration_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('camera calibration wizard shows the four-step workflow',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: CameraCalibrationScreen(
          captureSettings: CameraCaptureSettings.defaults,
          cameraName: 'USB camera',
          resolution: '3840 x 2160',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Калибровка камеры'), findsOneWidget);
    expect(find.text('1. Условия съёмки и прибор'), findsOneWidget);
    expect(find.text('2. Фото калибровочной шкалы'), findsOneWidget);
    expect(find.text('3. Поля шкалы и измерения'), findsOneWidget);
    expect(find.text('4. Расчёт и проверка профиля'), findsOneWidget);
    expect(find.text('Загрузить фото'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
