# Digital Defender

MVP скелет приложения Digital Defender: единый экран с драконом и тумблером, Android VPN-защита и Windows-заглушка.

## Сборка

- Flutter: проект настроен для Android и Windows. Укажите путь к Flutter SDK в `android/local.properties` и `windows/flutter/generated_config.cmake` при сборке.
- Android: VPN-сервис `DigitalDefenderVpnService` поднимает локальный VpnService и перехватывает DNS-запросы, блокируя домены из `assets/blocklists/android_basic.txt`.
- Windows: метод-канал логирует включение/выключение защиты (заглушка).

## Структура
- `lib/` — Flutter UI и контроллер состояния.
- `android/` — нативный код Android (Kotlin) с VPN-сервисом.
- `windows/` — раннер Windows с обработкой метод-канала.
- `assets/blocklists/` — пример блоклиста.

> Дракон на экране сейчас реализован как простой виджет (emoji + градиент), без использования бинарных изображений.

## Дополнение для obfusgated-теста

- Файл `assets/blocklists/blocklist_test_obfusgated.txt` участвует только в продвинутом (strict/advanced) режиме и дополняет расширенный блоклист.
- Формат поддерживает комментарии с `#`, правила allowlist через префикс `@@` и подстановки поддоменов через `*.` или ведущую точку.
- Цикл работы с тестом:
  1. Включите режим Advanced в приложении.
  2. Прогоните obfusgated-тест и соберите домены, которые остались незаблокированными.
  3. Добавьте эти домены в `assets/blocklists/blocklist_test_obfusgated.txt` и пересоберите APK.
