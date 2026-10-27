# Rhythm Note 0.6 validation

- 18 NoteCore tests passed, including original-file migration, completion preview, category ordering, both task-order directions, cross-category movement, invalid/self drops and saved-order recovery.
- Native UI: clicked the empty centre of the checkbox by coordinates; AX reported Completed and the row remained checked and struck through. Header Undo restored the exact saved document.
- Native UI: dragged study above work, then undid the section move.
- Native UI: dragged a task from study above a work task; dragged it below the other task within work; moved it back to study.
- JSON comparison after all verification: exactly equal to the saved pre-test note (3 categories, 2 tasks). No actual completion or order change was left behind.
- ZIP 0.6.0 executable matches the UI-tested executable.
- Proof images: v0.6-checkbox-test.png, v0.6-section-order-test.png, v0.6-task-order-test.png, rhythm-note-v0.6.png. Test-state screenshots are historical, not the final task state.
- Reference: public to-do ball page read, linked Instagram video sampled. No form was submitted.
- Cross-platform integration design is in docs/WEB_IOS_INTEGRATION.md; not connected, deployed or live-tested.
