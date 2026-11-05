# Multi-Message Reply

**Reply to several messages at once — as one deck of quotes.**

## Demo

<a href="3.mp4"><img src="3.webp" width="600" alt="Multi-Message Reply demo"></a>

<sub>Inline preview is silent — <a href="3.mp4">3.mp4</a> plays the full video with sound.</sub>

---

## The idea

Select 2–5 messages and reply to them all at once. Quotes appear as a swipeable card deck, letting you flip between messages, remove individual quotes, and jump back to the originals.

## How it works

- **Selection bar.** With 2–5 messages selected, a Reply button appears next to Share.
- **Composer.** One quote stacks the messages as a deck with a `1/3` counter. Tap to flip through the cards, long press to list all of them and remove any. The close button removes only the visible card. A regular Reply is unchanged and replaces the deck.
- **Sent message.** The cards peek out from behind the quote and the counter flips them. A tap expands the list, a tap on a card opens that message. Cards that reply to a photo or video show a small preview.

## Notes

Pure UIKit, no new dependencies — 12 files, +1591 −34, one new file: `MultiReplyStore.swift`. Answers [bugs.telegram.org/c/1216](https://bugs.telegram.org/c/1216), open since January 2021. Built and tested on a real iPhone (debug and release).

> The upstream README is kept as `README.upstream.md` (build/setup instructions).

## Source

Ported from [`niklavrukhin-cell/telegram-multi-reply`](https://github.com/niklavrukhin-cell/telegram-multi-reply) (branch `main`). All rights to the original code stay with its authors.
