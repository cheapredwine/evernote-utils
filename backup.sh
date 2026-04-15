#!/bin/bash
# backup.sh — Self-configuring Evernote backup with Keychain token storage
# https://github.com/cheapredwine/evernote-utils
#
# Just run it. Handles setup, auth, sync, export, archiving, and scheduling.
#
# Environment overrides:
#   EVERNOTE_BACKUP_DB    — path to database (default: ~/.evernote-backup/en_backup.db)
#   EVERNOTE_BACKUP_DEST  — archive destination (default: Google Drive or ~/Documents)
#   FORCE_REAUTH=1        — force token refresh
#   INSTALL_SCHEDULE=1    — enable weekly automated backups
#   UNINSTALL_SCHEDULE=1  — remove automated backups

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────

KEYCHAIN_SERVICE="com.cheapredwine.evernote-backup"
KEYCHAIN_ACCOUNT="evernote-token"
DB="${EVERNOTE_BACKUP_DB:-$HOME/.evernote-backup/en_backup.db}"
DB_DIR="$(dirname "$DB")"
WARN_DAYS=7

PLIST_LABEL="com.cheapredwine.evernote-backup"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

DATE=$(date +'%Y%m%d')
EXPORT_DIR="$HOME/Desktop/Evernote-$DATE"
MD_DIR="$HOME/Desktop/Evernote-Markdown-$DATE"
ARCHIVE_NAME="evernote-$DATE.tar.gz"

# Cleanup temp dirs on exit (even on failure)
cleanup() {
  [[ -d "$EXPORT_DIR" ]] && rm -rf "$EXPORT_DIR"
  [[ -d "$MD_DIR" ]] && rm -rf "$MD_DIR"
}
trap cleanup EXIT

# ── Helpers ─────────────────────────────────────────────────────

log()    { echo ":: $*"; }
warn()   { echo "⚠  $*"; }
err()    { echo "!! $*" >&2; }
die()    { err "$*"; exit 1; }

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true
}

needs_interactive() {
  if [[ ! -t 0 ]]; then
    notify "Evernote Backup" "$1"
    die "$1 Run ./backup.sh manually."
  fi
}

token_expiry_epoch() {
  local hex
  hex=$(echo "$1" | grep -oE 'E=[0-9a-f]+' | cut -d= -f2)
  [[ -n "$hex" ]] && echo $(( 16#$hex / 1000 )) || echo "0"
}

token_days_left() {
  echo $(( ($1 - $(date +%s)) / 86400 ))
}

keychain_get() {
  security find-generic-password \
    -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || true
}

keychain_set() {
  security add-generic-password \
    -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w "$1" -U
}

db_get_token() {
  [[ -f "$DB" ]] && sqlite3 "$DB" \
    "SELECT value FROM config WHERE name='auth_token';" 2>/dev/null || true
}

db_scrub_token() {
  [[ -f "$DB" ]] && sqlite3 "$DB" \
    "DELETE FROM config WHERE name='auth_token';" 2>/dev/null || true
}

db_is_valid() {
  [[ -f "$DB" ]] || return 1
  [[ "$(sqlite3 "$DB" "PRAGMA integrity_check;" 2>/dev/null)" == "ok" ]]
}

run_init() {
  needs_interactive "Evernote backup needs initial setup."
  log "Initializing database and authenticating with Evernote..."
  log "Your browser will open for OAuth."
  log ">>> Choose a SHORT token duration (1 month recommended). <<<"
  echo ""
  mkdir -p "$DB_DIR"
  evernote-backup init-db -d "$DB"
}

run_reauth() {
  needs_interactive "Evernote token expired."
  log "Re-authenticating..."
  log "Your browser will open for OAuth."
  log ">>> Choose a SHORT token duration (1 month recommended). <<<"
  echo ""
  sqlite3 "$DB" "REPLACE INTO config(name, value) VALUES ('auth_token', 'pending');"
  evernote-backup reauth -d "$DB"
}

extract_token_to_keychain() {
  local token
  token=$(db_get_token)
  [[ -n "$token" && "$token" != "pending" ]] || die "Could not extract token from database."
  keychain_set "$token"
  db_scrub_token
  log "Token stored in Keychain and removed from database."

  local expiry
  expiry=$(token_expiry_epoch "$token")
  [[ "$expiry" -gt 0 ]] && log "Token expires: $(date -r "$expiry" '+%Y-%m-%d %H:%M:%S')"
}

detect_destination() {
  if [[ -n "${EVERNOTE_BACKUP_DEST:-}" ]]; then
    echo "$EVERNOTE_BACKUP_DEST"
    return
  fi

  if [[ -d "$HOME/Library/CloudStorage" ]]; then
    local gd
    gd=$(find "$HOME/Library/CloudStorage" -maxdepth 1 -name "GoogleDrive-*" -type d 2>/dev/null | head -1)
    if [[ -n "$gd" && -d "$gd/My Drive" ]]; then
      echo "$gd/My Drive/EvernoteBackups"
      return
    fi
  fi

  if [[ -d "/Volumes/GoogleDrive/My Drive" ]]; then
    echo "/Volumes/GoogleDrive/My Drive/EvernoteBackups"
    return
  fi

  echo "$HOME/Documents/EvernoteBackups"
}

install_schedule() {
  mkdir -p "$(dirname "$PLIST_PATH")"
  cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_PATH</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>0</integer>
        <key>Hour</key>
        <integer>10</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$DB_DIR/backup.log</string>
    <key>StandardErrorPath</key>
    <string>$DB_DIR/backup.err</string>
</dict>
</plist>
EOF
  launchctl load "$PLIST_PATH"
  log "Scheduled weekly backup (Sundays at 10:00 AM)."
  log "Logs: $DB_DIR/backup.log"
}

uninstall_schedule() {
  if [[ -f "$PLIST_PATH" ]]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    log "Automated backup schedule removed."
  else
    log "No schedule installed."
  fi
}

# ── Schedule management (early exit) ────────────────────────────

if [[ -n "${UNINSTALL_SCHEDULE:-}" ]]; then
  uninstall_schedule
  exit 0
fi

if [[ -n "${INSTALL_SCHEDULE:-}" ]]; then
  install_schedule
  exit 0
fi

# ── Step 1: Ensure evernote-backup is installed ─────────────────

for cmd in evernote-backup evernote2md; do
  if ! command -v "$cmd" &>/dev/null; then
    log "$cmd not found. Installing via brew..."
    if command -v brew &>/dev/null; then
      brew install "$cmd"
    else
      die "$cmd not found and brew is not available. Install manually."
    fi
  fi
done

# ── Step 2: Ensure database exists and is valid ─────────────────

if [[ -f "$DB" ]] && ! db_is_valid; then
  warn "Database is corrupted. Removing and re-initializing."
  rm -f "$DB"
fi

if [[ ! -f "$DB" ]]; then
  run_init
  extract_token_to_keychain
fi

# ── Step 3: Ensure token is in Keychain ─────────────────────────

TOKEN=$(keychain_get)

if [[ -z "$TOKEN" ]]; then
  DB_TOKEN=$(db_get_token)
  if [[ -n "$DB_TOKEN" && "$DB_TOKEN" != "pending" ]]; then
    log "Found token in database but not Keychain. Migrating..."
    keychain_set "$DB_TOKEN"
    db_scrub_token
    TOKEN="$DB_TOKEN"
  fi
fi

if [[ -z "$TOKEN" ]]; then
  run_reauth
  extract_token_to_keychain
  TOKEN=$(keychain_get)
  [[ -n "$TOKEN" ]] || die "Authentication failed."
fi

# ── Step 4: Scrub any stale token from DB ───────────────────────

db_scrub_token

# ── Step 5: Check token expiration / forced reauth ──────────────

if [[ -n "${FORCE_REAUTH:-}" ]]; then
  log "Forced reauth requested."
  run_reauth
  extract_token_to_keychain
  TOKEN=$(keychain_get)
  [[ -n "$TOKEN" ]] || die "Re-authentication failed."
fi

EXPIRY=$(token_expiry_epoch "$TOKEN")
if [[ "$EXPIRY" -gt 0 ]]; then
  DAYS_LEFT=$(token_days_left "$EXPIRY")

  if [[ $DAYS_LEFT -le 0 ]]; then
    run_reauth
    extract_token_to_keychain
    TOKEN=$(keychain_get)
    [[ -n "$TOKEN" ]] || die "Re-authentication failed."
    EXPIRY=$(token_expiry_epoch "$TOKEN")
    DAYS_LEFT=$(token_days_left "$EXPIRY")
  fi

  if [[ $DAYS_LEFT -le $WARN_DAYS ]]; then
    warn "Token expires in $DAYS_LEFT day(s)."
  fi
fi

# ── Step 6: Sync ────────────────────────────────────────────────

DEST=$(detect_destination)
mkdir -p "$DEST"
log "Backup destination: $DEST"

log "Syncing from Evernote..."
evernote-backup sync -d "$DB" --token "$TOKEN"

# ── Step 7: Export ──────────────────────────────────────────────

log "Exporting notebooks..."
mkdir -p "$EXPORT_DIR"
evernote-backup export -d "$DB" "$EXPORT_DIR/"

# ── Step 8: Convert to Markdown (future-proofing) ───────────────

log "Converting to Markdown..."
mkdir -p "$MD_DIR"
evernote2md "$EXPORT_DIR" "$MD_DIR"

# ── Step 9: Archive ─────────────────────────────────────────────

ARCHIVE="$DEST/$ARCHIVE_NAME"
log "Archiving to $ARCHIVE..."
tar -zcf "$ARCHIVE" \
  -C "$(dirname "$EXPORT_DIR")" "$(basename "$EXPORT_DIR")" \
  -C "$(dirname "$MD_DIR")" "$(basename "$MD_DIR")"

# ── Step 10: Done ───────────────────────────────────────────────

log "Done. Backup saved to: $ARCHIVE"

if [[ ! -t 0 ]]; then
  notify "Evernote Backup" "Backup complete."
fi

# ── Step 11: Offer scheduling (first run only) ──────────────────

if [[ ! -f "$DB_DIR/.setup_complete" ]]; then
  touch "$DB_DIR/.setup_complete"
  if [[ ! -f "$PLIST_PATH" ]] && [[ -t 0 ]]; then
    echo ""
    read -rp "Enable weekly automated backups (Sundays 10am)? [y/N] " answer
    case "$answer" in
      [yY]|[yY][eE][sS]) install_schedule ;;
      *) log "Skipping. Enable later with: INSTALL_SCHEDULE=1 ./backup.sh" ;;
    esac
  fi
fi
