#!/usr/bin/env python3

import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Dict, Iterable, Optional


CODEX_HOME = Path.home() / ".codex"
SESSIONS_ROOT = CODEX_HOME / "sessions"
STATE_PATH = CODEX_HOME / "approval-watcher-state.json"
LOG_PATH = CODEX_HOME / "approval-watcher.log"
APP_NOTIFIER_BUNDLE = Path("/Applications/CodexApprovalNotifier.app")
QUEUE_DIR = CODEX_HOME / "notification-queue"
POLL_INTERVAL_SECONDS = 1.0
MAX_SEEN_EVENT_IDS = 200


def log(message: str) -> None:
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as handle:
        handle.write(f"{timestamp} {message}\n")


def load_state() -> dict:
    if not STATE_PATH.exists():
        return {"offsets": {}, "seen_event_ids": [], "initialized": False}
    try:
        state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
        state.setdefault("offsets", {})
        state.setdefault("seen_event_ids", [])
        state.setdefault("initialized", True)
        return state
    except Exception:
        return {"offsets": {}, "seen_event_ids": [], "initialized": False}


def save_state(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def trim_seen_event_ids(state: dict) -> None:
    seen = state.setdefault("seen_event_ids", [])
    if len(seen) > MAX_SEEN_EVENT_IDS:
        del seen[:-MAX_SEEN_EVENT_IDS]


def shutil_which(name: str) -> Optional[str]:
    for directory in os.environ.get("PATH", "").split(":"):
        candidate = Path(directory) / name
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def send_notification(title: str, body: str) -> None:
    body = body.strip().replace("\n", " ")
    if len(body) > 180:
        body = body[:177] + "..."

    if APP_NOTIFIER_BUNDLE.exists():
        QUEUE_DIR.mkdir(parents=True, exist_ok=True)
        item_id = str(uuid.uuid4())
        queue_path = QUEUE_DIR / f"{int(time.time() * 1000)}-{item_id}.json"
        queue_path.write_text(
            json.dumps({"id": item_id, "title": title, "body": body}, ensure_ascii=False),
            encoding="utf-8",
        )
        log(f"notification queued via app-notifier: {body!r}")
        return

    log("notification failed: app notifier bundle not found")


def parse_json_line(line: str) -> Optional[dict]:
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        return None


def parse_function_arguments(arguments: str) -> Optional[dict]:
    try:
        return json.loads(arguments)
    except Exception:
        return None


def describe_approval_event(entry: dict) -> Optional[dict]:
    payload = entry.get("payload")
    if not isinstance(payload, dict):
        return None

    if entry.get("type") == "response_item" and payload.get("type") == "function_call":
        name = payload.get("name")
        arguments = payload.get("arguments")
        if not isinstance(arguments, str):
            return None

        parsed_arguments = parse_function_arguments(arguments) or {}
        if name == "exec_command" and parsed_arguments.get("sandbox_permissions") == "require_escalated":
            command = parsed_arguments.get("cmd", "")
            justification = parsed_arguments.get("justification", "")
            return {
                "event_id": payload.get("call_id") or f"{entry.get('timestamp')}:{name}",
                "title": "Codex 审批",
                "body": "有新的审批确认，请查看。",
                "detail": {
                    "kind": "exec_command",
                    "command": command,
                    "justification": justification,
                },
            }

    if entry.get("type") == "event_msg" and payload.get("type") in {
        "exec_approval_request",
        "apply_patch_approval_request",
        "request_permissions",
    }:
        event_type = payload.get("type")
        return {
            "event_id": payload.get("item_id") or f"{entry.get('timestamp')}:{event_type}",
            "title": "Codex 审批",
            "body": "有新的审批确认，请查看。",
            "detail": payload,
        }

    return None


def iter_session_files() -> Iterable[Path]:
    if not SESSIONS_ROOT.exists():
        return []
    return sorted(SESSIONS_ROOT.rglob("*.jsonl"))


def process_file(path: Path, state: dict) -> None:
    offsets: Dict[str, int] = state.setdefault("offsets", {})
    seen_event_ids = state.setdefault("seen_event_ids", [])
    key = str(path)
    offset = offsets.get(key, 0)

    try:
        size = path.stat().st_size
    except OSError:
        return

    if size < offset:
        offset = 0

    try:
        with path.open("r", encoding="utf-8") as handle:
            handle.seek(offset)
            for line in handle:
                entry = parse_json_line(line)
                if not entry:
                    continue
                approval = describe_approval_event(entry)
                if not approval:
                    continue
                event_id = approval["event_id"]
                if event_id in seen_event_ids:
                    continue
                seen_event_ids.append(event_id)
                trim_seen_event_ids(state)
                log(
                    f"approval detected: file={path} detail={json.dumps(approval['detail'], ensure_ascii=False)}"
                )
                send_notification(approval["title"], approval["body"])
            offsets[key] = handle.tell()
    except OSError as exc:
        log(f"failed to process {path}: {exc}")


def initialize_offsets(state: dict) -> None:
    offsets = state.setdefault("offsets", {})
    for path in iter_session_files():
        try:
            offsets[str(path)] = path.stat().st_size
        except OSError:
            continue
    state["initialized"] = True
    save_state(state)
    log("approval watcher initialized at current session EOF")


def main() -> int:
    log("approval watcher started")
    state = load_state()
    if not state.get("initialized"):
        initialize_offsets(state)

    while True:
        for path in iter_session_files():
            process_file(path, state)
        save_state(state)
        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        log("approval watcher stopped")
        sys.exit(0)
