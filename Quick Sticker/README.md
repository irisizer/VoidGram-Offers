# Quick Sticker

**Press, slide, release — a sticker without opening the panel.**

## Demo

<!--
  Inline playback on GitHub needs an uploaded asset URL — a committed .mp4 only gets a link.
  To embed the player: edit this file on github.com, drag 4.mp4 into the editor and GitHub
  inserts the player line (https://github.com/user-attachments/assets/…) on its own line.
-->

**▶ [Watch the demo](4.mp4)**

---

## The idea

Reply with a sticker as quickly as you react to a message. Just hold the sticker icon, slide to your favorite sticker, and release to send. No need to open the sticker panel.

## How it works

- Press and hold the sticker button in the composer.
- Four stickers fan out of it while your finger is still down.
- Slide onto one and let go — it flies straight into a new outgoing message.
- Release anywhere else and everything folds back, nothing is sent.

## Notes

UIKit, iOS 16+, no dependencies. The chat screen is transcribed from Telegram-iOS (bubble images, gradient wallpaper kernel, glass header and composer) but rebuilt on `UITableView` + Auto Layout. Each fan card runs two springs — one on `position.x`, one on `position.y` — so the path bends into an arc while both axes keep real spring physics; tuning in `FanTuning.swift`, gesture in `QuickStickerOverlayView.swift`. Open `QuickAttach.xcodeproj`, run, hold the sticker icon. A UX prototype, not a client.

> The upstream README is kept as `README.upstream.md` (build/setup instructions).

## Source

Ported from [`artem-suslov/tg-attach-stickers`](https://github.com/artem-suslov/tg-attach-stickers) (branch `main`). All rights to the original code stay with its authors.
