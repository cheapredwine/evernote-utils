# evernote-utils

Back up all Evernote notebooks with hardened credential storage.

## What it does

`backup.sh` is a single self-configuring script. Run it and it handles
everything: installation, authentication, syncing, exporting, and
archiving. There is no separate setup step.

On first run it will:

1. Install `evernote-backup` and `evernote2md` via Homebrew if not present
2. Initialize the local database and open OAuth in your browser
3. Move the auth token from the database into macOS Keychain
4. Sync all notebooks, export as `.enex`, convert to Markdown, archive
5. Offer to set up weekly automated backups

On subsequent runs it pulls the token from Keychain and gets to work.
If the token expires, it re-authenticates automatically. If the
database is corrupted, it rebuilds. If running headless (via the
scheduler) and something needs your attention, you get a macOS
notification.

Each backup archive contains two copies of your notes:

- **`.enex` files** — Evernote's native XML format, for restoring into
  Evernote or any compatible app
- **Markdown + attachments** — plain text files readable by anything,
  forever. If Evernote disappears tomorrow, you still have your notes
  in a universal format

## Usage

```bash
chmod +x backup.sh
./backup.sh
```

That's it. First run takes longer (auth + full sync). After that
it's incremental.

### Flags

| Flag | What it does |
|------|-------------|
| `FORCE_REAUTH=1 ./backup.sh` | Force token refresh |
| `INSTALL_SCHEDULE=1 ./backup.sh` | Enable weekly automated backups |
| `UNINSTALL_SCHEDULE=1 ./backup.sh` | Remove automated backups |

### Backup destination

Auto-detected in order:

1. `~/Library/CloudStorage/GoogleDrive-<email>/My Drive/EvernoteBackups/`
2. `/Volumes/GoogleDrive/My Drive/EvernoteBackups/`
3. `~/Documents/EvernoteBackups/`

Override: `EVERNOTE_BACKUP_DEST=/your/path ./backup.sh`

### Database location

Default: `~/.evernote-backup/en_backup.db`

Override: `EVERNOTE_BACKUP_DB=/your/path/en_backup.db ./backup.sh`

## Scheduling

On first run, the script asks if you want weekly automated backups
(Sundays at 10:00 AM via launchd). If you skip it:

```bash
INSTALL_SCHEDULE=1 ./backup.sh
```

To remove:

```bash
UNINSTALL_SCHEDULE=1 ./backup.sh
```

Logs are written to `~/.evernote-backup/backup.log`.

If the token expires while on the automated schedule, the script
sends a macOS notification and exits. Run `./backup.sh` manually
once to complete re-authentication.

## Note locking

`evernote-lock.py` protects notes from accidental edits by setting
the `contentClass` attribute, which makes them read-only in every
Evernote client.

### How it works

1. In Evernote, tag any notes you want to protect with "ReadOnly"
   (or any tag you choose)
2. Run `./evernote-lock.py lock`
3. Those notes are now uneditable across all devices

The lock is enforced server-side by Evernote — it's not a local hack.

### Commands

```bash
./evernote-lock.py lock                    # Lock all notes tagged "ReadOnly"
./evernote-lock.py lock --tag DoNotEdit    # Use a different tag
./evernote-lock.py lock --note-guid GUID   # Lock a specific note
./evernote-lock.py unlock                  # Unlock all notes locked by this tool
./evernote-lock.py unlock --note-guid GUID # Unlock a specific note
./evernote-lock.py status                  # List currently locked notes
```

### Authentication

Uses the same Keychain token as `backup.sh`. If you haven't run
`backup.sh` yet, pass a token directly:

```bash
./evernote-lock.py --token "S=s1:U=..." lock
```

### Important

Unlike `backup.sh`, this tool **writes to your Evernote account**
(it has to, to set the read-only attribute). It only modifies the
`contentClass` field — it never touches note content, attachments,
or anything else. It also won't unlock notes that were locked by
other applications.

## Security model

The Evernote API has no read-only token scope. Any token that can
download notes can also modify them. This script reduces exposure:

- **Token lives in macOS Keychain, not on disk.** After authentication
  the token is extracted from the SQLite database and scrubbed. An
  attacker who exfiltrates the `.db` file gets cached notes and sync
  state, but no credential.

- **Short-lived tokens.** During OAuth, choose 1-month duration. The
  script warns 7 days before expiration and re-authenticates
  automatically when expired.

- **Runtime injection.** The token is passed via `--token` on each
  run and never written to disk outside of Keychain.

- **Keychain syncs via iCloud Keychain** across Apple devices.

### Threat model boundaries

This protects against credential exposure from file exfiltration
(cloud sync, stolen disk image, backup leak). It does not protect
against an attacker with live access to your Mac — if they can run
`security find-generic-password`, they have the token.

Evernote blocks permanent deletion (`expunge`) for third-party tokens.
A compromised token could trash or modify notes, but not permanently
destroy them.

## Prerequisites

- macOS
- Python 3.9+ (or Homebrew, which handles it)
- Both `evernote-backup` and `evernote2md` are auto-installed via
  Homebrew on first run

## Legacy

The original `backup.applescript` is preserved for reference. It
requires Evernote v7.x or earlier and does not work with Evernote v10+.
