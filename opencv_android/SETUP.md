# Подключение OpenCV к Android

## Шаг 1 — Добавить зависимость в android/app/build.gradle

```gradle
dependencies {
    implementation 'org.opencv:opencv:4.9.0'   // добавить эту строку
    // ... остальные зависимости
}
```

## Шаг 2 — Скопировать OpenCvPlugin.kt

Скопировать файл `opencv_android/OpenCvPlugin.kt` в:
```
android/app/src/main/kotlin/com/example/photo_compare/OpenCvPlugin.kt
```
(заменить `com/example/photo_compare` на фактический пакет приложения)

## Шаг 3 — Зарегистрировать плагин в MainActivity.kt

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

## Шаг 4 — Запустить

```bash
flutter clean
flutter run
```

## Что получите

| Функция | Описание |
|---|---|
| 📐 Перспектива | Автоматически выравнивает перспективу распечатки |
| ORB выравнивание | Точное совмещение по характерным точкам |
| SSIM метрика | Точнее MAE для оценки качества печати |
| Обнаружение углов | Находит контур листа на фото |

## Fallback

Если OpenCV не подключён — приложение работает в обычном режиме.
Кнопка «📐 Перспектива» покажет сообщение что плагин недоступен.
