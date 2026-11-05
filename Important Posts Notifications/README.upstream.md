# Unmute Similar — notifications for important posts in muted channels

A muted channel stays muted, but posts that matter still notify you — by keyword or by post type.
Hold a post → **Unmute Similar** opens an editor with words from that post as suggestions; add your
own keywords and pick post types (photos, GIFs, polls, giveaways, …). Matching posts get a bell
badge in the chat list, and a bell button in the chat jumps through them one by one.

Telegram-iOS concept, UIKit / AsyncDisplayKit, built on top of the official sources.

▶︎ [Media/demo.mp4](Media/demo.mp4) — the full flow recorded in the offline demo (1920×1920, 60 fps).

## Repository

| Path | What |
|---|---|
| `submodules/…` | New files, at the same paths as in Telegram-iOS — copy the folder over a checkout. |
| `Integration/telegram-ios.patch` | Changes to existing Telegram-iOS files (`git apply`). |
| `Demo/Assets/` | Avatars, post images and stickers for the offline demo. |
| `Media/demo.mp4` | Recording of the demo. |

### Feature

| File | What |
|---|---|
| `TelegramCore/Sources/Concepts/ConceptsMuteExceptions.swift` | Exception model (keywords + post types) per channel, stored locally in a `PreferencesEntry`; matching of a message against it. |
| `TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoMuteExceptionsScreen.swift` | The editor: header, keywords, post types with expandable groups, "Remove All Exceptions". |
| `…/PeerInfoMuteExceptionsKeywordsItem.swift` | Keyword field with chips; suggested words from the post as dashed chips. |
| `…/PeerInfoMuteExceptionSuggestions.swift` | Picks words worth suggesting from the post text (tickers and names first, no stop words). |
| `…/PeerInfoMuteExceptionsFooterItem.swift` | Footer button pinned to the bottom of the editor. |
| `TelegramUI/Sources/ConceptsMuteExceptionQuickAdd.swift` | Opens the editor as a sheet from the post context menu, with suggestions from that post. |
| `TelegramUI/Sources/ConceptsMuteExceptionNavigation.swift` | Unread posts that passed an exception; feeds the bell button in the chat and highlights the matched word. |
| `ChatListUI/Sources/Node/ConceptsMuteExceptionBadge.swift` | Bell badge and active unread counter in the chat list. |
| `TelegramUI/Resources/Animations/ConceptsBell*.tgs` | Muted / ringing bell stickers (header and menu). |

Hooks in existing files (see the patch): context menu item (`ChatInterfaceStateContextMenus.swift`),
notification decision for muted channels (`AccountStateManager.swift`), chat list badge
(`ChatListItem.swift`, `ChatListNode*.swift`), bell button above the input panel
(`ChatHistoryNavigationButton*.swift`, `ChatControllerLoadDisplayNode.swift`), editor header with the
channel avatar (`ChatListFilterSettingsHeaderItem.swift`), expandable switch rows
(`ItemListExpandableSwitchItem.swift`).

### Offline demo and recording

| File | What |
|---|---|
| `TelegramUI/Sources/ConceptsOfflineDemo.swift`, `TelegramCore/Sources/Concepts/ConceptsOfflineDemo.swift` | Fictional account and chats written to Postbox; the network never answers, nothing leaves the device. |
| `TelegramUI/Sources/ConceptsDemoAutopilot.swift` | Scripted run of the whole flow used for the recording. |
| `TelegramUI/Sources/ConceptsDemoTouchInjector.swift` | Real touch events for the autopilot (taps, long press, drags). |

Everything demo-specific is behind `--concepts-offline-demo` / `--concepts-demo-*` launch arguments;
without them the app behaves as upstream.

## How it works

* **Matching.** A post of a muted channel is checked against the channel's exception: any keyword
  found in the text (case-insensitive, whole words) or any selected post type. A post can have
  several types at once (a photo with a link is both "Photos" and "Links").
* **Notification.** If it matches, the regular notification path is used as if the channel were not
  muted; the post is also marked as "unseen exception".
* **Chat list.** A channel with unseen exception posts shows an active unread counter and a bell icon
  next to it, like mentions and reactions.
* **Chat.** A bell button with a counter appears above the input panel; each tap scrolls to the next
  matching post and highlights the matched word; the counter goes down as posts are read.
* **Editor.** Opened from the post menu as a sheet: words from the post are offered as dashed chips,
  a tap adds them; typed words become chips too. Post types are grouped (Media, Other) with
  per-type checkmarks.

## Integration into Telegram-iOS

Base commit: `fb0e62ba8a147f0821da6aa63c09da7d79a10111` (TelegramMessenger/Telegram-iOS).

```sh
cd Telegram-iOS
git checkout fb0e62ba8a147f0821da6aa63c09da7d79a10111
cp -R /path/to/this-repo/submodules/ submodules/
git apply /path/to/this-repo/Integration/telegram-ios.patch
```

Then build as usual (`build-system/Make/Make.py` or the generated Xcode project).

## Offline demo

```sh
xcrun simctl launch <udid> <bundle-id> \
  --concepts-offline-demo \
  --concepts-demo-assets <path to Demo/Assets>
```

Keep the assets folder outside `~/Documents` (simulator file-access protection blocks it).
Optional flags: `--concepts-demo-data <name>` (separate database), `--concepts-demo-open-channel`,
`--concepts-demo-open-quickadd`, `--concepts-demo-open-exceptions`, `--concepts-demo-autopilot`
(the scripted run from the video).

## Notes and limits

* Exceptions are stored on the device only; a real implementation needs server-side filtering so
  that pushes for matching posts are delivered while the channel is muted.
* Notification matching is wired for the offline demo path (`conceptsOfflineDemoEnabled`).
* Bell stickers: Telegram animated emoji by @syrreel.
* Code comments are partly in Russian.
