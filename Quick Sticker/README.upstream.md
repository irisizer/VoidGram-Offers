My Telegram channel
https://t.me/artem_designich


# Quick Stickers

Telegram's iOS chat screen, rebuilt in plain UIKit — the original runs on
their AsyncDisplayKit fork, with nodes and hand-computed layout — plus one
focused interaction: **quick stickers on a long press**.

## Why

Sending a sticker should be as immediate as reacting with one: press, slide,
release.

Here you press and hold the sticker button, four local demo stickers fan out of
it, you slide onto one and let go. The selected sticker flies directly into a
new outgoing message. Release anywhere else and everything folds back.

## How

No dependencies, UIKit, iOS 16+.

The screen is transcribed from [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) —
bubble images, the gradient wallpaper kernel, glass header and composer,
CoreText bubble widths — rather than eyeballed, but rebuilt on `UITableView`
and Auto Layout instead of their `ListView` and `ASDisplayNode`.

The fan is the interesting part. One spring per card would fly it in a straight
line, so each card runs **two springs — one on `position.x`, one on
`position.y`** — with different stiffness and damping. A fast bouncy Y plus a
slower smooth X bends the path into an arc while both axes keep real spring
physics, which a keyframed curve throws away. Cancelling swaps the two axes'
parameters and the card leaves along the path it arrived on. Numbers live in
`FanTuning.swift`, the gesture in `QuickStickerOverlayView.swift`.

## Run

Open `QuickAttach.xcodeproj`, pick an iPhone simulator, Run, and hold the
sticker icon in the composer. The four bundled stickers work identically on a
simulator and a real device; the app asks for no media permissions.

---

Graphics and drawing code come from Telegram-iOS (GPL-2.0). A UX prototype, not
a client.
