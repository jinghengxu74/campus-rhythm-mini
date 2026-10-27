# Rhythm Note account integration · 0.9

The native Mac app and Expo `/notes` route share a version-1 notebook at `plan.notebook` in the existing authenticated `rhythm_snapshots` plan. It holds categories and small dated/undated note tasks, including stable UUIDs, manual order, checked drafts, explicit confirmation timestamps, text colors and highlights.

These records are daily work intentions, distinct from the planner’s assessment/deadline Task entity. No deadline or duration is invented to make an undated thought fit the scheduling model. Pending is undated. Linking a note to an existing deadline or scheduling it as an event remains a separate future action.

The native Events tab reads the canonical `plan.events`. Stored campus-reference times are converted to real Date instants using Asia/Hong_Kong; display follows the Mac’s current time zone. All-day dates stay date-only. Events are read-only in the small note.

## Authentication

The fixed product origin serves `/desktop-connect`, which uses the existing account entry and OAuth callback. The user explicitly connects the displayed account. Browser WebCrypto encrypts the session with an ephemeral P-256 ECDH key, HKDF-SHA256 and AES-256-GCM for the native one-time key. A random state, ten-minute lifetime and consumed-key rejection bind the return. The custom callback contains only public key material and ciphertext. Native code verifies the account through the normal user endpoint before loading its plan. Password sign-in is also available; credentials are never written to note files. Sessions are stored in Keychain.

No browser cookie or local-storage extraction is used by the agent or native application. The website’s own authenticated client performs its normal account operation on the user’s Connect action. No Supabase redirect allowlist, provider secrets or site protection need to be weakened.

## Saving and recovery

- Native requests select only revision and plan, not Health.
- Fetch the latest plan before saving; preserve every unrelated field, including unknown JSON fields and exact supported numeric values. Replace only `notebook`.
- Save through authenticated `save_rhythm` with the expected revision and `health_mode: keep`.
- If the note changed both locally and remotely, preserve local edits and show a conflict. Explicit Keep Mac / Use account actions retain a local backup of the other notebook. Revision checks remain active during resolution.
- Persist the last synchronized base beside the account-specific cache. Resume an unsent local edit on relaunch, rather than replacing it with the remote note.
- Stop stale callbacks on sign-out/account changes. Local mode and every account have separate files; disconnect returns to the local file.
- The database update preserves an existing notebook when older web/iOS clients omit that field. New clients validate/serialize it explicitly.

The Expo Notes route and serializers are shared source for web and iOS. This does not establish that an older installed iOS binary has the new route; installing/rebuilding and device acceptance remain separate.

## Verification boundaries

Native domain tests and web/database tests cover the contract. The desktop encryption fixture is produced by the actual WebCrypto sender and decrypted by the production native receiver in tests. Production migration verification confirms RLS remains on and anonymous `save_rhythm` execution remains off.

An implementation/build is not evidence of the user’s successful real-account sign-in or cross-device acceptance. Record Mac sign-in → existing calendar read → note create/check/confirm → web refresh → web change → Mac poll/relaunch, plus import idempotence and cleanup, when the user completes the normal sign-in flow.
