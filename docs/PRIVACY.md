# Rhythm Note privacy

Local notes are stored in this Mac’s app-support directory. Signing in and explicitly importing local notes are separate actions. Account notebook changes are sent to the configured Campus Rhythm account service. Do not share the app-support directory.

The current ad-hoc build stores session tokens in an owner-only local file (0600), not encrypted at rest by the app. The app may migrate an existing Keychain session; new builds do not promise Keychain-backed storage. A process running as your macOS user may be able to read this file.

Apple Calendar requires OS authorization. Sharing selected calendars to the Campus account is separately opt-in and off by default. When enabled, a read-only snapshot updates while this Mac is open and authorized. Turning sharing off stops future uploads; it does not promise deletion of previously uploaded snapshots. The web cannot write back to Apple Calendar.

The Mac client does not request Health access. Update checks contact the public GitHub release API; the current updater opens a release page rather than automatically replacing the app.
