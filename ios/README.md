# Message — iOS-клиент (SwiftUI)

Нативное приложение для iPhone к тому же бэкенду, что и веб-клиент (`server/`). Реализованы:

- регистрация/вход;
- список чатов и переписка;
- отправка текста, голосовых, видеосообщений в кружках и файлов;
- поиск пользователей и старт диалога;
- переключение светлой/тёмной темы.

Обмен сообщениями и медиа работает через те же REST-эндпоинты, что и веб-клиент.

## Требования

- Xcode 15+ (iOS 17+)
- Сервер запущен и доступен по сети (для симулятора: `http://127.0.0.1:3001`; для **реального iPhone** — IP компьютера в Wi‑Fi, например `http://192.168.1.10:3001`)

## Создание проекта в Xcode

1. **File → New → Project → App** (iOS, SwiftUI, Swift).
2. Название: `MessageApp`, минимальная версия iOS 17.
3. Скопируйте **все** `.swift` из `MessageApp/Sources/` в проект и отметьте target **MessageApp**.
4. **Уберите дубли из шаблона Xcode**, иначе будет «Multiple commands produce …» и лишний `@main`:
   - Должен остаться **один** файл с `@main` — наш `MessageAppApp.swift` (или переименуйте под ваше имя приложения, но не дублируйте `@main`).
   - Удалите **старый** автоматический `ContentView.swift` из шаблона **или** полностью замените его содержимое на версию из репозитория (в репозитории уже есть актуальный `ContentView.swift`).
5. В `APIConfig.swift` задайте `baseURL` (без завершающего слэша).
6. **Info** → **App Transport Security**:
   - для разработки с HTTP добавьте исключение для вашего хоста или `NSAllowsArbitraryLoads` = YES (только для отладки).

### Разрешения (для будущих медиа)

В `Info.plist` добавьте:

- `NSMicrophoneUsageDescription`
- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription`

На симуляторе камера недоступна: кнопка видеосообщения автоматически откроет выбор видео из медиатеки.

## Сборка

Откройте `.xcodeproj`, выберите симулятор или устройство, **Product → Clean Build Folder**, затем **Run**.

### Если были ошибки про `Combine` / `ObservableObject` / `@Published`

В `SessionStore.swift` должен быть `import Combine` (в репозитории он уже добавлен).

### Если «фантомные» ошибки про `.swiftmodule` / `.abi.json`

Обычно это следствие первой неудачной сборки. Сделайте **Clean Build Folder**, удалите папку **Derived Data** (Xcode → Settings → Locations → стрелка у Derived Data → удалить для проекта), соберите снова.

## API

Совпадает с веб-клиентом: `POST /api/auth/login`, `GET /api/conversations`, `GET/POST /api/conversations/:id/messages`, заголовок `Authorization: Bearer <token>`.
