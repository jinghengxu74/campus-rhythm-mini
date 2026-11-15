# v0.9.61 — Completed chart dates and sync protection

## Changes since v0.9.59

- Reserve independent space for chart counts, bars, weekdays and month/day labels. Show zero counts and retain the zero-day baseline. Improve label contrast in both appearances.
- Date labels explicitly follow the Mac system calendar/time zone; stored completion timestamps are unchanged.
- Calendar-only cloud updates preserve a newer remote notebook when the local notebook has not changed. Concurrent notebook edits still require conflict handling.
- Add opt-in, read-only sharing of selected Apple Calendar snapshots to the Campus account. This is off by default and requires an authorized, running Mac. Timed snapshot fields currently use the Campus Hong Kong time convention; travel/time-zone acceptance remains pending.
- Correct calendar permission copy and session-storage documentation. Mark session-file access as MainActor-isolated, removing the previous build warning.

## Validation on 2026-11-16

- 71 Swift tests passed, including UTC+8 midnight grouping, Apple snapshot serialization/merge, and calendar-only notebook preservation.
- Release build and ad-hoc signature verification passed. ZIP inspected: app executable, icon, plist and code signature only; no account data or screenshots.
- git diff --check passed. No new compiler warnings/errors in this run.
- This is source review and automated validation, not independent malware certification. New chart layout visual acceptance, real iPhone/Mac bidirectional acceptance and second-account isolation remain pending.

## Installation

Apple silicon, macOS 13+. Early beta, ad-hoc signed and not notarized. Existing users should quit before replacing the application. Keep the existing app-support data; no data reset is required. Update notices open the release page; installation remains manual.
