# Rhythm Note 0.7.1 validation

- Release build succeeded; ad-hoc signature verified.
- Native UI: selected Handwritten · STKaiti from the renamed Typeface submenu. Date, all three tabs, category headings, task labels, composer placeholder/category label, completed header/count/category metadata and folded circle count visibly changed together.
- Native options menu also visibly adopted STKaiti. Original monospaced menu styling was checked before switching.
- Font selection saved as kaiti under the existing preference key.
- Task JSON bytes match the fresh pre-verification backup exactly. No task mutation was needed for this appearance change.
- New unit tests were not added for this reversible typography change. Prior domain tests were not re-run because the domain was unchanged.
- ZIP 0.7.1/build 8 executable matches the UI-tested clean staging executable.
- Evidence: rhythm-note-v0.7.1.png and v0.7.1-global-typeface-menu.png.
