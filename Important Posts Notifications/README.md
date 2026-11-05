# Important Posts Notifications

**A muted channel stays muted — except for the posts that matter.**

## Demo

<a href="2.mp4"><img src="2.webp" width="600" alt="Important Posts Notifications demo"></a>

<sub>Inline preview is silent — <a href="2.mp4">2.mp4</a> plays the full video with sound.</sub>

---

## The idea

Get notified about posts that matter — by keyword or post type. Everything else stays muted

## How it works

- Hold a post in a muted channel → **Unmute Similar**.
- The editor opens with words from that post as suggestions; add your own keywords.
- Pick the post types that should count: photos, GIFs, polls, giveaways and so on.
- Matching posts get a bell badge in the chat list.
- A bell button in the chat jumps through the matched posts one by one.
- Everything that does not match stays muted, exactly as before.

## Notes

Telegram-iOS concept — UIKit / AsyncDisplayKit on top of the official sources. New files sit under `submodules/` at the same paths as in Telegram-iOS; changes to existing files are in `Integration/telegram-ios.patch` (`git apply`). `Demo/Assets/` holds avatars, post images and stickers for the offline demo.

> The upstream README is kept as `README.upstream.md` (build/setup instructions).

## Source

Ported from [`riveauxmia/telegram-unmute-similar`](https://github.com/riveauxmia/telegram-unmute-similar) (branch `main`). All rights to the original code stay with its authors.
