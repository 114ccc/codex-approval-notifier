import AppKit
import Foundation
import UserNotifications

let codexDir = (NSHomeDirectory() as NSString).appendingPathComponent(".codex")
let logPath = (codexDir as NSString).appendingPathComponent("app-notifier.log")
let queueDir = (codexDir as NSString).appendingPathComponent("notification-queue")

func appendLog(_ message: String) {
    let formatter = ISO8601DateFormatter()
    let line = "\(formatter.string(from: Date())) \(message)\n"
    let url = URL(fileURLWithPath: logPath)
    let directory = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

enum NotifyError: Error, CustomStringConvertible {
    case authorizationDenied
    case authorizationError(String)
    case deliveryError(String)
    case timeout(String)

    var description: String {
        switch self {
        case .authorizationDenied:
            return "authorization denied"
        case .authorizationError(let message):
            return "authorization error: \(message)"
        case .deliveryError(let message):
            return "delivery error: \(message)"
        case .timeout(let message):
            return "timeout: \(message)"
        }
    }
}

func wait(timeout: TimeInterval, work: (@escaping (Result<Void, NotifyError>) -> Void) -> Void) -> Result<Void, NotifyError> {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<Void, NotifyError> = .failure(.timeout("unknown"))

    work { callbackResult in
        result = callbackResult
        semaphore.signal()
    }

    if semaphore.wait(timeout: .now() + timeout) == .timedOut {
        return .failure(.timeout("operation timed out"))
    }

    return result
}

func requestAuthorization(center: UNUserNotificationCenter) -> Result<Void, NotifyError> {
    wait(timeout: 10) { done in
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                done(.failure(.authorizationError(error.localizedDescription)))
                return
            }
            if granted {
                done(.success(()))
            } else {
                done(.failure(.authorizationDenied))
            }
        }
    }
}

func deliverNotification(center: UNUserNotificationCenter, title: String, body: String) -> Result<Void, NotifyError> {
    wait(timeout: 10) { done in
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codex-approval-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                done(.failure(.deliveryError(error.localizedDescription)))
                return
            }
            done(.success(()))
        }
    }
}

func showAlert(title: String, message: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

struct QueueItem: Decodable {
    let id: String
    let title: String
    let body: String
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let center = UNUserNotificationCenter.current()
let arguments = CommandLine.arguments
let isBackgroundLaunch = arguments.contains("--background")

appendLog("launch args=\(arguments)")
appendLog("bundlePath=\(Bundle.main.bundlePath)")
appendLog("app initialized")

let authorizationResult = requestAuthorization(center: center)

switch authorizationResult {
case .success:
    appendLog("authorization granted")
case .failure(let error):
    appendLog("authorization failed: \(error)")
    if !isBackgroundLaunch {
        showAlert(
            title: "CodexApprovalNotifier 需要通知权限",
            message: "当前无法获取通知权限：\(error)\n\n请到 系统设置 -> 通知 中检查 CodexApprovalNotifier。"
        )
    }
}

if arguments.count >= 3 && !isBackgroundLaunch {
    let title = arguments[1]
    let body = arguments[2]
    if case .success = authorizationResult {
        switch deliverNotification(center: center, title: title, body: body) {
        case .success:
            appendLog("notification queued title=\(title) body=\(body)")
        case .failure(let error):
            appendLog("notification delivery failed: \(error)")
        }
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
    exit(0)
}

if !isBackgroundLaunch {
    if case .success = authorizationResult {
        showAlert(
            title: "CodexApprovalNotifier 已就绪",
            message: "通知权限已授予。保持此 app 运行即可接收 Codex 审批提醒。"
        )
    }
}

func processQueue() {
    guard case .success = authorizationResult else {
        return
    }

    let fm = FileManager.default
    let queueURL = URL(fileURLWithPath: queueDir, isDirectory: true)
    try? fm.createDirectory(at: queueURL, withIntermediateDirectories: true)

    guard let items = try? fm.contentsOfDirectory(at: queueURL, includingPropertiesForKeys: nil)
        .filter({ $0.pathExtension == "json" })
        .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) else {
        return
    }

    for itemURL in items {
        guard let data = try? Data(contentsOf: itemURL),
              let item = try? JSONDecoder().decode(QueueItem.self, from: data) else {
            appendLog("failed to decode queue item \(itemURL.path)")
            try? fm.removeItem(at: itemURL)
            continue
        }

        switch deliverNotification(center: center, title: item.title, body: item.body) {
        case .success:
            appendLog("queue notification sent id=\(item.id) title=\(item.title)")
            try? fm.removeItem(at: itemURL)
        case .failure(let error):
            appendLog("queue notification failed id=\(item.id) error=\(error)")
        }
    }
}

appendLog("entering queue loop background=\(isBackgroundLaunch)")
while true {
    processQueue()
    Thread.sleep(forTimeInterval: 1.0)
}
