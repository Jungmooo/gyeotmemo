import AppKit

var dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GyeotMemo", isDirectory: true)
let arguments = CommandLine.arguments
for i in arguments.indices.dropLast() where arguments[i] == "--data-dir" {
    dataDirectory = URL(fileURLWithPath: (arguments[i + 1] as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
}
if arguments.dropFirst().first == "--self-test" { exit(SelfTests.run(dataDirectory)) }

let app = NSApplication.shared
if arguments.dropFirst().first == "--layout-test" {
    app.setActivationPolicy(.accessory)
    exit(LayoutTests.run(dataDirectory))
}

// One window per data folder; a second launch brings the running one forward instead.
try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
let instanceLock = open(dataDirectory.appendingPathComponent(".lock").path, O_RDWR | O_CREAT, 0o644)
if instanceLock >= 0 && flock(instanceLock, LOCK_EX | LOCK_NB) != 0 {
    let me = ProcessInfo.processInfo.processIdentifier
    NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        .first { $0.processIdentifier != me }?.activate(options: [])
    exit(0)
}

private var errorLog = dataDirectory.appendingPathComponent("error.log")
NSSetUncaughtExceptionHandler { exception in
    // Leave the original data intact and make unexpected errors visible.
    let line = "\(Date())\n\(exception.name.rawValue): \(exception.reason ?? "")\n\(exception.callStackSymbols.joined(separator: "\n"))\n"
    if let handle = try? FileHandle(forWritingTo: errorLog) { handle.seekToEndOfFile(); handle.write(line.data(using: .utf8)!); handle.closeFile() }
    else { try? line.write(to: errorLog, atomically: true, encoding: .utf8) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: MainController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MainController(store: MemoStore(directory: dataDirectory))
        NSApp.mainMenu = buildMenu()
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { controller.canClose() ? .terminateNow : .terminateCancel }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if controller.window.isMiniaturized { controller.window.deminiaturize(nil) }
        controller.window.makeKeyAndOrderFront(nil)
        return true
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func revealData() { NSWorkspace.shared.activateFileViewerSelecting([controller.store.filePath]) }

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title); items.forEach(menu.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: ""); holder.submenu = menu; main.addItem(holder)
        }
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.keyEquivalentModifierMask = modifiers; item.target = target; return item
        }
        submenu("곁메모", [
            item("곁메모에 관하여", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("저장 폴더 열기", #selector(revealData), target: self),
            .separator(),
            item("곁메모 가리기", #selector(NSApplication.hide(_:)), "h"),
            item("기타 가리기", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("모두 보기", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("곁메모 종료", #selector(NSApplication.terminate(_:)), "q"),
        ])
        submenu("편집", [
            item("실행 취소", Selector(("undo:")), "z"),
            item("실행 복귀", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("오려두기", #selector(NSText.cut(_:)), "x"),
            item("복사하기", #selector(NSText.copy(_:)), "c"),
            item("붙여넣기", #selector(NSText.paste(_:)), "v"),
            item("모두 선택", #selector(NSText.selectAll(_:)), "a"),
        ])
        submenu("할 일", [
            item("새 할 일", #selector(MainController.focusInput), "n", target: controller),
            item("완료 정리", #selector(MainController.clearCompleted), target: controller),
            item("삭제 되돌리기", #selector(MainController.undoClicked), target: controller),
        ])
        let window = [
            item("항상 위 고정", #selector(MainController.togglePin), "p", [.command, .shift], target: controller),
            .separator(),
            item("최소화", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("닫기", #selector(NSWindow.performClose(_:)), "w"),
        ]
        submenu("윈도우", window)
        NSApp.windowsMenu = main.items.last?.submenu
        return main
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
