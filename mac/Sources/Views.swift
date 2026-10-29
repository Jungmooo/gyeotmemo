import AppKit

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Palette {
    static let background = NSColor(hex: 0xFAF9F6)
    static let ink = NSColor(hex: 0x272B28)
    static let green = NSColor(hex: 0x38634F)
    static let field = NSColor(hex: 0xFFFEFB)
    static let titleBar = NSColor(hex: 0xF0F1E9)
    static let titleLine = NSColor(hex: 0xE5E7DE)
    static let footer = NSColor(hex: 0xF1F3EB)
    static let footerLine = NSColor(hex: 0xE7EADF)
    static let hover = NSColor(hex: 0xE7EBE5)
    static let pressed = NSColor(hex: 0xD6E1D6)
    static let rowHover = NSColor(hex: 0xF0F1EA)
    static let rowSelected = NSColor(hex: 0xDCE4D8)
    static let rowFocused = NSColor(hex: 0xBED0BA)
    static let taskText = NSColor(hex: 0x363E34)
    static let taskDone = NSColor(hex: 0x949D8E)
    static let iconMuted = NSColor(hex: 0x929B8B)
    static let saveOK = NSColor(hex: 0x8D9881)
    static let saveWarn = NSColor(hex: 0xA46F3E)
    static let saveError = NSColor(hex: 0xAC5546)
    static let selection = NSColor(hex: 0xB8D4BE)
}

func label(_ text: String, size: CGFloat, color: NSColor, bold: Bool = false) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    field.textColor = color
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
}

func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: weight))
}

/// Borderless button with the rounded hover / pressed fill used throughout the Windows design.
final class FlatButton: NSButton {
    var baseColor: NSColor = .clear { didSet { refresh() } }
    var tint: NSColor = NSColor(hex: 0x727B73) { didSet { contentTintColor = tint; refresh() } }
    var padding = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8) { didSet { invalidateIntrinsicContentSize() } }
    var fontSize: CGFloat = 11 { didSet { refresh() } }
    private var hovering = false, pressing = false

    convenience init(title: String, image: NSImage? = nil, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title; self.image = image; self.target = target; self.action = action
        isBordered = false; bezelStyle = .regularSquare; focusRingType = .default
        imagePosition = image == nil ? .noImage : (title.isEmpty ? .imageOnly : .imageLeading)
        imageHugsTitle = true
        wantsLayer = true; layer?.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        contentTintColor = tint
        refresh()
    }

    func refresh() {
        layer?.backgroundColor = (pressing ? Palette.pressed : hovering ? Palette.hover : baseColor).cgColor
        if !title.isEmpty {
            attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: tint])
        }
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + padding.left + padding.right, height: size.height + padding.top + padding.bottom)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = isEnabled; refresh() }
    override func mouseExited(with event: NSEvent) { hovering = false; refresh() }
    override func mouseDown(with event: NSEvent) { pressing = true; refresh(); super.mouseDown(with: event); pressing = false; refresh() }
    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.35; if !isEnabled { hovering = false }; refresh() } }
}

/// Rounded check box drawn like the WPF template (19pt box, green fill when checked).
final class CheckBox: NSControl {
    var checked = false { didSet { needsDisplay = true; setAccessibilityValue(checked) } }
    private var hovering = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true); setAccessibilityRole(.checkBox); setAccessibilityLabel("완료 표시")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 21, height: 21) }
    override var acceptsFirstResponder: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: NSRect(x: 1.65, y: 1.65, width: 17.7, height: 17.7), xRadius: 6, yRadius: 6)
        box.lineWidth = 1.3
        (checked ? Palette.green : Palette.field).setFill(); box.fill()
        (checked || hovering ? Palette.green : NSColor(hex: 0xC4CCC1)).setStroke(); box.stroke()
        guard checked else { return }
        let tick = NSBezierPath()
        tick.move(to: NSPoint(x: 5.5, y: 21 - 10.5)); tick.line(to: NSPoint(x: 9, y: 21 - 14)); tick.line(to: NSPoint(x: 15.5, y: 21 - 6.5))
        tick.lineWidth = 1.8; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
        NSColor.white.setStroke(); tick.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        checked.toggle()
        sendAction(action, to: target)
    }
    override func accessibilityPerformPress() -> Bool { checked.toggle(); sendAction(action, to: target); return true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
}

final class ProgressLine: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 3) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: 0xE4E8DE).setFill(); bounds.fill()
        NSColor(hex: 0x7F9D74).setFill(); NSRect(x: 0, y: 0, width: bounds.width * CGFloat(max(0, min(1, value))), height: bounds.height).fill()
    }
}

/// Plain view with a solid fill, optional rounded corners and a hairline border.
final class Panel: NSView {
    init(fill: NSColor, border: NSColor? = nil, radius: CGFloat = 0, edges: NSRectEdge? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.fill = fill; self.border = border; self.radius = radius; self.edge = edges
    }
    required init?(coder: NSCoder) { fatalError() }
    private var fill: NSColor = .clear, border: NSColor?, radius: CGFloat = 0, edge: NSRectEdge?
    var draggable = false
    override var mouseDownCanMoveWindow: Bool { draggable }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill()
        guard let border = border else { return }
        border.setFill()
        switch edge {
        case .minY?: NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        case .maxY?: NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        default: border.setStroke(); path.lineWidth = 1; path.stroke()
        }
    }
}

/// Horizontal handle between the task list and the memo; reports vertical drags in points.
final class SplitHandle: NSView {
    var onDragBegan: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    private var start: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = "드래그하여 메모 영역 크기 조절"
        setAccessibilityElement(true); setAccessibilityRole(.splitter); setAccessibilityLabel("메모 영역 크기 조절")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: 0xE3E7DC).setFill(); NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1).fill()
        NSColor(hex: 0xCED6C5).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 14, y: bounds.midY - 1.5, width: 28, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    }
    override func mouseDown(with event: NSEvent) { start = event.locationInWindow.y; onDragBegan?() }
    override func mouseDragged(with event: NSEvent) { onDrag?(event.locationInWindow.y - start) }
    override func mouseUp(with event: NSEvent) { onDragEnded?() }
}

final class TaskRowView: NSTableRowView {
    var focused = false { didSet { needsDisplay = true } }
    private var hovering = false
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        if hovering { Palette.rowHover.setFill(); path.fill() }
        if isSelected || focused { (focused ? Palette.rowFocused : Palette.rowSelected).setStroke(); path.lineWidth = 1; path.stroke() }
    }
    override var isSelected: Bool { didSet { needsDisplay = true } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
}

final class TaskCellView: NSTableCellView {
    static let horizontalChrome: CGFloat = 1 + 16 + 33 + 4 + 25 + 25 + 3
    let handle = label("⠿", size: 14, color: NSColor(hex: 0xC1C8BB))
    let check = CheckBox()
    let title = NSTextField(wrappingLabelWithString: "")
    let edit: FlatButton
    let delete: FlatButton

    init(target: AnyObject) {
        edit = FlatButton(title: "", image: symbol("pencil", size: 11), target: target, action: #selector(MainController.editClicked(_:)))
        delete = FlatButton(title: "", image: symbol("xmark", size: 10), target: target, action: #selector(MainController.deleteClicked(_:)))
        super.init(frame: .zero)
        handle.toolTip = "드래그로 순서 변경 (⌥↑ / ↓)"
        check.target = target; check.action = #selector(MainController.checkClicked(_:))
        title.font = .systemFont(ofSize: 13)
        title.toolTip = "두 번 클릭하여 수정 (Return)"
        title.isSelectable = false
        title.focusRingType = .none
        title.cell?.wraps = true; title.cell?.isScrollable = false
        title.setAccessibilityLabel("할 일")
        for button in [edit, delete] { button.tint = Palette.iconMuted; button.padding = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
        edit.toolTip = "수정"; edit.setAccessibilityLabel("할 일 수정하기")
        delete.toolTip = "삭제 (아래 되돌리기로 복원)"; delete.setAccessibilityLabel("할 일 삭제")
        textField = title
        for view in [handle, check, title, edit, delete] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            handle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            handle.widthAnchor.constraint(equalToConstant: 16),
            handle.topAnchor.constraint(equalTo: topAnchor, constant: 9 + 3),
            check.leadingAnchor.constraint(equalTo: handle.trailingAnchor),
            check.topAnchor.constraint(equalTo: topAnchor, constant: 9 + 4),
            title.leadingAnchor.constraint(equalTo: check.leadingAnchor, constant: 33),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 9 + 5),
            title.trailingAnchor.constraint(equalTo: edit.leadingAnchor, constant: -4),
            edit.widthAnchor.constraint(equalToConstant: 25), edit.heightAnchor.constraint(equalToConstant: 28),
            edit.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            delete.leadingAnchor.constraint(equalTo: edit.trailingAnchor),
            delete.widthAnchor.constraint(equalToConstant: 25), delete.heightAnchor.constraint(equalToConstant: 28),
            delete.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            delete.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
        ])
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ item: TodoItem, editing: Bool) {
        check.checked = item.completed
        title.isEditable = editing; title.isSelectable = editing
        title.drawsBackground = editing; title.backgroundColor = Palette.field
        if editing {
            title.attributedStringValue = NSAttributedString(string: item.text)
            title.textColor = Palette.taskText; title.font = .systemFont(ofSize: 13)
        } else {
            var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: item.completed ? Palette.taskDone : Palette.taskText]
            if item.completed { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue; attributes[.strikethroughColor] = Palette.taskDone }
            title.attributedStringValue = NSAttributedString(string: item.text, attributes: attributes)
        }
    }

    private static let measure: NSTextField = {
        let field = NSTextField(wrappingLabelWithString: ""); field.font = .systemFont(ofSize: 13); return field
    }()
    static func height(for text: String, width: CGFloat) -> CGFloat {
        measure.stringValue = text.isEmpty ? " " : text
        let textWidth = max(40, width - horizontalChrome)
        let textHeight = measure.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: .greatestFiniteMagnitude)).height
        return ceil(max(28, textHeight + 5 + 3)) + 18
    }
}

/// Task list with the Windows keyboard model: Delete, Return/F2 to edit, ⌥↑/↓ to reorder, Space to complete.
final class TaskTableView: NSTableView {
    weak var controller: MainController?
    override func keyDown(with event: NSEvent) {
        let option = event.modifierFlags.contains(.option)
        switch event.keyCode {
        case 51, 117: controller?.deleteSelected()
        case 36, 76, 120: controller?.editSelected()
        case 49: controller?.toggleSelected()
        case 126 where option: controller?.moveSelected(by: -1)
        case 125 where option: controller?.moveSelected(by: 1)
        default: super.keyDown(with: event)
        }
    }
    override func becomeFirstResponder() -> Bool { let ok = super.becomeFirstResponder(); if ok { controller?.listFocusChanged(true) }; return ok }
    override func resignFirstResponder() -> Bool { let ok = super.resignFirstResponder(); if ok { controller?.listFocusChanged(false) }; return ok }
}

final class NoteTextView: NSTextView {
    let placeholder = label("자유롭게 적어 두세요…", size: 12, color: NSColor(hex: 0xABB2A3))
    func updatePlaceholder() { placeholder.isHidden = !string.isEmpty }
}

/// Window that routes ⌘Z to "삭제 되돌리기" whenever a text field is not handling it.
final class MemoWindow: NSWindow {
    weak var controller: MainController?
    @objc func undo(_ sender: Any?) { controller?.undoDelete() }
    @objc func redo(_ sender: Any?) {}
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undo(_:)) { return controller?.canUndoDelete ?? false }
        if menuItem.action == #selector(redo(_:)) { return false }
        return super.validateMenuItem(menuItem)
    }
}
