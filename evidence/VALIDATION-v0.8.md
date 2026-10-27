# Rhythm Note 0.8 local validation · 2026-10-22

- Release build and clean staging ad-hoc signature checks passed. Local OS is macOS 27.0.1, so the NSGlassEffectView branch is available. Older-OS HUD fallback was compiled but not run on older hardware.
- Native UI: the new smallcircle.filled.circle button exposes Fold into circle and successfully opens the separate 32 pt circle window. Dragging leaves it folded; a subsequent click unfolds the note. Verified again after the final material update.
- Appearance: verified Glass/Frosted selected states switch; Paper opacity control reached 15%; Balanced glass selected Glass and restored 48%. The slider changes only the tint layer, while window alpha remains 1.
- Native regular/clear materials were inspected with a temporary non-user gradient backdrop. This was a visual inspection, not a calibrated transparency measurement. The temporary background app was terminated after inspection.
- Current saved settings are Glass and 0.48 paper opacity. Task file bytes equal the fresh pre-test backup exactly. No task state or ordering was modified.
- Domain logic did not change, so the earlier 24 domain tests were not re-run for this appearance-only revision. No mirrored appearance unit tests were added.
- Version 0.8.0 / build 9 ZIP executable matches the final UI-tested staging executable.
- Evidence: rhythm-note-v0.8.png, v0.8-folded-circle.png.
- Still local-only and ad-hoc signed. No new web/iOS sync, deployment or notarization is claimed.
