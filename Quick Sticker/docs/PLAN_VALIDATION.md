# Валидация рисерч-плана «Быстрый жест-атач → Telegram iOS»

Дата проверки: 22.08.2026. Проверялось по свежему shallow-клону `TelegramMessenger/Telegram-iOS` (ветка `master`).

## Вердикт: план валиден ✅

Все ключевые фактические утверждения подтверждены по исходникам, большинство — с точностью до строки.

## Проверенные утверждения

| Утверждение плана | Факт в кодовой базе | Статус |
|---|---|---|
| `sendButtonLongPressed` в `ChatTextInputPanelNode.swift`, ~стр. 932 | Строки 932–934, `displaySendMessageOptions(node, gesture)` | ✅ точно |
| `attachmentButton: HighlightTrackingButton`, ~стр. 276 | Строка 276 (+ `attachmentButtonBackground` 277, `attachmentButtonIcon` 278) | ✅ точно |
| Создание кнопки ~стр. 777–788 | Строки 777–788 | ✅ точно |
| `addTarget(... attachmentButtonPressed ...)` ~стр. 918 | Строка 918 | ✅ точно |
| Лонгтап-жеста на attach-кнопке нет (жест свободен) | На `attachmentButton` только `touchUpInside` + `highligthedChanged`; long-press не навешен | ✅ |
| `externalUpdated`/`externalEnded` в `ChatSendMessageContextScreen.swift`, ~стр. 363–378 | Строки 363 и 378 | ✅ точно |
| `highlightGestureMoved` ~стр. 3163, `highlightGestureFinished` ~стр. 3186 в `ReactionContextNode.swift` | Строки 3163 и 3186 | ✅ точно |
| `displaySendMessageOptions` в `ChatPanelInterfaceInteraction.swift` | Строка 152: `(ASDisplayNode, ContextGesture) -> Void` | ✅ |
| `enqueueMediaMessages(signals:...)` в `ChatControllerOpenAttachmentMenu.swift`, ~стр. 473/1431/2069 | Строки 473, 1431, 2069 | ✅ точно |
| `MediaPickerScreen` на `PHFetchResult<PHAsset>`, кейс `.assets(fetchResult:...)` ~стр. 307 | Строка 307, включая `mediaAccess: PHAuthorizationStatus` | ✅ точно |

## Оценка плана по существу

- **Архитектурный подход верный.** Переиспользование `ContextGesture` с передачей незавершённого жеста презентуемому экрану — ровно тот паттерн, которым сделаны меню отправки и полоса реакций; фича собирается из существующих механизмов.
- **Точки врезки выбраны правильно.** `ChatTextInputPanelNode` (жест) → `ChatPanelInterfaceInteraction` (контракт) → `ChatControllerOpenAttachmentMenu.swift` (проверки прав и отправка) — минимальная связность, новый UI в отдельном модуле.
- **Разумная трактовка UX из видео** (вариант A — прикрепление, а не мгновенная отправка) с честной оговоркой, что в Telegram нет attachment-чипа в композере и нужен ближайший нативный аналог.
- **Риски описаны адекватно** (limited photos access, дрейф номеров строк, UX-риск варианта B).

## Замечания (не блокирующие)

1. **Оценка сроков (6–8 дней) реалистична только для варианта A через существующий медиапикер.** Пиксель-в-пиксель повтор анимации «перелёта» в композер потребует кастомного attachment-превью, которого в Telegram нет, — это может добавить 2–3 дня.
2. **`attachmentButton` теперь обёрнут в `GlassBackgroundView`** (новый glass-UI Telegram) — якорь анимаций нужно брать от `attachmentButtonBackground`, а не от самой кнопки.
3. **Сборка полного Telegram-iOS требует macOS + Bazel + собственные `api_id`/`api_hash`** — в CI/линукс-окружении невозможна; поэтому прототип UX реализован как отдельное приложение (этот репозиторий), а план интеграции остаётся картой для переноса.
