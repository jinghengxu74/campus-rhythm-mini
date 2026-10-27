# Campus Rhythm Mini · macOS to-do sticker

**Campus Rhythm Mini** (*Campus Resume Sticker*; menu title **Rhythm Note**) is a small daily note that lives in your menu bar or a draggable circle. Keep today’s list beside tomorrow’s, capture an idea without a date, and confirm what you finished.

## Daily notes

- **To-do** starts on the selected calendar day and carries forward until Mark complete; a tick alone is still an unconfirmed draft. The same record keeps its original day, order, colors and ID. Future tasks stay hidden before their start day. Hover the date to reveal navigation, click it for a date picker, or use **… → Open next day in new window**. Windows share the same saved document while keeping their own date and tab. A Today window follows the local day at midnight; deliberately selected past/future days stay selected.
- **Pending** is an undated inbox: ideas you have in mind, without a made-up due date. Right-click a task to move it to today, tomorrow or the selected day.
- **Completed** groups confirmed completions by their actual local completion day. Tick first to cross out a task, then choose **Mark complete**. Reopening restores its prior open status. Older records without a timestamp remain explicitly undated.
- **Events** reads your Campus Rhythm calendar for the selected day after account connection. It displays event times in the Mac’s current time zone, retaining all-day dates.
- Custom categories, folding, task/category priority ordering, editing and undo remain available. Day selection is the start of a work intention, not an assessment deadline or a calendar booking.

## Appearance and windows

**… → Appearance** provides Light / Dark, **Rounded Glass / Compact / Minimal** edges, Glass / Frosted finishes, paper opacity, paper color and text color. Right-click a task for its own text color or Yellow / Mint / Lavender / Rose / Blue highlight. Appearance settings are kept by note date; font selection applies across the note, controls, menus and folded-circle count.

The circle-with-dot control folds the note into a 32 pt circle. Drag it anywhere; only a click unfolds it. The circle tooltip identifies its date. Drag the header grip to move a full note, and the bottom-right grip to resize it. Pinning controls whether other windows can cover it. Extra windows can be closed without deleting their tasks; the menu bar keeps the app available.

Native Liquid Glass is used on macOS 26+. Earlier macOS versions use a native visual-effect fallback. Minimal removes the glass rim and native window shadow. Typography includes system monospaced, SF Pro, New York and locally installed STKaiti; no font is downloaded.

## Connect your account

Open **… → Connect account**. Connect in the browser with the same Campus Rhythm Google/email account, or use your account’s email/password. Browser handoff is encrypted for a one-time native key; access/refresh tokens never appear as plaintext in a callback URL. The native session is kept in Keychain.

Account notes and local notes remain separate. **Import local notes…** previews the scope and adds local categories, dates, colors and completion history to the account without duplicating IDs. Disconnect returns to the original local note. Account caches and pending edits are isolated by user ID.

[Web Daily notes](https://campus-rhythm-one.vercel.app/notes) uses the same account notebook. Calendar events come from the existing plan. Sync polls every 20 seconds and saves with revision checks; it is not a realtime subscription. Concurrent note changes stop for an explicit conflict choice, with a local backup of the other version. Offline edits remain on this Mac. The Mac client does not request Health data or change Health permissions.

Daily notes are lightweight work intentions. The existing planner’s deadline tasks remain a distinct entity; creating an undated idea does not fabricate a deadline or a scheduled event.

## Build

Requires Xcode Command Line Tools, macOS 13+, and Apple silicon for the supplied build.

```sh
zsh scripts/test.sh
zsh scripts/build.sh
```

Open `dist/Campus Rhythm Mini.app` or unzip `dist/Rhythm-Note-macOS-arm64.zip`. Local builds use ad-hoc signing, not public notarization. The legacy bundle/executable name is retained to preserve existing local data.

Data lives under `~/Library/Application Support/CampusRhythmMini/`. Legacy open tasks receive the day of their first daily-note migration; existing IDs, titles, ordering and completion timestamps are retained. Pending has no date. Corrupt files are preserved and editing pauses rather than replacing the original. Never commit this application-support folder, sessions, personal screenshots or `.env` files.

## Implementation and acceptance

- Native domain, date isolation, legacy preservation, metadata persistence, calendar conversion and cloud-plan preservation have automated coverage.
- WebCrypto → native CryptoKit handoff interoperability, replay rejection, expiry and tampering are covered by a test-only fixture.
- The web source includes Notes, desktop connection, serializer support and a backward-compatible database migration. Earlier clients cannot drop the notebook when saving their plan.
- Live-tested on 2026-10-22: owner browser sign-in, explicit import of five local notes, matching account calendar, Mac-to-web creation, web-to-Mac completion-day archive, web-to-Mac next-day creation/highlight/Pending and test cleanup after website reload, plus account and original-note restoration after process restart. iPhone acceptance remains pending.
