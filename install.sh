#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CodexApprovalNotifier"
APP_DIR="/Applications/${APP_NAME}.app"
CODEX_DIR="${HOME}/.codex"
SCRIPTS_DIR="${CODEX_DIR}/scripts"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
WATCHER_LABEL="com.coder.codex-approval-watcher"
NOTIFIER_LABEL="com.coder.codex-approval-notifier"

mkdir -p "${SCRIPTS_DIR}" "${LAUNCH_AGENTS_DIR}"

cp "${ROOT_DIR}/scripts/codex_approval_watcher.py" "${SCRIPTS_DIR}/codex_approval_watcher.py"
cp "${ROOT_DIR}/scripts/codex_approval_notifier_main.swift" "${SCRIPTS_DIR}/codex_approval_notifier_main.swift"

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${ROOT_DIR}/app-template/Contents/Info.plist" "${APP_DIR}/Contents/Info.plist"

if [[ -f "/Applications/Codex.app/Contents/Resources/electron.icns" ]]; then
  cp "/Applications/Codex.app/Contents/Resources/electron.icns" "${APP_DIR}/Contents/Resources/CodexApprovalNotifier.icns"
fi

swiftc "${SCRIPTS_DIR}/codex_approval_notifier_main.swift" -o "${APP_DIR}/Contents/MacOS/CodexApprovalNotifier"
codesign --force --deep -s - "${APP_DIR}"

cat > "${LAUNCH_AGENTS_DIR}/${WATCHER_LABEL}.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${WATCHER_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>${SCRIPTS_DIR}/codex_approval_watcher.py</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
  <key>StandardOutPath</key>
  <string>${CODEX_DIR}/approval-watcher.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${CODEX_DIR}/approval-watcher.stderr.log</string>
</dict>
</plist>
PLIST

cat > "${LAUNCH_AGENTS_DIR}/${NOTIFIER_LABEL}.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${NOTIFIER_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${APP_DIR}/Contents/MacOS/CodexApprovalNotifier</string>
    <string>--background</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
  <key>StandardOutPath</key>
  <string>${CODEX_DIR}/app-notifier.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${CODEX_DIR}/app-notifier.stderr.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/${WATCHER_LABEL}" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)/${NOTIFIER_LABEL}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "${LAUNCH_AGENTS_DIR}/${NOTIFIER_LABEL}.plist"
launchctl bootstrap "gui/$(id -u)" "${LAUNCH_AGENTS_DIR}/${WATCHER_LABEL}.plist"
launchctl kickstart -k "gui/$(id -u)/${NOTIFIER_LABEL}"
launchctl kickstart -k "gui/$(id -u)/${WATCHER_LABEL}"

open "${APP_DIR}"

cat <<EOF
Installed ${APP_NAME}.

Next steps:
1. Open System Settings -> Notifications
2. Allow notifications for ${APP_NAME}
3. Keep ${APP_NAME} installed in /Applications

The app was opened for initial authorization.
EOF
