# Agent Instructions — evernote-utils

## Overview

macOS utilities for Evernote backup and read-only note protection. Works via Evernote API — no local app required.

## Tools

- **`backup.sh`** — Automated backup with hardened credential storage
- **`evernote-lock.py`** — Make notes read-only via `contentClass`

## Security

- Token lives in macOS Keychain, not on disk.
- Short-lived tokens (1-month OAuth).
- Runtime injection — never written to disk outside Keychain.

## Operations

```bash
./backup.sh                    # Full backup + optional scheduling setup
./evernote-lock.py lock        # Lock notes tagged "ReadOnly"
./evernote-lock.py unlock      # Unlock notes locked by this tool
```

## Rules

- Never commit Evernote tokens.
- `backup.sh` is idempotent — safe to re-run.
- `evernote-lock.py` only modifies `contentClass` — never touches note content.
