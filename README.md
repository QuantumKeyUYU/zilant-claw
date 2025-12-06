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
