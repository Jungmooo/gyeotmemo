import Foundation

enum SelfTests {
    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw StorageError(message) } }
    private static func files(_ dir: URL, _ match: (String) -> Bool) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter(match)
    }

    static func run(_ directory: URL) -> Int32 {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let sandbox = directory.appendingPathComponent("test-" + TodoItem.newId())
        var report: [String] = []
        func finish(_ code: Int32) -> Int32 {
            let text = report.joined(separator: "\n") + "\n"
            try? text.write(to: directory.appendingPathComponent("self-test-results.txt"), atomically: true, encoding: .utf8)
            print(text, terminator: "")
            return code
        }
        do {
            try fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
            let store = MemoStore(directory: sandbox)
            let state = store.load()
            try check(state.tasks.isEmpty && state.pinned, "Empty defaults")
            report.append("PASS: empty startup and pinned default")

            state.tasks.append(TodoItem(text: "한글 · 실험 결과 확인 📝", completed: true))
            state.note = "첫 줄\r\n둘째 줄: 0.5 ~ 2.5"; state.draft = "작성 중인 할 일"
            state.left = -430; state.top = 68; state.width = 360; state.height = 670; state.noteHeight = 150; state.pinned = false
            try store.save(state)
            var loaded = MemoStore(directory: sandbox).load()
            try check(loaded.tasks[0].text == state.tasks[0].text && loaded.tasks[0].completed && loaded.tasks[0].id == state.tasks[0].id, "Task persistence")
            try check(loaded.note == state.note && loaded.draft == state.draft && loaded.left == -430 && loaded.width == 360 && loaded.height == 670 && loaded.noteHeight == 150 && !loaded.pinned, "State persistence")
            report.append("PASS: Korean / Unicode, multi-line note, draft, completion, geometry and pin round-trip")

            state.note = "두 번째 저장"; try store.save(state)
            try check(fm.fileExists(atPath: store.backupPath.path) && files(sandbox, { $0.hasSuffix(".tmp") }).isEmpty, "Atomic backup")
            try "{broken-json".write(to: store.filePath, atomically: false, encoding: .utf8)
            let recovering = MemoStore(directory: sandbox); loaded = recovering.load()
            try check(loaded.note == "첫 줄\r\n둘째 줄: 0.5 ~ 2.5" && recovering.loadMessage != nil && !recovering.writeBlocked, "Backup recovery")
            try check(files(sandbox, { $0.hasPrefix("memo.unreadable-") }).count == 1, "Original archive")
            try recovering.save(loaded)
            try check(MemoStore(directory: sandbox).load().tasks.count == 1, "Recovered save")
            report.append("PASS: atomic save, backup recovery, original archive and subsequent save")

            let futureDir = sandbox.appendingPathComponent("future"); try fm.createDirectory(at: futureDir, withIntermediateDirectories: true)
            let futureJson = "{\"Version\":2,\"Tasks\":[],\"Note\":\"future-format\"}"
            try futureJson.write(to: futureDir.appendingPathComponent("memo.json"), atomically: false, encoding: .utf8)
            let future = MemoStore(directory: futureDir); let empty = future.load()
            try check(future.writeBlocked, "Future schema should be protected")
            var blocked = false; do { try future.save(empty) } catch { blocked = true }
            try check(blocked && (try String(contentsOf: future.filePath, encoding: .utf8)) == futureJson, "Future schema preservation")
            report.append("PASS: future data format preserved without overwrite")

            let badDir = sandbox.appendingPathComponent("bad"); try fm.createDirectory(at: badDir, withIntermediateDirectories: true)
            try "null".write(to: badDir.appendingPathComponent("memo.json"), atomically: false, encoding: .utf8)
            let bad = MemoStore(directory: badDir)
            try check(bad.load().tasks.isEmpty && !bad.writeBlocked && bad.loadMessage != nil, "Corrupt without backup")
            try check(files(badDir, { $0.hasPrefix("memo.unreadable-") }).count == 1, "Bad file preserved")
            report.append("PASS: damaged data without backup archived before starting empty")

            let invalidDir = sandbox.appendingPathComponent("invalid-version"); try fm.createDirectory(at: invalidDir, withIntermediateDirectories: true)
            try "{\"Version\":{},\"Tasks\":[]}".write(to: invalidDir.appendingPathComponent("memo.json"), atomically: false, encoding: .utf8)
            let invalid = MemoStore(directory: invalidDir)
            try check(invalid.load().tasks.isEmpty && !invalid.writeBlocked && invalid.loadMessage != nil, "Malformed schema recovery")
            report.append("PASS: malformed schema field recovered without startup crash")

            // macOS has no mandatory file locks; a read-only folder is the equivalent write failure.
            let lockedDir = sandbox.appendingPathComponent("locked"); try fm.createDirectory(at: lockedDir, withIntermediateDirectories: true)
            let lockedStore = MemoStore(directory: lockedDir); try lockedStore.save(state)
            let original = try String(contentsOf: lockedStore.filePath, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedDir.path)
            var failed = false; do { try lockedStore.save(MemoState()) } catch { failed = true }
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path)
            try check(failed && (try String(contentsOf: lockedStore.filePath, encoding: .utf8)) == original && files(lockedDir, { $0.hasSuffix(".tmp") }).isEmpty, "Locked file protection")
            report.append("PASS: write failure leaves saved contents intact and cleans temporary file")

            let a = TodoItem(text: "a"), b = TodoItem(text: "b", completed: true), c = TodoItem(text: "c", completed: true)
            var tasks = [a, b, c]; let history = TaskHistory()
            func same(_ x: [TodoItem], _ y: [TodoItem]) -> Bool { x.count == y.count && zip(x, y).allSatisfy { $0 === $1 } }
            history.delete(&tasks, [b, c]); try check(tasks.count == 1 && history.canUndo, "Batch delete")
            history.undo(&tasks); try check(same(tasks, [a, b, c]), "Undo restores indexes")
            tasks.insert(tasks.remove(at: 2), at: 0); try check(same(tasks, [c, a, b]), "Reorder")
            history.delete(&tasks, [a]); history.delete(&tasks, [b]); history.undo(&tasks); history.undo(&tasks)
            try check(same(tasks, [c, a, b]) && !history.canUndo, "Stacked undo")
            state.tasks = tasks; try store.save(state)
            try check(MemoStore(directory: sandbox).load().tasks.map { $0.text } == ["c", "a", "b"], "Order round-trip")
            report.append("PASS: batch delete, stacked undo, exact position restore and reordered persistence")
            return finish(0)
        } catch {
            report.append("FAIL: \(error.localizedDescription)")
            return finish(1)
        }
    }
}
