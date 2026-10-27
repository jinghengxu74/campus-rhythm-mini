<div align="center">

# Campus Rhythm To-Do Notes

**Local-first macOS desktop sticker** — To-do, Pending, **Done chart**, Events. Fold to a circle on your desk.

Part of [Campus Rhythm](https://github.com/jinghengxu74/campus-rhythm-app) · MIT open source

[![Download latest](https://img.shields.io/badge/Download-latest%20release-111111?style=for-the-badge&logo=apple)](https://github.com/jinghengxu74/campus-rhythm-mini/releases/latest)
[![Showcase](https://img.shields.io/badge/Docs-showcase-5b57d9?style=for-the-badge)](https://github.com/jinghengxu74/campus-rhythm-app/blob/main/docs/CAMPUS_RHYTHM_TODO_NOTES.md)
</div>

## Why

Heavy to-do users often have **open lists** but weak **done history**. This app is a glass **sticker** on your Mac: fast capture, real **Completed** archive, seven-day bar chart, optional calendar events — **no cloud unless you connect an account**.

## Screenshots

See the [showcase gallery](https://github.com/jinghengxu74/campus-rhythm-app#macos--campus-rhythm-to-do-notes-desktop-sticker).

## Download

[Latest GitHub Release](https://github.com/jinghengxu74/campus-rhythm-mini/releases/latest) (Apple silicon, macOS 13+). Or build below.

In the app: **… → Check for updates…**

## Build

```sh
zsh scripts/test.sh
zsh scripts/build.sh
open dist/Campus\ Rhythm\ Mini.app
```

Bundle filename stays `Campus Rhythm Mini.app` so existing local data paths keep working; the public product name is **To-Do Notes**.

## Privacy

**Default: everything stays on your Mac** (`~/Library/Application Support/CampusRhythmMini/`).  
Details: [PRIVACY_TODO_NOTES.md](https://github.com/jinghengxu74/campus-rhythm-app/blob/main/docs/PRIVACY_TODO_NOTES.md) on the showcase repo.

## Fork

See [FORK.md](https://github.com/jinghengxu74/campus-rhythm-app/blob/main/docs/FORK.md).

## License

MIT — [LICENSE](LICENSE)
