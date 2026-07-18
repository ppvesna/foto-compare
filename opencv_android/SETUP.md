# Android / OpenCV

OpenCV уже подключён к Android-проекту. Этот документ описывает текущую конфигурацию и её
проверку. Шаги копирования файлов вручную больше не нужны.

## Текущая конфигурация

Gradle Kotlin DSL:

```text
android/app/build.gradle.kts
```

Подключённая зависимость:

```kotlin
dependencies {
    implementation("org.opencv:opencv:4.9.0")
}
```

Плагин:

```text
android/app/src/main/kotlin/com/example/photo_compare/OpenCvPlugin.kt
```

Регистрация:

```text
android/app/src/main/kotlin/com/example/photo_compare/MainActivity.kt
```

`MainActivity` добавляет `OpenCvPlugin` в `configureFlutterEngine`. MethodChannel:

```text
com.example.photo_compare/opencv
```

## Доступные native-методы

Текущий Kotlin-плагин содержит:

- `alignByAnchors`;
- `compareImages`;
- `splitModules`;
- `stitchImages`;
- `fuseImages`;
- `detectCorners`;
- `ssim`;
- `alignImages`;
- `alignPyramid`;
- `perspectiveCorrect`.

Наличие native-метода не означает, что для него есть активная UI-кнопка. Основной текущий путь
калибровки: `alignByAnchors`. Старые автоматические кнопки перспективы и пирамиды из интерфейса удалены.

## Проверка сборки

```bash
flutter clean
flutter pub get
flutter build apk --debug
```

Или запуск на подключённом Android-устройстве/эмуляторе:

```bash
flutter devices
flutter run -d <device-id>
```

Минимальная ручная проверка:

1. загрузить эталон и образец;
2. поставить одинаковые пары точек;
3. нажать «Рассчитать»;
4. убедиться, что `alignByAnchors` возвращает совмещённое изображение;
5. запустить сравнение;
6. проверить геометрию, Delta E и наложение.

## Резервные копии

`opencv_android/` содержит исходные копии `OpenCvPlugin.kt` и `MainActivity.kt`. Они не участвуют в Android-сборке.
Рабочие файлы находятся в `android/app/src/main/...`.

Резервная копия может отставать от рабочего плагина. При изменении OpenCV нужно либо синхронизировать
обе копии, либо отказаться от резервной копии отдельным решением.

## Ограничения

- Нативный плагин есть только для Android.
- Web использует Dart/Web Worker путь, а не Kotlin OpenCV.
- iOS-адаптер не реализован.
- Release-сборка пока использует debug signing и не готова к публикации.

## Architecture v2

В целевой архитектуре Android OpenCV станет одним из адаптеров `alignment` и `color_analysis`. Domain и
`inspection` не должны зависеть от MethodChannel или Kotlin-типов.
