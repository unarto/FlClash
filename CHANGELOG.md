## v0.2.0 (март 2026)

### UI / Дизайн
- Один главный экран вместо четырёх вкладок
- 4 карточки: Импорт ключа, Вкл/Выкл, Россия вперёд!, Настройки
- Material You M3: светлый фон, закруглённые карточки, пастельные акценты
- Подпись "from pavel with love ♥" внизу экрана
- Новая иконка: синий градиент #0039A6 + красная буква R

### Функции
- Пресет «Россия 2026»: 40+ доменов напрямую
- Экран диагностики доступа (YouTube, Telegram, Gemini, банки)
- Онбординг для новых пользователей
- Улучшены сообщения об ошибках импорта подписки

### Инфраструктура
- GitHub Actions: автосборка APK (Flutter 3.41.2, arm64)
- Code review: исправлены утечки памяти и async safety
- Очистка репозитория
```

Commit directly to main.

---

**Часть 2 — README с красивым HTML**

Отправь в Codex:

---
```
TASK: Replace README.md with a beautiful HTML-styled markdown.

Replace entire content of README.md with exactly this:

<div align="center">

<img src="assets/icon/app_icon.png" width="120" height="120" style="border-radius: 28px" alt="FlClashR icon"/>

# FlClashR 🇷🇺

**Свободный интернет в одну кнопку**

VPN-клиент для России. Простой как выключатель.

[![Build APK](https://github.com/rupaulogit/FlClashR/actions/workflows/build-apk.yml/badge.svg)](https://github.com/rupaulogit/FlClashR/actions/workflows/build-apk.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.41.2-blue?logo=flutter)
![License](https://img.shields.io/badge/License-GPLv3-green)
![Platform](https://img.shields.io/badge/Platform-Android-brightgreen?logo=android)

</div>

---

## ✨ Возможности

| | |
|---|---|
| 🚀 **Один экран** | Четыре кнопки — больше ничего лишнего |
| 🇷🇺 **Россия, вперёд!** | YouTube, Telegram, Gemini — через VPN. Банки, Госуслуги — напрямую |
| 🔒 **DNS Cloudflare** | 1.1.1.1 вместо утечек через провайдера |
| 📋 **Импорт по ссылке** | Вставьте URL подписки и готово |
| 🎨 **Material You** | Адаптивный дизайн, тёмная тема |
| 🏥 **Диагностика** | Проверка доступа к сервисам одной кнопкой |

---

## 📱 Скриншоты

> Главный экран — четыре карточки, один тап для подключения

---

## ⬇️ Установка

1. Зайдите в раздел [Actions](../../actions/workflows/build-apk.yml)
2. Откройте последний успешный билд
3. Скачайте `FlClashRP-debug` из раздела **Artifacts**
4. Установите APK на Android (разрешите установку из неизвестных источников)

---

## 🇷🇺 Пресет «Россия 2026»

Одна кнопка настраивает всё:

- **Через VPN**: YouTube, Telegram, Google, Gemini, Instagram
- **Напрямую**: Сбербанк, ВТБ, Альфа, Госуслуги, ВКонтакте, Ozon, Wildberries, РЖД, Яндекс и 30+ других
- **DNS**: Cloudflare (1.1.1.1) — защита от утечек
- **TUN**: gvisor — стабильная работа на Android

---

## 🛠 Сборка
```bash
git clone https://github.com/rupaulogit/FlClashR
cd FlClashR
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --debug
```

---

## 📄 Лицензия

GPLv3 — форк [FlClash](https://github.com/chen08209/FlClash) by chen08209

---

<div align="center">
<sub>made with ♥ by pavel</sub>
</div>

After saving:
git add README.md
git commit -m "docs: beautiful README with features and install guide"
