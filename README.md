<div align="center">

# Campus Rhythm Mini

**A free macOS to-do sticker** — menu bar note, glass window, fold-to-circle.

Also called **Campus Resume Sticker**. In-app menu title: **Rhythm Note**. Part of [Campus Rhythm](https://github.com/jinghengxu74/campus-rhythm-app).

[![Download](https://img.shields.io/badge/Download-macOS%20arm64-111111?style=for-the-badge&logo=apple)](https://github.com/jinghengxu74/campus-rhythm-app/blob/main/assets/downloads/Campus-Rhythm-Mini-macOS-arm64-v0.9.37.zip)
[![Showcase](https://img.shields.io/badge/Product-showcase-5b57d9?style=for-the-badge)](https://github.com/jinghengxu74/campus-rhythm-app)
[![Stars](https://img.shields.io/github/stars/jinghengxu74/campus-rhythm-mini?style=social)](https://github.com/jinghengxu74/campus-rhythm-mini/stargazers)

⭐ **Star this repo** if you use the sticker — it helps other students discover it.

</div>

## Screenshot

![Completed tab with seven-day chart](https://raw.githubusercontent.com/jinghengxu74/campus-rhythm-app/main/assets/mac-campus-rhythm-mini-completed-2026-10-27.png)

## Download

Pre-built **Apple silicon** zip (unsigned, ad-hoc, macOS 13+):

**[Campus-Rhythm-Mini-macOS-arm64-v0.9.37.zip](https://github.com/jinghengxu74/campus-rhythm-app/raw/main/assets/downloads/Campus-Rhythm-Mini-macOS-arm64-v0.9.37.zip)**

See the [install guide](https://github.com/jinghengxu74/campus-rhythm-app/blob/main/docs/CAMPUS_RHYTHM_MINI.md) on the showcase repo.

## Build

```sh
zsh scripts/test.sh
zsh scripts/build.sh
open dist/Campus\ Rhythm\ Mini.app
```

## Features

- **To-do / Pending / Completed / Events** for the selected day
- Drag reorder, categories, undo, trash, optional **Rhythm** assistant
- **Completed** tab with a swipeable seven-day bar chart
- Fold to a **draggable circle**; pin, resize, multiple day windows
- Optional **Campus Rhythm account** sync with [web Daily notes](https://campus-rhythm-one.vercel.app/notes)

Local data: `~/Library/Application Support/CampusRhythmMini/` — never commit it.

## License

MIT — see [LICENSE](LICENSE). Campus Rhythm naming and artwork remain the maintainer's brand.
