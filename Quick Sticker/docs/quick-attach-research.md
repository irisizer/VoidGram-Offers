# Быстрый жест-атач по лонгтапу (как в ChatGPT) → Telegram iOS

Рисерч: анализ видео + разбор кодовой базы `TelegramMessenger/Telegram-iOS` + план реализации.

Дата: 22.08.2026. Кодовая база сверена с веткой `master`, коммит `6ad963e5b62d` (18.07.2026).

---

## 1. Анализ видео (ScreenRecording_08-22-2026_09-53-46_1.mp4)

Параметры: 7.2 с, 1290×2796, 60 fps (запись экрана iPhone, приложение ChatGPT, вкладка Work).

### Раскадровка

| Время | Что происходит |
|---|---|
| 0.0–0.9 с | Исходное состояние: композер с кнопкой «+» слева, плейсхолдер «Work with ChatGPT», клавиатура открыта. |
| ~1.0 с | Срабатывает лонгтап по «+» (порог удержания ≈ 0.3–0.5 с). Из точки кнопки «веером» выпрыгивают 4 миниатюры последних фото галереи и раскладываются в горизонтальную полосу над композером (staggered spring слева направо). |
| ~1.0–1.1 с | Одновременно: весь остальной UI — чат, композер, клавиатура — блюрится/приглушается, но остаётся на месте. Кнопка «+» морфится в «×» (отмена). |
| 1.1–4.1 с | Палец не отпущен. Миниатюра под пальцем увеличивается (scale ≈ 1.1–1.2, spring), остальные — обычного размера. Подсветка следует за пальцем. |
| ~4.2 с | Отпускание над первой миниатюрой: невыбранные миниатюры тают/сжимаются, блюр уходит, композер расширяется, выбранное фото перелетает в него и становится **вложением** — превью со скруглением и бейджем «×» в углу. Кнопка отправки становится активной (синей). |
| 4.4–7.2 с | Статичное состояние «фото прикреплено». В конце ролика пользователь удаляет вложение по «×» — возврат к исходному состоянию. |

### Механика жеста (спецификация)

1. **Триггер:** long-press по кнопке атача. Обычный тап сохраняет прежнее поведение (открытие полного меню).
2. **Появление:** полоса из N последних фото галереи (в ролике N = 4), анимация «из точки кнопки», фон блюрится, кнопка превращается в «×».
3. **Трекинг:** пока палец зажат, элемент под пальцем подсвечивается увеличением; смена элемента — с хаптиком.
4. **Отпускание над элементом:** элемент выбран.
5. **Отпускание над «×» / мимо полосы:** отмена, обратная анимация.

### Важный нюанс

В ролике при отпускании фото **не отправляется мгновенно, а прикрепляется к полю ввода** (attachment-чип с «×»); сообщение уходит только по кнопке send. В исходной формулировке задачи было «отпускаю — отправляются». В плане ниже предусмотрены **оба варианта** поведения (раздел 4, этап 6).

---

## 2. Репозиторий

- **Официальный клиент:** https://github.com/TelegramMessenger/Telegram-iOS (организация TelegramMessenger, repo id 157590294).
- **Стек:** Swift (+ немного Objective-C в LegacyComponents), собственный UI-фреймворк на базе AsyncDisplayKit/Texture (модуль `Display`), сборка **Bazel** через `build-system/Make/Make.py`.
- **Структура:** сотни модулей в `submodules/`, основной продуктовый код — `submodules/TelegramUI`.

---

## 3. Рисерч кодовой базы

### 3.1. Ключевая находка: нужный паттерн жеста уже существует

В приложении уже есть две фичи с точно такой же физикой «зажал → веди палец → подсветка под пальцем → отпустил = выбрал»:

**а) Лонгтап по кнопке отправки** (меню «Отправить без звука / Запланировать»):

- `submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift`, ~стр. 932:
  ```swift
  self.sendActionButtons.sendButtonLongPressed = { [weak self] node, gesture in
      self?.interfaceInteraction?.displaySendMessageOptions(node, gesture)
  }
  ```
  Жест (`ContextGesture`) передаётся дальше **не завершённым** — презентуемый экран продолжает получать координаты пальца.

- `submodules/ChatSendMessageActionUI/Sources/ChatSendMessageContextScreen.swift`, ~стр. 363–378: экран подписывается на
  ```swift
  component.gesture?.externalUpdated = { view, location in ... } // палец двигается → подсветка
  component.gesture?.externalEnded  = { viewAndLocation in ... } // палец отпущен → действие
  ```

**б) Полоса реакций** (лонгтап по сообщению → веди палец по эмодзи):

- `submodules/ReactionSelectionNode/Sources/ReactionContextNode.swift`:
  - `highlightGestureMoved(location:hover:)` (~стр. 3163) — хит-тест и подсветка под пальцем;
  - `highlightGestureFinished(performAction:)` (~стр. 3186) — выбор при отпускании.

**в) Кнопка микрофона** — ещё один референс непрерывного press-and-drag трекинга: `submodules/TelegramUI/Components/ChatTextInputMediaRecordingButton/`.

Вывод: жестовую часть фичи можно собрать почти целиком из существующих механизмов (`ContextGesture` из `submodules/Display/Source/ContextGesture.swift`).

### 3.2. Кнопка атача (точка входа)

Файл: `submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift`

- ~стр. 276: `public let attachmentButton: HighlightTrackingButton` (+ `attachmentButtonBackground: GlassBackgroundView`, `attachmentButtonIcon: UIImageView`);
- ~стр. 777–788: создание кнопки;
- ~стр. 918: `addTarget(... #selector(attachmentButtonPressed), for: .touchUpInside)`;
- ~стр. 5641: `@objc func attachmentButtonPressed()` → `displayAttachmentMenu()` → через `interfaceInteraction` открывается полное меню вложений.

Лонгтап-жеста на кнопке сейчас нет — жест свободен, конфликтов не будет.

### 3.3. Контракт «панель → контроллер»

- `submodules/ChatPresentationInterfaceState/Sources/ChatPanelInterfaceInteraction.swift` — интерфейс всех колбэков панели ввода (здесь живёт `displaySendMessageOptions`; сюда же добавится новый метод).
- `submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift` — реализация открытия attach-меню (`AttachmentController`), проверки прав чата и **путь отправки медиа**: `enqueueMediaMessages(signals:silentPosting:scheduleTime:...)` (вызовы на ~стр. 473, 1431, 2069).

### 3.4. Источник «последних фото»

- `submodules/MediaPickerUI/Sources/MediaPickerScreen.swift` — пикер построен на `PHFetchResult<PHAsset>` (state-кейс `.assets(fetchResult:...)`, ~стр. 307+), т.е. паттерны запроса галереи через Photos framework в проекте уже есть, включая обработку `PHAuthorizationStatus` (limited/denied).
- Полное меню вложений: `submodules/AttachmentUI/Sources/AttachmentController.swift` (+ `AttachmentPanel`, `AttachmentContainer`).

### 3.5. Прочие строительные блоки

- Хаптика: `submodules/Display/Source/HapticFeedback.swift` (`HapticFeedback().tap()` / `.impact()`).
- Блюр-подложки: собственные ноды затемнения/блюра в `Display` + `UIVisualEffectView`-обёртки (используются контекст-меню и полосой реакций).
- Анимации: везде spring-транзишены `ContainedViewLayoutTransition` / `ComponentTransition`.

---

## 4. План реализации

### Этап 0. Подготовка (0.5 дня)
Прочитать референсы из п. 3.1: `ChatSendMessageContextScreen.swift`, `ReactionContextNode.swift`, `ContextGesture.swift`. Понять жизненный цикл `ContextGesture`: активация → `activated(gesture, location)` → передача жеста презентуемому экрану → `externalUpdated`/`externalEnded`.

### Этап 1. Жест на кнопке скрепки (~0.5 дня)
В `ChatTextInputPanelNode.swift`:
- навесить `ContextGesture` на `attachmentButton` по образцу кнопки отправки;
- добавить колбэк `attachmentButtonLongPressed: ((ASDisplayNode/UIView, ContextGesture) -> Void)?`;
- тап оставить без изменений (полное меню).

### Этап 2. Проброс в контроллер (~0.5 дня)
- Новый метод в `ChatPanelInterfaceInteraction` — `displayQuickAttachment(sourceView, gesture)`.
- Реализация в чат-контроллере рядом с `presentAttachmentMenu` (файл `ChatControllerOpenAttachmentMenu.swift`) — там уже есть все проверки: права чата (запрет медиа), secret-чаты, slowmode и т.д. Если быстрый атач недоступен — молча открыть обычное меню.

### Этап 3. Новый модуль `QuickAttachmentUI` (~1.5–2 дня)
Оверлей-контроллер (по архитектуре похож на `ChatSendMessageContextScreen`):
- полноэкранная блюр/дим-подложка;
- горизонтальная полоса из 4–6 миниатюр над композером, выровнена по кнопке скрепки;
- кнопка «×» на месте «+» (морф иконки);
- якорь анимаций — фрейм `attachmentButton`, переданный через `convert(_:to:)`;
- появление: staggered spring из точки кнопки (задержка ~30 мс между айтемами), исчезание — обратное.

### Этап 4. Данные (~0.5–1 день)
- `PHAsset.fetchAssets(with: .image, options:)`, сортировка по `creationDate desc`, `fetchLimit` = 4–6;
- миниатюры через `PHCachingImageManager` (таргет-сайз ≈ 2× размер ячейки);
- разрешения: `.authorized`/`.limited` → показываем что есть; `.denied`/`.notDetermined` → лонгтап ведёт в обычное меню (оно само запросит доступ);
- опционально видео вторым шагом (в ролике только фото).

### Этап 5. Трекинг пальца (~0.5 дня)
- `gesture.externalUpdated` → перевод координаты в систему полосы → хит-тест айтема → подсветка scale 1.0 → ~1.15 spring; при смене айтема `HapticFeedback().tap()`;
- `gesture.externalEnded` → если палец над айтемом — выбрать; над «×»/мимо — отменить.

### Этап 6. Действие при отпускании (~1 день)
Два варианта, решить продуктово (или спрятать за настройку):
- **Вариант A — как в видео (прикрепление):** у Telegram нет attachment-чипа в композере, ближайший нативный аналог — открыть стандартный медиапикер/превью с уже выбранным ассетом и полем подписи; пользователь жмёт send сам. Безопасно от случайных отправок.
- **Вариант B — мгновенная отправка (как в исходной формулировке):** сконвертировать выбранный `PHAsset` в сигнал и вызвать существующий `enqueueMediaMessages(signals:...)`. Максимально быстро, но есть риск случайной отправки — рекомендуется хотя бы undo-тост или подтверждающий хаптик-порог.

Рекомендация: начать с A (совпадает с референсом из видео), B добавить настройкой «Отправлять сразу».

### Этап 7. Полиш и edge cases (~1–2 дня)
- запреты чата (banSendMedia/banSendPhotos) — переиспользовать проверки attach-меню;
- scheduled-чаты, форумы/топики, slowmode;
- VoiceOver: жест недоступен — остаётся тап (полное меню);
- iPad / landscape / RTL-раскладка полосы;
- пустая галерея / медленная загрузка миниатюр (плейсхолдеры);
- телеметрия/фича-флаг при необходимости.

### Этап 8. Сборка и проверка (~0.5 дня)
- Сборка: `python3 build-system/Make/Make.py ...` (Bazel); для запуска нужны собственные `api_id`/`api_hash` (описано в README репозитория).
- Ручной прогон сценариев: выбор каждого айтема, отмена по «×», отмена свайпом мимо, denied-доступ, чат с запретом медиа.

**Итоговая оценка: ~6–8 рабочих дней** на вариант A с полировкой анимаций.

---

## 5. Карта изменений (сводно)

| Файл/модуль | Изменение |
|---|---|
| `submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift` | `ContextGesture` на `attachmentButton`, колбэк `attachmentButtonLongPressed` |
| `submodules/ChatPresentationInterfaceState/Sources/ChatPanelInterfaceInteraction.swift` | новый метод `displayQuickAttachment(...)` |
| `submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift` | реализация: проверки прав → презентация оверлея; выбор → пикер с предвыбором (A) или `enqueueMediaMessages` (B) |
| **новый** `submodules/TelegramUI/Components/QuickAttachmentUI/` | оверлей: блюр, полоса миниатюр, анимации, трекинг `externalUpdated`/`externalEnded` |
| Референсы (без изменений) | `ChatSendMessageContextScreen.swift`, `ReactionContextNode.swift`, `ContextGesture.swift`, `MediaPickerUI`, `HapticFeedback.swift` |

---

## 6. Риски

- **Огромный `ChatControllerOpenAttachmentMenu.swift` / связность TelegramUI** — правки точечные, но пересборка модуля долгая; держать новый UI в отдельном модуле.
- **Line-номера дрейфуют** — репозиторий очень активный; ориентироваться на символы (`attachmentButton`, `sendButtonLongPressed`, `externalUpdated`), а не на номера строк.
- **Вариант B (мгновенная отправка)** — UX-риск случайных отправок; закрыть настройкой/undo.
- **Limited Photos access (iOS 14+)** — полоса может быть пустой; нужен фолбэк в полное меню.
