import Foundation

final class TodoItem {
    var id: String
    var text: String
    var completed: Bool
    init(text: String, completed: Bool = false, id: String = TodoItem.newId()) { self.id = id; self.text = text; self.completed = completed }
    static func newId() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
}

struct StorageError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// Same schema as the Windows build (PascalCase keys, Version 1), so memo.json moves between both.
final class MemoState {
    var version = 1
    var tasks: [TodoItem] = []
    var note = ""
    var draft = ""
    var pinned = true
    var width: Double = 380
    var height: Double = 650
    var left: Double?
    var top: Double?
    var noteHeight: Double = 136

    init() {}

    init(json root: [String: Any]) throws {
        func number(_ key: String) throws -> Double? {
            guard let value = root[key], !(value is NSNull) else { return nil }
            guard let n = value as? NSNumber, !MemoState.isBool(n) else { throw StorageError("\(key) 값이 올바르지 않습니다.") }
            return n.doubleValue
        }
        func string(_ key: String) throws -> String? {
            guard let value = root[key], !(value is NSNull) else { return nil }
            guard let s = value as? String else { throw StorageError("\(key) 값이 올바르지 않습니다.") }
            return s
        }
        guard let list = root["Tasks"] as? [Any] else { throw StorageError("할 일 목록을 읽지 못했습니다.") }
        var ids = Set<String>()
        for entry in list {
            guard let task = entry as? [String: Any], let text = task["Text"] as? String else { throw StorageError("잘못된 할 일입니다.") }
            var completed = false
            if let value = task["Completed"], !(value is NSNull) {
                guard let n = value as? NSNumber, MemoState.isBool(n) else { throw StorageError("잘못된 완료 상태입니다.") }
                completed = n.boolValue
            }
            var id = task["Id"] as? String ?? ""
            if id.isEmpty || ids.contains(id) { id = TodoItem.newId() }
            ids.insert(id)
            tasks.append(TodoItem(text: text, completed: completed, id: id))
        }
        note = try string("Note") ?? ""
        draft = try string("Draft") ?? ""
        if let value = root["Pinned"], !(value is NSNull) {
            guard let n = value as? NSNumber, MemoState.isBool(n) else { throw StorageError("Pinned 값이 올바르지 않습니다.") }
            pinned = n.boolValue
        }
        width = try number("Width") ?? width
        height = try number("Height") ?? height
        left = try number("Left")
        top = try number("Top")
        noteHeight = try number("NoteHeight") ?? noteHeight
    }

    func json() -> [String: Any] {
        [
            "Version": version,
            "Tasks": tasks.map { ["Id": $0.id, "Text": $0.text, "Completed": $0.completed] as [String: Any] },
            "Note": note, "Draft": draft, "Pinned": pinned,
            "Width": width, "Height": height,
            "Left": left.map { $0 as Any } ?? NSNull(), "Top": top.map { $0 as Any } ?? NSNull(),
            "NoteHeight": noteHeight,
        ]
    }

    static func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }
    static func versionOf(_ root: [String: Any]?) -> Int? {
        guard let n = root?["Version"] as? NSNumber, !isBool(n), n.doubleValue == n.doubleValue.rounded(), abs(n.doubleValue) < 1e9 else { return nil }
        return n.intValue
    }
}

final class MemoStore {
    let directory: URL
    var filePath: URL { directory.appendingPathComponent("memo.json") }
    var backupPath: URL { directory.appendingPathComponent("memo.backup.json") }
    private(set) var loadMessage: String?
    private(set) var writeBlocked = false
    private let files = FileManager.default

    init(directory: URL) { self.directory = directory }

    private func root(_ url: URL) throws -> [String: Any]? {
        let data = try Data(contentsOf: url)
        if data.count > 8 * 1024 * 1024 { throw StorageError("저장 파일이 너무 큽니다.") }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any]
    }

    private func read(_ url: URL) throws -> MemoState {
        // Reject missing schema and future formats instead of silently replacing them.
        guard let root = try root(url), MemoState.versionOf(root) == 1, root["Tasks"] != nil else { throw StorageError("지원하지 않는 저장 형식입니다.") }
        return try MemoState(json: root)
    }

    func load() -> MemoState {
        loadMessage = nil; writeBlocked = false
        if !files.fileExists(atPath: filePath.path) {
            if files.fileExists(atPath: backupPath.path) {
                do { let backup = try read(backupPath); loadMessage = "백업에서 메모를 복원했습니다."; return backup }
                catch { writeBlocked = true; loadMessage = "백업을 읽지 못했습니다. 원본 파일을 확인해 주세요." }
            }
            return MemoState()
        }
        do { return try read(filePath) }
        catch {
            // A future schema must never be downgraded by this version.
            if let version = MemoState.versionOf(try? root(filePath)), version > 1 {
                writeBlocked = true; loadMessage = "더 새로운 버전의 메모입니다. 저장을 중단했습니다."; return MemoState()
            }
            do {
                try files.createDirectory(at: directory, withIntermediateDirectories: true)
                let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyyMMdd-HHmmss-SSS"
                let archive = directory.appendingPathComponent("memo.unreadable-\(stamp.string(from: Date()))-\(TodoItem.newId().prefix(6)).json")
                try files.copyItem(at: filePath, to: archive)
            } catch {
                writeBlocked = true; loadMessage = "저장 파일을 읽거나 보관하지 못했습니다. 원본 파일을 확인해 주세요."; return MemoState()
            }
            if let backup = try? read(backupPath) { loadMessage = "백업에서 복원했습니다. 읽지 못한 원본도 보관했습니다."; return backup }
            loadMessage = "읽지 못한 원본을 보관하고 새 메모를 열었습니다."
            return MemoState()
        }
    }

    func save(_ state: MemoState) throws {
        if writeBlocked { throw StorageError(loadMessage ?? "저장이 차단되었습니다.") }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("memo.\(TodoItem.newId()).tmp")
        defer { try? files.removeItem(at: temporary) }
        let data = try JSONSerialization.data(withJSONObject: state.json(), options: [.sortedKeys])
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        if fd < 0 { throw posixError("임시 파일을 만들지 못했습니다") }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        let synced = fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0
        close(fd)
        if written != data.count || !synced { throw posixError("임시 파일에 쓰지 못했습니다") }
        if files.fileExists(atPath: filePath.path) {
            // Keep the previous file as the backup, then swap the new file in atomically.
            unlink(backupPath.path)
            if link(filePath.path, backupPath.path) != 0 { throw posixError("백업을 만들지 못했습니다") }
        }
        if rename(temporary.path, filePath.path) != 0 { throw posixError("저장 파일을 교체하지 못했습니다") }
    }

    private func posixError(_ message: String) -> StorageError { StorageError("\(message): \(String(cString: strerror(errno)))") }
}

final class TaskHistory {
    private var deletions: [[(item: TodoItem, index: Int)]] = []
    var canUndo: Bool { !deletions.isEmpty }

    func delete(_ tasks: inout [TodoItem], _ items: [TodoItem]) {
        var batch: [(item: TodoItem, index: Int)] = []
        for item in items { if let index = tasks.firstIndex(where: { $0 === item }) { batch.append((item, index)) } }
        batch.sort { $0.index < $1.index }
        for removed in batch { tasks.removeAll { $0 === removed.item } }
        if !batch.isEmpty { deletions.append(batch) }
    }

    @discardableResult
    func undo(_ tasks: inout [TodoItem]) -> Bool {
        guard let batch = deletions.popLast() else { return false }
        for removed in batch where !tasks.contains(where: { $0 === removed.item }) { tasks.insert(removed.item, at: min(removed.index, tasks.count)) }
        return true
    }
}
