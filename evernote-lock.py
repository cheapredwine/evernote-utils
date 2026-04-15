#!/usr/bin/env python3
"""evernote-lock.py — Lock/unlock Evernote notes via contentClass.

Makes notes read-only using the contentClass attribute so they
can't be accidentally edited in any Evernote client. To lock notes,
tag them in Evernote, then run this tool.

Usage:
    ./evernote-lock.py lock                    # Lock all notes tagged "ReadOnly"
    ./evernote-lock.py lock --tag DoNotEdit    # Use a different tag name
    ./evernote-lock.py lock --note-guid GUID   # Lock a specific note by GUID
    ./evernote-lock.py unlock                  # Unlock all notes locked by this tool
    ./evernote-lock.py unlock --note-guid GUID # Unlock a specific note
    ./evernote-lock.py status                  # List currently locked notes

Token is pulled from macOS Keychain (shared with backup.sh) or
passed directly with --token.
"""

import argparse
import subprocess
import sys
from typing import Optional

try:
    from evernote.edam.notestore.ttypes import NoteFilter, NotesMetadataResultSpec
    from evernote.edam.type.ttypes import Note, NoteAttributes
    from evernote_backup.evernote_client_api_http import (
        NoteStoreClientRetryable,
        UserStoreClientRetryable,
    )
except ImportError:
    print("Missing dependencies. Install with: pip install evernote-backup")
    sys.exit(1)

KEYCHAIN_SERVICE = "com.cheapredwine.evernote-backup"
KEYCHAIN_ACCOUNT = "evernote-token"
CONTENT_CLASS = "cheapredwine.readonly"
EVERNOTE_HOST = "www.evernote.com"
DEFAULT_TAG = "ReadOnly"
MAX_NOTES = 250


def get_token(cli_token: Optional[str] = None) -> str:
    """Get token from CLI arg, Keychain, or fail with instructions."""
    if cli_token:
        return cli_token

    # Try Keychain (populated by backup.sh)
    try:
        result = subprocess.run(
            [
                "security",
                "find-generic-password",
                "-a", KEYCHAIN_ACCOUNT,
                "-s", KEYCHAIN_SERVICE,
                "-w",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        token = result.stdout.strip()
        if token:
            return token
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    print("No token available. Provide one with --token or run backup.sh to set up Keychain.")
    sys.exit(1)


def get_shard(token: str) -> str:
    """Extract shard ID from Evernote token string."""
    for part in token.split(":"):
        if part.startswith("S="):
            return part[2:]
    raise ValueError("Could not extract shard from token")


def get_note_store(token: str) -> NoteStoreClientRetryable:
    """Create an authenticated NoteStore client."""
    shard = get_shard(token)
    return NoteStoreClientRetryable(
        auth_token=token,
        store_url=f"https://{EVERNOTE_HOST}/edam/note/{shard}",
        user_agent="evernote-lock/1.0",
    )


def find_tag_guid(note_store: NoteStoreClientRetryable, tag_name: str) -> Optional[str]:
    """Find a tag's GUID by name."""
    tags = note_store.listTags()
    for tag in tags:
        if tag.name.lower() == tag_name.lower():
            return tag.guid
    return None


def find_notes_by_tag(
    note_store: NoteStoreClientRetryable, tag_guid: str
) -> list[tuple[str, str]]:
    """Find all notes with a given tag. Returns list of (guid, title)."""
    note_filter = NoteFilter(tagGuids=[tag_guid])
    result_spec = NotesMetadataResultSpec(includeTitle=True, includeAttributes=True)

    notes = []
    offset = 0
    while True:
        batch = note_store.findNotesMetadata(note_filter, offset, MAX_NOTES, result_spec)
        for note_meta in batch.notes:
            notes.append((note_meta.guid, note_meta.title))
        if len(batch.notes) < MAX_NOTES:
            break
        offset += MAX_NOTES

    return notes


def find_locked_notes(
    note_store: NoteStoreClientRetryable,
) -> list[tuple[str, str]]:
    """Find all notes locked by this tool."""
    note_filter = NoteFilter(words=f"contentClass:{CONTENT_CLASS}")
    result_spec = NotesMetadataResultSpec(includeTitle=True)

    notes = []
    offset = 0
    while True:
        batch = note_store.findNotesMetadata(note_filter, offset, MAX_NOTES, result_spec)
        for note_meta in batch.notes:
            notes.append((note_meta.guid, note_meta.title))
        if len(batch.notes) < MAX_NOTES:
            break
        offset += MAX_NOTES

    return notes


def lock_note(note_store: NoteStoreClientRetryable, guid: str, title: str) -> bool:
    """Set contentClass on a note to make it read-only."""
    note = note_store.getNote(guid, False, False, False, False)

    if note.attributes and note.attributes.contentClass == CONTENT_CLASS:
        print(f"  Already locked: {title}")
        return False

    update = Note()
    update.guid = guid
    update.title = note.title
    update.attributes = note.attributes or NoteAttributes()
    update.attributes.contentClass = CONTENT_CLASS

    note_store.updateNote(update)
    print(f"  Locked: {title}")
    return True


def unlock_note(note_store: NoteStoreClientRetryable, guid: str, title: str) -> bool:
    """Clear contentClass on a note to make it editable."""
    note = note_store.getNote(guid, False, False, False, False)

    if not note.attributes or not note.attributes.contentClass:
        print(f"  Already unlocked: {title}")
        return False

    if note.attributes.contentClass != CONTENT_CLASS:
        print(f"  Skipping (locked by another app): {title}")
        return False

    update = Note()
    update.guid = guid
    update.title = note.title
    update.attributes = note.attributes
    update.attributes.contentClass = None

    note_store.updateNote(update)
    print(f"  Unlocked: {title}")
    return True


def cmd_lock(note_store: NoteStoreClientRetryable, args: argparse.Namespace) -> None:
    """Lock notes by tag or specific GUID."""
    if args.note_guid:
        note = note_store.getNote(args.note_guid, False, False, False, False)
        lock_note(note_store, args.note_guid, note.title)
        return

    tag_guid = find_tag_guid(note_store, args.tag)
    if not tag_guid:
        print(f"Tag '{args.tag}' not found in your account.")
        sys.exit(1)

    notes = find_notes_by_tag(note_store, tag_guid)
    if not notes:
        print(f"No notes found with tag '{args.tag}'.")
        return

    print(f"Locking {len(notes)} note(s) tagged '{args.tag}':")
    locked = sum(1 for guid, title in notes if lock_note(note_store, guid, title))
    print(f"\n{locked} note(s) locked.")


def cmd_unlock(note_store: NoteStoreClientRetryable, args: argparse.Namespace) -> None:
    """Unlock all notes locked by this tool, or a specific one."""
    if args.note_guid:
        note = note_store.getNote(args.note_guid, False, False, False, False)
        unlock_note(note_store, args.note_guid, note.title)
        return

    notes = find_locked_notes(note_store)
    if not notes:
        print("No locked notes found.")
        return

    print(f"Unlocking {len(notes)} note(s):")
    unlocked = sum(1 for guid, title in notes if unlock_note(note_store, guid, title))
    print(f"\n{unlocked} note(s) unlocked.")


def cmd_status(note_store: NoteStoreClientRetryable, args: argparse.Namespace) -> None:
    """Show all currently locked notes."""
    notes = find_locked_notes(note_store)
    if not notes:
        print("No locked notes.")
        return

    print(f"{len(notes)} locked note(s):")
    for guid, title in notes:
        print(f"  {title}  [{guid}]")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Lock/unlock Evernote notes to prevent accidental edits."
    )
    parser.add_argument("--token", help="Evernote auth token (otherwise uses Keychain)")
    subparsers = parser.add_subparsers(dest="command", required=True)

    lock_parser = subparsers.add_parser("lock", help="Lock notes (make read-only)")
    lock_parser.add_argument(
        "--tag", default=DEFAULT_TAG, help=f"Tag to match (default: {DEFAULT_TAG})"
    )
    lock_parser.add_argument("--note-guid", help="Lock a specific note by GUID")

    unlock_parser = subparsers.add_parser("unlock", help="Unlock notes (make editable)")
    unlock_parser.add_argument("--note-guid", help="Unlock a specific note by GUID")

    subparsers.add_parser("status", help="Show locked notes")

    args = parser.parse_args()

    token = get_token(args.token)
    note_store = get_note_store(token)

    commands = {
        "lock": cmd_lock,
        "unlock": cmd_unlock,
        "status": cmd_status,
    }

    commands[args.command](note_store, args)


if __name__ == "__main__":
    main()
