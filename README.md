# Codex Approval Notifier

macOS helper that shows a system notification when Codex opens a real command-approval prompt.

## What it does

- Watches Codex session files under `~/.codex/sessions`
- Detects real approval requests such as `exec_command` calls with `sandbox_permissions=require_escalated`
- Queues a notification
- Uses a small macOS app in `/Applications/CodexApprovalNotifier.app` to deliver the notification

Notification text:

`有新的审批确认，请查看。`

## Requirements

- macOS
- Codex CLI already installed and in use
- `python3`
- `swiftc`
- Permission to copy an app into `/Applications`

## Install

From this repository root:

```bash
chmod +x install.sh
./install.sh
```

The installer will:

1. Copy the watcher/notifier sources into `~/.codex/scripts`
2. Build `CodexApprovalNotifier.app`
3. Install the app into `/Applications`
4. Register two LaunchAgents:
   - `com.coder.codex-approval-notifier`
   - `com.coder.codex-approval-watcher`
5. Open the app so you can approve notification permissions

## First-run setup

After install:

1. Open `CodexApprovalNotifier.app` if it is not already open
2. Go to `System Settings -> Notifications`
3. Allow notifications for `CodexApprovalNotifier`

## Verify

You can trigger a test notification by running:

```bash
python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location('watcher', '/Users/coder/.codex/scripts/codex_approval_watcher.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.send_notification('Codex Test', '这是测试通知')
print('queued')
PY
```

## Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
```

## Files installed on the target machine

- `/Applications/CodexApprovalNotifier.app`
- `~/.codex/scripts/codex_approval_watcher.py`
- `~/.codex/scripts/codex_approval_notifier_main.swift`
- `~/Library/LaunchAgents/com.coder.codex-approval-watcher.plist`
- `~/Library/LaunchAgents/com.coder.codex-approval-notifier.plist`

## Logs

- `~/.codex/approval-watcher.log`
- `~/.codex/app-notifier.log`

## Notes

- The installer tries to reuse the Codex app icon from `/Applications/Codex.app` if it exists.
- This project is currently packaged for local installation, not notarized distribution.
