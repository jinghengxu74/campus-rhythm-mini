# Rhythm Note 0.7 validation · 2026-10-22

## Implemented and locally UI-tested

- Top-right minus folds into the 32 pt circle. AX exposes Fold into circle.
- Native circle drag stayed folded. Persisted origin changed from {1364, 824} to {1284, 774}, matching the drag delta. Clicking subsequently opened the note. There is no hover-open timer/path in the source.
- Relaunch restored circle mode and the exact saved origin; clicking opened the note near it.
- Checkbox changed an open task to Checked, awaiting Mark complete. It remained To-do in saved JSON: 2 open tasks, 1 checked draft, 1 pre-existing completed task, and no new completion timestamp.
- Clicking Mark complete removed the test task from To-do. Completed displayed Today · Thu, Oct 22, 2026, a one-task done list, category and actual confirmation time. The original undated Memo remained separately under Earlier · date not recorded.
- Header Undo restored the pre-confirmation checked state; unticking restored the original task. A normalized JSON comparison (legacy missing isChecked treated as false) confirmed all 3 tasks, categories, order and prior statuses exactly match the fresh pre-test backup. No test task was left complete.
- Only To-do, Pending and Completed tabs are exposed. Cancelled records remain supported in storage; no data deletion/mass migration was performed.
- Appearance popover opened; native slider decremented from 92% to 89% and down to the 70% minimum. Reset restored 92%. Defaults retained 0.92 after relaunch. Background tint changes independently of opaque text/controls.
- Existing task-typeface choices, pinning and manual ordering remain implemented. Native drag ordering/resize acceptance from 0.6 is not newly claimed as re-tested in this revision.

## Automated / packaging checks

- 24 NoteCore tests passed (0 failures), including new two-step completion, checked-state persistence, confirmation timestamp persistence, repeated-confirm idempotence, pending restoration, local midnight grouping in Asia/Hong_Kong, undated legacy records, retained cancellations and checked task reordering.
- Production build succeeded. Clean staging app passed ad-hoc signature verification.
- Version 0.7.0 / build 7 ZIP executable SHA-256 matches the staging executable used for UI verification.
- ARM64 ZIP is about 1.6 MB. This is a local ad-hoc signed build, not a notarized public release.

## Evidence

- v0.7-checked-awaiting-confirmation.png: temporary checked test state.
- v0.7-daily-completed-test.png: temporary completion test, subsequently undone.
- v0.7-circle-after-drag.png: circle still folded after movement.
- rhythm-note-v0.7.png: final restored task state.

No login, web/iOS deployment or cloud synchronization was implemented or claimed. Completed is the local saved view. Legacy completion dates cannot be reconstructed from task titles; existing undated records remain explicitly undated.
