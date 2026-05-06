# Подключение OpenCV — пошаговая инструкция

## Шаг 1 — android/app/build.gradle

Добавить одну строку в `dependencies`:

```gradle
dependencies {
    implementation("org.opencv:opencv:4.9.0")   // ← добавить
}
```

## Шаг 2 — скопировать OpenCvPlugin.kt

Скопировать файл:
```
opencv_android/OpenCvPlugin.kt
```
В папку:
```
android/app/src/main/kotlin/com/example/photo_compare/OpenCvPlugin.kt
```

## Шаг 3 — обновить MainActivity.kt

Заменить содержимое `android/app/src/main/kotlin/com/example/photo_compare/MainActivity.kt`:

```kotlin
package com.example.photo_compare

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(OpenCvPlugin())
    }
}
```

## Шаг 4 — запустить

```bash
flutter clean
flutter run
```

## Что появится после подключения

- Кнопка **📐 Перспектива** в режиме Выравнивание — автоматически выправляет фото снятое под углом
- **SSIM** метрика в результатах — точнее чем MAE
- **ORB выравнивание** — точное совмещение по характерным точкам
