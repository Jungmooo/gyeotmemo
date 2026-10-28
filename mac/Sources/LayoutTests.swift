import AppKit

/// Counterpart of tests/LayoutRegression.cs: drives the real window and memo handle off-screen.
enum LayoutTests {
    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw StorageError(message) } }

    private static func open(_ directory: URL) -> MainController {
        let controller = MainController(store: MemoStore(directory: directory))
        controller.window.title = "곁메모 · 레이아웃 검증"
        controller.window.orderFront(nil)
        controller.window.contentView?.layoutSubtreeIfNeeded(); controller.table.sizeLastColumnToFit()
        return controller
    }
    private static func drag(_ controller: MainController, _ delta: CGFloat) {
        controller.handle.onDragBegan?(); controller.handle.onDrag?(delta); controller.handle.onDragEnded?()
        controller.window.contentView?.layoutSubtreeIfNeeded()
    }
    private static func metrics(_ c: MainController) -> String {
        let note = c.notePane.convert(c.notePane.bounds, to: nil)
        return String(format: "window=%.1f, memo=%.1f, memo bottom=%.1f, memo max=%.1f", c.window.frame.height, note.height, note.minY, c.maxNoteHeight)
    }

    /// Drives the same paths as the keyboard and mouse: field editor typing, Return, Escape, ⌘Z and reordering.
    private static func flow(_ directory: URL, _ report: inout [String]) throws {
        var c = open(directory)
        func type(_ text: String) {
            guard let editor = c.window.firstResponder as? NSTextView else { return }
            editor.selectAll(nil); editor.insertText(text, replacementRange: editor.selectedRange())
        }
        func press(_ command: Selector) { (c.window.firstResponder as? NSTextView)?.doCommand(by: command) }
        c.focusInput(); type("  첫 번째 할 일  "); press(#selector(NSResponder.insertNewline(_:)))
        c.focusInput(); type("두 번째"); press(#selector(NSResponder.insertNewline(_:)))
        c.focusInput(); type("   "); press(#selector(NSResponder.insertNewline(_:)))
        try check(c.tasks.map { $0.text } == ["첫 번째 할 일", "두 번째"] && c.table.numberOfRows == 2, "Return adds trimmed tasks and ignores blanks")
        report.append("PASS: Return adds trimmed tasks, blank input ignored, list shows \(c.table.numberOfRows) rows")

        c.beginEdit(c.tasks[1]); type("고친 할 일"); press(#selector(NSResponder.insertNewline(_:)))
        try check(c.tasks[1].text == "고친 할 일" && c.window.firstResponder === c.table, "Return commits inline edit")
        c.beginEdit(c.tasks[1]); type("취소될 글"); press(#selector(NSResponder.cancelOperation(_:)))
        c.beginEdit(c.tasks[0]); type("   "); c.window.makeFirstResponder(c.table)
        try check(c.tasks[1].text == "고친 할 일" && c.tasks[0].text == "첫 번째 할 일", "Escape and blank edits keep the original")
        report.append("PASS: inline edit commits on Return, Escape and blank text restore the original")

        c.table.selectRowIndexes([1], byExtendingSelection: false); c.moveSelected(by: -1)
        try check(c.tasks.map { $0.text } == ["고친 할 일", "첫 번째 할 일"], "⌥↑ moves the selected task")
        c.table.selectRowIndexes([0], byExtendingSelection: false); c.toggleSelected(); c.clearCompleted()
        try check(c.tasks.map { $0.text } == ["첫 번째 할 일"], "Clear completed")
        c.window.makeFirstResponder(c.table); c.window.undo(nil)
        try check(c.tasks.map { $0.text } == ["고친 할 일", "첫 번째 할 일"] && c.tasks[0].completed, "⌘Z restores cleared task in place")
        report.append("PASS: reorder, complete, clear completed and ⌘Z restore in the original position")

        c.togglePin()
        try check(c.window.level == .normal, "Unpin lowers the window")
        c.focusInput(); type("작성 중")
        try check(c.saveNow() && c.canClose(), "Save")
        c.window.orderOut(nil)
        c = open(directory)
        try check(c.tasks.map { $0.text } == ["고친 할 일", "첫 번째 할 일"] && c.tasks[0].completed && c.window.level == .normal && c.store.load().draft == "작성 중", "Flow round-trip")
        report.append("PASS: order, completion, unpinned state and draft survive reopening")
        _ = c.canClose(); c.window.orderOut(nil)
    }

    static func run(_ directory: URL) -> Int32 {
        let sandbox = directory.appendingPathComponent("layout-" + TodoItem.newId())
        var report: [String] = []
        func finish(_ code: Int32) -> Int32 {
            let text = report.joined(separator: "\n") + "\n"
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? text.write(to: directory.appendingPathComponent("layout-test-results.txt"), atomically: true, encoding: .utf8)
            print(text, terminator: "")
            return code
        }
        do {
            var c = open(sandbox)
            let windowHeight = c.window.frame.height, start = c.notePane.frame.height
            report.append("initial: " + metrics(c))
            try check(abs(start - 136) < 0.5, "Default memo height \(start)")

            drag(c, 100)
            try check(abs(c.notePane.frame.height - (start + 100)) < 0.5 && c.window.frame.height == windowHeight, "Drag up grows memo: " + metrics(c))
            report.append("PASS: drag up 100 grows memo \(Int(start)) -> \(Int(c.notePane.frame.height)), window unchanged")

            drag(c, -60)
            try check(abs(c.notePane.frame.height - (start + 40)) < 0.5, "Drag down shrinks memo: " + metrics(c))
            report.append("PASS: drag down shrinks memo to \(Int(c.notePane.frame.height))")

            drag(c, 5000)
            let maximum = c.notePane.frame.height
            try check(abs(maximum - c.maxNoteHeight) < 0.5 && maximum > start + 100, "Drag clamps to maximum: " + metrics(c))
            drag(c, -5000)
            try check(abs(c.notePane.frame.height - MainController.minNote) < 0.5, "Drag clamps to minimum: " + metrics(c))
            drag(c, 5000)
            report.append("PASS: memo clamps between \(Int(MainController.minNote)) and \(Int(maximum))")

            c.window.makeFirstResponder(nil)
            try check(c.saveNow() && c.canClose(), "Save before reopen")
            c.window.orderOut(nil)

            c = open(sandbox)
            try check(abs(c.notePane.frame.height - maximum) < 0.5, "Maximum memo height restored: " + metrics(c))
            report.append("PASS: reopen restores memo height \(Int(maximum))")

            c.window.setFrame(NSRect(origin: c.window.frame.origin, size: c.window.minSize), display: true)
            c.window.contentView?.layoutSubtreeIfNeeded()
            let note = c.notePane.convert(c.notePane.bounds, to: nil)
            try check(c.window.frame.size == c.window.minSize, "Window shrinks to its minimum despite a tall memo: " + metrics(c))
            try check(note.minY >= 32 - 0.5 && note.height >= MainController.minNote - 0.5 && note.height <= c.maxNoteHeight + 0.5, "Memo stays inside window at minimum size: " + metrics(c))
            let restored = NSRect(origin: c.window.frame.origin, size: NSSize(width: 380, height: 650))
            c.window.setFrame(restored, display: true); c.window.contentView?.layoutSubtreeIfNeeded()
            try check(abs(c.notePane.frame.height - maximum) < 0.5, "Memo returns to its requested height when the window grows: " + metrics(c))
            report.append("PASS: minimum window \(Int(c.window.minSize.height)) keeps memo above the status bar; memo returns to \(Int(maximum)) when enlarged")
            _ = c.canClose(); c.window.orderOut(nil)

            try flow(sandbox.appendingPathComponent("flow"), &report)
            try? FileManager.default.removeItem(at: sandbox)
            return finish(0)
        } catch {
            report.append("FAIL: \(error.localizedDescription)")
            return finish(1)
        }
    }
}
