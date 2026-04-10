#!/bin/zsh
set -euo pipefail

APP_NAME="CodexApprovalNotifier"
APP_DIR="/Applications/${APP_NAME}.app"
CODEX_DIR="${HOME}/.codex"
SCRIPTS_DIR="${CODEX_DIR}/scripts"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
WATCHER_LABEL="com.coder.codex-approval-watcher"
NOTIFIER_LABEL="com.coder.codex-approval-notifier"

launchctl bootout "gui/$(id -u)/${WATCHER_LABEL}" >/dev/null 2>&1 || true
launchctl bootout "gui/$(id -u)/${NOTIFIER_LABEL}" >/dev/null 2>&1 || true

rm -f "${LAUNCH_AGENTS_DIR}/${WATCHER_LABEL}.plist"
rm -f "${LAUNCH_AGENTS_DIR}/${NOTIFIER_LABEL}.plist"
rm -f "${SCRIPTS_DIR}/codex_approval_watcher.py"
rm -f "${SCRIPTS_DIR}/codex_approval_notifier_main.swift"
rm -rf "${CODEX_DIR}/notification-queue"
rm -f "${CODEX_DIR}/approval-watcher.log" "${CODEX_DIR}/approval-watcher-state.json"
rm -f "${CODEX_DIR}/approval-watcher.stdout.log" "${CODEX_DIR}/approval-watcher.stderr.log"
rm -f "${CODEX_DIR}/app-notifier.log" "${CODEX_DIR}/app-notifier.stdout.log" "${CODEX_DIR}/app-notifier.stderr.log"
rm -rf "${APP_DIR}"

echo "Uninstalled ${APP_NAME}."
