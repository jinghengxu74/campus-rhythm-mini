# Rhythm Note · paper revision 0.5

## Direction

The user's original sticky-note reference: a quiet, light-grey sheet with a centered date, monospaced text, collapsible categories and square checkboxes. Readability takes priority over optical effects.

## Surface

- Fully opaque warm grey: sRGB (0.953, 0.949, 0.941), alpha 1.
- 16 pt rounded corners; thin neutral border and native window shadow.
- No NSGlassEffectView, NSVisualEffectView, backdrop sampling or idle alpha animation.
- The window itself is clear only outside the rounded paper boundary.
- Native controls and text use a light appearance for consistent contrast.

## Type and controls

- Task text defaults to system monospaced 12 pt; categories use 12 pt semibold monospaced.
- Date and status labels use 10 pt monospaced.
- Optional task-only choices: system proportional 13 pt, system serif 14 pt, or locally installed STKaiti 15 pt.
- Four statuses share a faint grey tray; the selected tab is near white with dark text.
- Square completion boxes, a compact rectangular input row and a subdued pin match the reference.

## Behaviour

- A note stays at full opacity even when idle or unpinned.
- Pin controls window level: floating when pinned, normal when unpinned.
- Menu-bar minimization, separate circle mode, user-defined categories, editing, status changes, undo, free movement, resizing and frame restoration are retained.
- Existing note data and the four-state model are unchanged.

The discarded glass experiment is archived separately and is not compiled.

## Interaction revision 0.6

- Completion label has an explicit rectangular 24 pt hit area, including the empty centre of the square. The hosting view accepts first-mouse clicks.
- A just-completed task stays checked and crossed out in its original list until a tab change. This transient display state does not change its persisted Completed status.
- Categories and tasks have text/handle drag sources, validated in-process drop targets and insertion indicators. The data changes only on a successful drop; there is no persistent reorder on hover.
- Category drops move the entire section; task drops support before/after insertion and cross-category moves, retaining IDs and status.
- Context-menu Move to top and header Undo are alternative controls.
- Manual ordering is the user's local priority order. It does not fabricate deadlines, reschedule work or claim to update the separate online recommendation engine.

## Interaction and appearance revision 0.7

This revision supersedes the 0.5 opaque-only surface and the 0.6 immediate-completion preview.

- A checkbox now toggles a persistent `isChecked` draft flag on an open task. It cannot create a completed record. The inline Mark complete action is the explicit archive step.
- Confirmation writes a UTC ISO 8601 `completedAt` timestamp at second precision. Daily groups use the current local calendar/time zone; titles and due dates are irrelevant. Missing legacy timestamps remain unknown and appear in a separate last section.
- Reopening restores the prior open status and clears the completion timestamp and draft flag. Duplicate confirmation does not change the original time. Undo restores the entire prior document.
- Only To-do, Pending and Completed appear in tabs, native filter menus and status actions. Cancelled remains a decodable stored status for backward compatibility, without deleting legacy records.
- The minus control folds into a 32 pt circle. A native first-click view distinguishes a >3 pt drag from a click; drag moves the circle and saves its position, while a click expands the note nearby. There is no hover timer or hover-open path.
- 20 pt note corners, a 0.5 pt light rim, native shadow and a behind-window popover material soften the paper. A separate warm paper tint defaults to 92% opacity, adjustable 70–100%. Text remains opaque; `NSWindow.alphaValue` stays 1. The circle uses a 96% tint for a readable count.
- Window movement, resizing, pinning and local task/category drag ordering remain available. Completed is a dated archive, so its rows do not advertise priority drag handles.

## Typography revision 0.7.1

- Typeface replaces Task typeface and applies one selected family across all app text roles, including native menus and the folded circle.
- A shared size/weight factory preserves hierarchy. SF Symbols retain their symbol-specific styling.
- Native menus built by SwiftUI are styled on the app's native menu-tracking notification; status-menu submenus use the same family.
- The existing notePaperTypeface preference is retained. STKaiti uses the installed local font; no font installation or data migration is required.

## Glass and fold-control revision 0.8

- Replaces the popover blur plus 92% paper layer with NSGlassEffectView on macOS 26+. The hosting view and tint sit inside the documented contentView, not arbitrary glass subviews.
- Glass uses the system clear style with a 48% paper tint; Frosted uses the system regular style. The paper tint is adjustable 15–100% without changing window/text opacity. A separate appearance key avoids inheriting the previous appearance's near-opaque 92% setting.
- macOS 13–25 fall back to a HUD visual effect material; no native Liquid Glass is claimed there.
- Softer 24 pt note corners and a rounded translucent capture tray; no extra stacked glass passes for every row.
- The minus symbol is replaced with a 28 pt circular hit target and smallcircle.filled.circle symbol. The action remains Fold into circle, with a tooltip and accessibility label.
- The 32 pt folded circle remains draggable and click-only. Its count inherits the selected typeface.
- API reference: https://developer.apple.com/documentation/appkit/nsglasseffectview

## Daily desktop revision 0.9

- Light and dark surfaces, with white text on the dark default. Custom paper/ink colors and task-specific colors remain optional.
- Rounded Glass, Compact and Minimal edge previews; Minimal uses a material card without a glass rim or native window shadow. Native content is sized before attachment when replacing a material, preventing a size jump.
- Date navigation and a date picker replace the inert header label. A small grip preserves free movement. Independent windows share a repository while selecting different days/tabs.
- Appearance profiles are saved by day, so two differently styled notes can reopen consistently.
- Pending is global and undated; To-do filters by the selected day. Completed retains actual confirmation-day grouping. Task highlight is a whole-task marker, not a rich-text selection editor.
- Events shows the selected day’s canonical account calendar. Account connection stays behind the menu; no login is required for local notes.
