import AppKit

private let taskPasteboardType = NSPasteboard.PasteboardType("kr.gyeotmemo.task-row")

final class MainController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let window: MemoWindow
    let store: MemoStore
    private let saved: MemoState
    private(set) var tasks: [TodoItem] = []
    private let history = TaskHistory()
    private var saveTimer: Timer?, dateTimer: Timer?
    private var ready = false, dirty = false
    private var editItem: TodoItem?, editOriginal = ""
    private var saveError: String?

    private let input = NSTextField()
    private let note = NoteTextView()
    let table = TaskTableView()
    private let dateLabel = label("", size: 11, color: NSColor(hex: 0x7C8579))
    private let countLabel = label("0 / 0", size: 11, color: Palette.green, bold: true)
    private let progress = ProgressLine()
    private let remainingLabel = label("", size: 10, color: NSColor(hex: 0x949C8D))
    let saveLabel = label("자동 저장", size: 10, color: Palette.saveOK)
    private let emptyState = NSStackView()
    private let pinButton = FlatButton(title: "고정", image: symbol("pin.fill", size: 10), target: nil, action: nil)
    private var addButton: FlatButton!, clearButton: FlatButton!, undoButton: FlatButton!
    private let lowerArea = NSView()
    let notePane = NSView()
    let handle = SplitHandle()
    private var noteHeight: NSLayoutConstraint!
    private var dragStartHeight: CGFloat = 0

    static let minNote: CGFloat = 82, minList: CGFloat = 89, handleHeight: CGFloat = 10

    init(store: MemoStore) {
        self.store = store
        saved = store.load()
        window = MemoWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 650),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.controller = self
        window.title = "곁메모"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Palette.background
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let toolbar = NSToolbar(identifier: "GyeotMemoToolbar")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly; toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 330, height: 490)
        buildLayout()

        input.stringValue = saved.draft
        note.string = saved.note
        tasks = saved.tasks
        table.reloadData()
        let width = clamp(saved.width, 330, 1200, 380), height = clamp(saved.height, 490, 1600, 650)
        noteHeight.constant = CGFloat(clamp(saved.noteHeight, Double(Self.minNote), height, 136))
        var frame = NSRect(x: 0, y: 0, width: width, height: height)
        let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? area.maxY
        // Left/Top keep the Windows meaning: top-left corner, y measured downward from the primary screen's top.
        if let left = saved.left, let top = saved.top, left.isFinite, top.isFinite {
            frame.origin = NSPoint(x: left, y: Double(primaryTop) - top - height)
        } else {
            frame.origin = NSPoint(x: max(area.minX, area.maxX - frame.width - 28), y: area.maxY - 45 - frame.height)
        }
        window.setFrame(frame, display: false)
        ensureVisible()
        window.level = saved.pinned ? .floating : .normal

        updateCounts(); updatePin(); updatePlaceholders(); updateDate()
        if store.writeBlocked {
            input.isEditable = false; note.isEditable = false; table.isEnabled = false
            addButton.isEnabled = false; clearButton.isEnabled = false
        }
        if store.loadMessage != nil {
            saveLabel.stringValue = store.writeBlocked ? "저장 중단 · 파일 확인 필요" : "메모 복원됨 · 안내 확인"
            saveLabel.textColor = Palette.saveWarn
        }
        saveLabel.toolTip = (store.loadMessage ?? "자동으로 이 Mac에 저장합니다.") + "\n" + store.filePath.path
        dateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.updateDate() }
        ready = true
        if !FileManager.default.fileExists(atPath: store.filePath.path) && !store.writeBlocked { queueSave() }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded(); table.sizeLastColumnToFit()
        (window.fieldEditor(true, for: input) as? NSTextView)?.insertionPointColor = Palette.green
        window.makeFirstResponder(input)
        input.currentEditor()?.selectedRange = NSRange(location: (input.stringValue as NSString).length, length: 0)
    }

    // MARK: Layout

    private func buildLayout() {
        let root = window.contentView!
        let header = Panel(fill: Palette.titleBar, border: Palette.titleLine, edges: .minY)
        header.draggable = true
        let footer = Panel(fill: Palette.footer, border: Palette.footerLine, edges: .maxY)
        let content = NSView(); content.translatesAutoresizingMaskIntoConstraints = false
        [header, content, footer].forEach(root.addSubview)
        let guide = window.contentLayoutGuide as! NSLayoutGuide
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor), header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor), header.bottomAnchor.constraint(equalTo: guide.topAnchor),
            content.topAnchor.constraint(equalTo: guide.topAnchor, constant: 21),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor), footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 32),
        ])

        // Logo and name sit in the drawn header (after the traffic lights) rather than in the toolbar,
        // so the system never wraps them in a toolbar-item background.
        let logo = Panel(fill: Palette.green, radius: 5)
        let tick = NSImageView(image: symbol("checkmark", size: 10, weight: .bold) ?? NSImage()); tick.contentTintColor = .white
        tick.translatesAutoresizingMaskIntoConstraints = false; logo.addSubview(tick)
        let name = label("곁메모", size: 13, color: Palette.ink, bold: true)
        [logo, name].forEach(header.addSubview)
        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 92), logo.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 22), logo.heightAnchor.constraint(equalToConstant: 25),
            tick.centerXAnchor.constraint(equalTo: logo.centerXAnchor), tick.centerYAnchor.constraint(equalTo: logo.centerYAnchor),
            name.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 9), name.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        let heading = label("오늘의 할 일", size: 23, color: Palette.ink, bold: true)
        let badge = Panel(fill: NSColor(hex: 0xEAF0E5), radius: 10)
        badge.addSubview(countLabel)
        NSLayoutConstraint.activate([
            countLabel.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 8), countLabel.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -8),
            countLabel.topAnchor.constraint(equalTo: badge.topAnchor, constant: 4), countLabel.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -4),
        ])
        progress.translatesAutoresizingMaskIntoConstraints = false

        let inputBox = Panel(fill: Palette.field, border: NSColor(hex: 0xD6DECE), radius: 10)
        input.translatesAutoresizingMaskIntoConstraints = false
        input.isBordered = false; input.drawsBackground = false; input.focusRingType = .none
        input.font = .systemFont(ofSize: 13); input.textColor = Palette.ink
        input.cell?.isScrollable = true; input.cell?.wraps = false; input.lineBreakMode = .byClipping
        input.placeholderAttributedString = NSAttributedString(string: "할 일을 적고 Return", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(hex: 0x9AA092)])
        input.delegate = self
        input.setAccessibilityLabel("새 할 일")
        addButton = FlatButton(title: "", image: symbol("plus", size: 15, weight: .medium), target: self, action: #selector(addClicked))
        addButton.tint = Palette.green; addButton.padding = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        addButton.toolTip = "할 일 추가 (Return)"; addButton.setAccessibilityLabel("할 일 추가")
        inputBox.addSubview(input); inputBox.addSubview(addButton)
        NSLayoutConstraint.activate([
            input.leadingAnchor.constraint(equalTo: inputBox.leadingAnchor, constant: 12), input.centerYAnchor.constraint(equalTo: inputBox.centerYAnchor),
            input.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -4),
            addButton.trailingAnchor.constraint(equalTo: inputBox.trailingAnchor, constant: -6), addButton.centerYAnchor.constraint(equalTo: inputBox.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 32), addButton.heightAnchor.constraint(equalToConstant: 30),
            inputBox.heightAnchor.constraint(equalToConstant: 44),
        ])

        lowerArea.translatesAutoresizingMaskIntoConstraints = false
        [dateLabel, heading, badge, progress, inputBox, lowerArea].forEach(content.addSubview)
        NSLayoutConstraint.activate([
            dateLabel.topAnchor.constraint(equalTo: content.topAnchor), dateLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            heading.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 5), heading.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            badge.centerYAnchor.constraint(equalTo: heading.centerYAnchor), badge.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            progress.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            progress.leadingAnchor.constraint(equalTo: content.leadingAnchor), progress.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 3),
            inputBox.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 18),
            inputBox.leadingAnchor.constraint(equalTo: content.leadingAnchor), inputBox.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            lowerArea.topAnchor.constraint(equalTo: inputBox.bottomAnchor, constant: 13),
            lowerArea.leadingAnchor.constraint(equalTo: content.leadingAnchor), lowerArea.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            lowerArea.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Task list pane + memo pane share lowerArea; the handle moves space directly between them.
        let listPane = NSView(); listPane.translatesAutoresizingMaskIntoConstraints = false
        notePane.translatesAutoresizingMaskIntoConstraints = false
        [listPane, handle, notePane].forEach(lowerArea.addSubview)
        noteHeight = notePane.heightAnchor.constraint(equalToConstant: 136)
        // Both stay below windowSizeStayPut (500) so a tall memo can never hold the window open;
        // the list minimum wins over the requested memo height when space runs out.
        noteHeight.priority = NSLayoutConstraint.Priority(490)
        let listMin = listPane.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minList)
        listMin.priority = NSLayoutConstraint.Priority(495)
        NSLayoutConstraint.activate([
            listPane.topAnchor.constraint(equalTo: lowerArea.topAnchor), listPane.leadingAnchor.constraint(equalTo: lowerArea.leadingAnchor),
            listPane.trailingAnchor.constraint(equalTo: lowerArea.trailingAnchor), listMin,
            handle.topAnchor.constraint(equalTo: listPane.bottomAnchor), handle.heightAnchor.constraint(equalToConstant: Self.handleHeight),
            handle.leadingAnchor.constraint(equalTo: lowerArea.leadingAnchor), handle.trailingAnchor.constraint(equalTo: lowerArea.trailingAnchor),
            notePane.topAnchor.constraint(equalTo: handle.bottomAnchor), notePane.bottomAnchor.constraint(equalTo: lowerArea.bottomAnchor),
            notePane.leadingAnchor.constraint(equalTo: lowerArea.leadingAnchor), notePane.trailingAnchor.constraint(equalTo: lowerArea.trailingAnchor),
            notePane.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minNote), noteHeight,
        ])
        handle.onDragBegan = { [weak self] in guard let self = self else { return }; self.endEdit(cancel: false); self.dragStartHeight = self.notePane.frame.height }
        handle.onDrag = { [weak self] delta in self?.setNoteHeight((self?.dragStartHeight ?? 0) + delta) }
        handle.onDragEnded = { [weak self] in self?.queueSave() }

        let scroll = NSScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task")); column.resizingMask = .autoresizingMask
        column.width = 340
        table.addTableColumn(column)
        table.controller = self
        table.headerView = nil; table.style = .plain; table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 6); table.selectionHighlightStyle = .regular
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.focusRingType = .none; table.allowsEmptySelection = true
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(tableDoubleClicked)
        table.registerForDraggedTypes([taskPasteboardType])
        table.draggingDestinationFeedbackStyle = .gap
        table.setAccessibilityLabel("할 일 목록")
        scroll.documentView = table

        emptyState.orientation = .vertical; emptyState.alignment = .centerX; emptyState.spacing = 0
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        let emptyIcon = NSImageView(image: symbol("checkmark", size: 18, weight: .semibold) ?? NSImage())
        emptyIcon.contentTintColor = NSColor(hex: 0xA5B79A)
        let emptyBox = Panel(fill: NSColor(hex: 0xEEF1E7), radius: 10); emptyBox.addSubview(emptyIcon)
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyBox.widthAnchor.constraint(equalToConstant: 44), emptyBox.heightAnchor.constraint(equalToConstant: 48),
            emptyIcon.centerXAnchor.constraint(equalTo: emptyBox.centerXAnchor), emptyIcon.centerYAnchor.constraint(equalTo: emptyBox.centerYAnchor),
        ])
        let emptyTitle = label("가볍게 하나부터 시작해요", size: 12, color: NSColor(hex: 0x858F7D))
        let emptyHint = label("오늘 기억할 일을 위에 적어 주세요.", size: 10, color: NSColor(hex: 0xA3AA9C))
        [emptyBox, emptyTitle, emptyHint].forEach(emptyState.addArrangedSubview)
        emptyState.setCustomSpacing(12, after: emptyBox); emptyState.setCustomSpacing(5, after: emptyTitle)

        clearButton = FlatButton(title: "완료 정리", target: self, action: #selector(clearCompleted))
        clearButton.fontSize = 10; clearButton.padding = NSEdgeInsets(top: 3, left: 5, bottom: 3, right: 5)
        clearButton.toolTip = "완료한 항목을 정리합니다. 되돌리기로 복원할 수 있습니다."
        [scroll, emptyState, remainingLabel, clearButton].forEach(listPane.addSubview)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: listPane.topAnchor), scroll.leadingAnchor.constraint(equalTo: listPane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: listPane.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: listPane.bottomAnchor, constant: -25),
            emptyState.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), emptyState.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            remainingLabel.leadingAnchor.constraint(equalTo: listPane.leadingAnchor), remainingLabel.centerYAnchor.constraint(equalTo: listPane.bottomAnchor, constant: -12.5),
            clearButton.trailingAnchor.constraint(equalTo: listPane.trailingAnchor), clearButton.centerYAnchor.constraint(equalTo: remainingLabel.centerYAnchor),
        ])

        let noteTitle = label("메모", size: 11, color: NSColor(hex: 0x6F7B65), bold: true)
        let noteHint = label("생각을 잠깐 놓아두는 곳", size: 10, color: NSColor(hex: 0xA4AC9C))
        let noteScroll = NSScrollView(); noteScroll.translatesAutoresizingMaskIntoConstraints = false
        noteScroll.drawsBackground = false; noteScroll.hasVerticalScroller = true; noteScroll.autohidesScrollers = true; noteScroll.borderType = .noBorder
        note.isRichText = false; note.allowsUndo = true; note.drawsBackground = false
        note.font = .systemFont(ofSize: 12); note.textColor = Palette.ink; note.insertionPointColor = Palette.green
        note.selectedTextAttributes = [.backgroundColor: Palette.selection]
        note.textContainerInset = NSSize(width: 0, height: 4); note.textContainer?.lineFragmentPadding = 0
        note.isAutomaticQuoteSubstitutionEnabled = false; note.isAutomaticDashSubstitutionEnabled = false
        note.isAutomaticTextReplacementEnabled = false; note.isAutomaticSpellingCorrectionEnabled = false
        note.isVerticallyResizable = true; note.autoresizingMask = [.width]
        note.textContainer?.widthTracksTextView = true
        note.delegate = self
        note.setAccessibilityLabel("자유 메모")
        noteScroll.documentView = note
        [noteTitle, noteHint, noteScroll, note.placeholder].forEach(notePane.addSubview)
        NSLayoutConstraint.activate([
            noteTitle.topAnchor.constraint(equalTo: notePane.topAnchor, constant: 8 + 4), noteTitle.leadingAnchor.constraint(equalTo: notePane.leadingAnchor),
            noteHint.firstBaselineAnchor.constraint(equalTo: noteTitle.firstBaselineAnchor), noteHint.leadingAnchor.constraint(equalTo: noteTitle.trailingAnchor, constant: 8),
            noteScroll.topAnchor.constraint(equalTo: notePane.topAnchor, constant: 8 + 24),
            noteScroll.leadingAnchor.constraint(equalTo: notePane.leadingAnchor), noteScroll.trailingAnchor.constraint(equalTo: notePane.trailingAnchor),
            noteScroll.bottomAnchor.constraint(equalTo: notePane.bottomAnchor, constant: -7),
            note.placeholder.topAnchor.constraint(equalTo: noteScroll.topAnchor, constant: 4), note.placeholder.leadingAnchor.constraint(equalTo: noteScroll.leadingAnchor),
        ])

        undoButton = FlatButton(title: "삭제 되돌리기", target: self, action: #selector(undoClicked))
        undoButton.fontSize = 10; undoButton.padding = NSEdgeInsets(top: 2, left: 5, bottom: 2, right: 5)
        undoButton.toolTip = "마지막 삭제 되돌리기 (목록에서 ⌘Z)"
        saveLabel.lineBreakMode = .byTruncatingTail
        [saveLabel, undoButton].forEach(footer.addSubview)
        NSLayoutConstraint.activate([
            saveLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 20), saveLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            undoButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -17), undoButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            saveLabel.trailingAnchor.constraint(lessThanOrEqualTo: undoButton.leadingAnchor, constant: -8),
        ])

        pinButton.target = self; pinButton.action = #selector(togglePin)
        pinButton.padding = NSEdgeInsets(top: 5, left: 9, bottom: 5, right: 9)
        pinButton.toolTip = "항상 위 고정 켜기 / 끄기 (⇧⌘P)"
    }

    // MARK: Toolbar (title bar contents)

    private let pinItem = NSToolbarItem.Identifier("pin")
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, pinItem] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, pinItem] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.view = pinButton; item.label = "고정"
        return item
    }

    // MARK: State helpers

    private func clamp(_ value: Double, _ low: Double, _ high: Double, _ fallback: Double) -> Double {
        value.isFinite ? max(low, min(max(low, high), value)) : fallback
    }

    /// Largest memo height that still leaves the list, its footer row and the handle inside lowerArea.
    var maxNoteHeight: CGFloat { max(Self.minNote, lowerArea.frame.height - Self.handleHeight - Self.minList) }

    func setNoteHeight(_ value: CGFloat) {
        noteHeight.constant = max(Self.minNote, min(maxNoteHeight, value))
        window.contentView?.layoutSubtreeIfNeeded()
        queueSave()
    }

    private func ensureVisible() {
        let frame = window.frame
        let title = NSRect(x: frame.minX, y: frame.maxY - 48, width: frame.width, height: 48)
        let visible = NSScreen.screens.contains { screen in
            let overlap = title.intersection(screen.visibleFrame)
            return !overlap.isNull && overlap.width >= 100 && overlap.height >= 28
        }
        if !visible, let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: max(area.minX, area.maxX - frame.width - 28), y: area.maxY - 32 - frame.height))
        }
    }

    private func updateDate() {
        let format = DateFormatter(); format.locale = Locale(identifier: "ko_KR"); format.dateFormat = "M월 d일 EEEE"
        dateLabel.stringValue = format.string(from: Date())
    }
    private func updatePlaceholders() { note.updatePlaceholder() }
    private var pinned: Bool { window.level == .floating }
    private func updatePin() {
        pinButton.baseColor = NSColor(hex: pinned ? 0xDDE8D6 : 0xE5E8E0)
        pinButton.tint = NSColor(hex: pinned ? 0x38634F : 0x8D9585)
        pinButton.image = symbol(pinned ? "pin.fill" : "pin.slash", size: 10)
        pinButton.title = pinned ? "고정" : "해제"
        pinButton.refresh()
        pinButton.setAccessibilityLabel(pinned ? "항상 위 고정 켜짐" : "항상 위 고정 꺼짐")
    }
    @objc func togglePin() { window.level = pinned ? .normal : .floating; updatePin(); queueSave() }

    private func updateCounts() {
        let done = tasks.filter { $0.completed }.count, total = tasks.count
        countLabel.stringValue = "\(done) / \(total)"
        progress.value = total == 0 ? 0 : Double(done) / Double(total)
        emptyState.isHidden = total != 0
        remainingLabel.stringValue = total == 0 ? "적는 순간, 조금 더 가벼워져요" : (done == total ? "오늘 적은 일을 모두 마쳤어요" : "\(total - done)개의 할 일이 남았어요")
        clearButton.isEnabled = done > 0 && !store.writeBlocked
        undoButton.isHidden = !history.canUndo
    }

    private func tasksChanged(reload: Bool = true) {
        if reload { table.reloadData() }
        updateCounts(); queueSave()
    }

    // MARK: Actions

    @objc func addClicked() { addTask() }
    func addTask() {
        endEdit(cancel: false)
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { window.makeFirstResponder(input); return }
        let task = TodoItem(text: text)
        tasks.append(task)
        input.stringValue = ""
        tasksChanged()
        table.scrollRowToVisible(tasks.count - 1)
        window.makeFirstResponder(input)
    }
    @objc func focusInput() { window.makeFirstResponder(input) }
    @objc func clearCompleted() {
        endEdit(cancel: false)
        history.delete(&tasks, tasks.filter { $0.completed })
        tasksChanged()
    }
    @objc func undoClicked() { undoDelete() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undoClicked)?: return canUndoDelete
        case #selector(clearCompleted)?: return clearButton.isEnabled
        case #selector(focusInput)?: return !store.writeBlocked
        case #selector(togglePin)?: menuItem.state = pinned ? .on : .off; return true
        default: return true
        }
    }
    var canUndoDelete: Bool { history.canUndo && !store.writeBlocked }
    func undoDelete() { endEdit(cancel: false); if history.undo(&tasks) { tasksChanged() } }

    private func item(for sender: NSView) -> TodoItem? {
        let row = table.row(for: sender)
        return row >= 0 && row < tasks.count ? tasks[row] : nil
    }
    @objc func checkClicked(_ sender: CheckBox) {
        guard let task = item(for: sender) else { return }
        task.completed = sender.checked
        reloadRow(task); updateCounts(); queueSave()
    }
    @objc func editClicked(_ sender: NSButton) { beginEdit(item(for: sender)) }
    @objc func deleteClicked(_ sender: NSButton) {
        guard let task = item(for: sender) else { return }
        endEdit(cancel: false); delete(task)
    }
    @objc func tableDoubleClicked() {
        let row = table.clickedRow
        guard row >= 0, row < tasks.count, let event = window.currentEvent,
              let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? TaskCellView else { return }
        let point = cell.convert(event.locationInWindow, from: nil)
        if cell.title.frame.insetBy(dx: -2, dy: -4).contains(point) { beginEdit(tasks[row]) }
    }

    private func delete(_ task: TodoItem) {
        let row = tasks.firstIndex { $0 === task } ?? 0
        history.delete(&tasks, [task])
        tasksChanged()
        if !tasks.isEmpty, window.firstResponder === table { table.selectRowIndexes([min(row, tasks.count - 1)], byExtendingSelection: false) }
    }
    private var selected: TodoItem? { table.selectedRow >= 0 && table.selectedRow < tasks.count ? tasks[table.selectedRow] : nil }
    func deleteSelected() { if let task = selected { delete(task) } }
    func editSelected() { beginEdit(selected) }
    func toggleSelected() { guard let task = selected else { return }; task.completed.toggle(); reloadRow(task); updateCounts(); queueSave() }
    func moveSelected(by offset: Int) {
        let index = table.selectedRow, target = index + offset
        guard index >= 0, target >= 0, target < tasks.count else { return }
        tasks.insert(tasks.remove(at: index), at: target)
        table.moveRow(at: index, to: target)
        table.selectRowIndexes([target], byExtendingSelection: false); table.scrollRowToVisible(target)
        queueSave()
    }
    func listFocusChanged(_ focused: Bool) {
        for row in 0..<table.numberOfRows {
            (table.rowView(atRow: row, makeIfNecessary: false) as? TaskRowView)?.focused = focused && row == table.selectedRow
        }
    }

    private func reloadRow(_ task: TodoItem) {
        guard let row = tasks.firstIndex(where: { $0 === task }) else { return }
        table.reloadData(forRowIndexes: [row], columnIndexes: [0])
        table.noteHeightOfRows(withIndexesChanged: [row])
    }

    // MARK: Inline editing

    func beginEdit(_ item: TodoItem?) {
        guard let item = item, !store.writeBlocked, let row = tasks.firstIndex(where: { $0 === item }) else { return }
        endEdit(cancel: false)
        editItem = item; editOriginal = item.text
        table.selectRowIndexes([row], byExtendingSelection: false); table.scrollRowToVisible(row)
        reloadRow(item)
        guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? TaskCellView else { return }
        cell.title.delegate = self
        window.makeFirstResponder(cell.title)
        cell.title.currentEditor()?.selectAll(nil)
    }

    func endEdit(cancel: Bool) {
        guard let item = editItem else { return }
        editItem = nil
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        item.text = cancel || text.isEmpty ? editOriginal : text
        if let row = tasks.firstIndex(where: { $0 === item }),
           let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? TaskCellView, cell.title.currentEditor() != nil {
            window.makeFirstResponder(table)
        }
        reloadRow(item); queueSave()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === input {
            if (input.stringValue as NSString).length > 4000 { input.stringValue = String(input.stringValue.prefix(4000)) }
            queueSave()
        } else if let item = editItem {
            if (field.stringValue as NSString).length > 4000 { field.stringValue = String(field.stringValue.prefix(4000)) }
            item.text = field.stringValue
            if let row = tasks.firstIndex(where: { $0 === item }) { table.noteHeightOfRows(withIndexesChanged: [row]) }
            queueSave()
        }
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
        (notification.userInfo?["NSFieldEditor"] as? NSTextView)?.insertionPointColor = Palette.green
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        if (notification.object as? NSTextField) !== input { endEdit(cancel: false) }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        if control === input {
            if command == #selector(NSResponder.insertNewline(_:)) { addTask(); return true }
            return false
        }
        if command == #selector(NSResponder.insertNewline(_:)) { endEdit(cancel: false); return true }
        if command == #selector(NSResponder.cancelOperation(_:)) { endEdit(cancel: true); return true }
        return false
    }

    func textDidChange(_ notification: Notification) { updatePlaceholders(); queueSave() }
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        (textView.string as NSString).length - range.length + ((text ?? "") as NSString).length <= 200_000
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { tasks.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("TaskCell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? TaskCellView ?? {
            let cell = TaskCellView(target: self); cell.identifier = id; return cell
        }()
        cell.show(tasks[row], editing: tasks[row] === editItem)
        cell.title.delegate = self
        return cell
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { TaskRowView() }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        TaskCellView.height(for: tasks[row].text, width: tableView.bounds.width)
    }
    func tableViewColumnDidResize(_ notification: Notification) {
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<tasks.count))
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        if let item = editItem, selected !== item { endEdit(cancel: false) }
        listFocusChanged(window.firstResponder === table)
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard !store.writeBlocked, editItem == nil else { return nil }
        let item = NSPasteboardItem(); item.setString(String(row), forType: taskPasteboardType); return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === table else { return [] }
        if op == .on { tableView.setDropRow(row, dropOperation: .above) }
        return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let value = info.draggingPasteboard.pasteboardItems?.first?.string(forType: taskPasteboardType), let from = Int(value), from < tasks.count else { return false }
        let to = from < row ? row - 1 : row
        guard to != from, to >= 0, to < tasks.count else { return false }
        tasks.insert(tasks.remove(at: from), at: to)
        table.moveRow(at: from, to: to)
        table.selectRowIndexes([to], byExtendingSelection: false)
        queueSave()
        return true
    }

    // MARK: Saving

    func queueSave() {
        guard ready, !store.writeBlocked else { return }
        dirty = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in _ = self?.saveNow() }
        if saveError == nil { saveLabel.stringValue = "저장 중…" }
    }

    @discardableResult
    func saveNow() -> Bool {
        guard ready, dirty else { return true }
        saveTimer?.invalidate(); saveTimer = nil
        saved.tasks = tasks; saved.note = note.string; saved.draft = input.stringValue; saved.pinned = pinned
        if !window.isMiniaturized && !window.styleMask.contains(.fullScreen) {
            let frame = window.frame, primaryTop = NSScreen.screens.first?.frame.maxY ?? frame.maxY
            saved.left = Double(frame.minX); saved.top = Double(primaryTop - frame.maxY)
            saved.width = Double(frame.width); saved.height = Double(frame.height)
        }
        saved.noteHeight = Double(notePane.frame.height > 0 ? notePane.frame.height : noteHeight.constant)
        do {
            try store.save(saved)
            dirty = false; saveError = nil
            let time = DateFormatter(); time.dateFormat = "HH:mm"
            saveLabel.stringValue = "자동 저장됨 · " + time.string(from: Date())
            saveLabel.textColor = Palette.saveOK
            saveLabel.toolTip = (store.loadMessage ?? "이 Mac에 자동 저장했습니다.") + "\n" + store.filePath.path
            return true
        } catch {
            saveError = error.localizedDescription
            saveLabel.stringValue = "저장 실패 · 안내 확인"; saveLabel.textColor = Palette.saveError
            saveLabel.toolTip = "저장 폴더가 쓰기 가능한지 확인해 주세요.\n" + store.filePath.path + "\n" + error.localizedDescription
            return false
        }
    }

    /// Preserve unsaved work on I/O errors; an untouched future-format file can close safely.
    func canClose() -> Bool {
        endEdit(cancel: false)
        if dirty && !saveNow() {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "메모를 저장하지 못했습니다"
            alert.informativeText = "창을 열어 두었습니다.\n저장 폴더의 권한이나 파일 상태를 확인한 뒤 다시 닫아 주세요.\n\n" + (saveError ?? "")
            alert.addButton(withTitle: "확인")
            alert.beginSheetModal(for: window)
            return false
        }
        saveTimer?.invalidate(); dateTimer?.invalidate()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { canClose() }
    func windowDidMove(_ notification: Notification) { queueSave() }
    func windowDidResize(_ notification: Notification) { queueSave() }
}
