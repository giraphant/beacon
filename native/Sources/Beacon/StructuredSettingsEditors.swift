import AppKit
import BeaconCore
import SwiftUI
import UniformTypeIdentifiers

struct SymbolSettingsEditorRow: Identifiable, Equatable {
    let id: UUID
    var symbol: String
    var displayMode: SymbolDisplayMode
    var percentText: String
    var stepText: String

    init(
        id: UUID = UUID(),
        entry: SymbolSettingsEntry = SymbolSettingsEntry(symbol: "")
    ) {
        self.id = id
        symbol = entry.symbol
        displayMode = entry.displayMode
        percentText = entry.alertPercent.flatMap(formatPreferenceNumber) ?? ""
        stepText = entry.boundaryStep.flatMap(formatPreferenceNumber) ?? ""
    }

    var entry: SymbolSettingsEntry? {
        guard let symbol = normalizePreferenceSymbol(symbol) else { return nil }
        return SymbolSettingsEntry(
            symbol: symbol,
            displayMode: displayMode,
            alertPercent: positiveNumber(percentText),
            boundaryStep: positiveNumber(stepText)
        )
    }

    var isEmpty: Bool {
        symbol.trimmingCharacters(in: .whitespaces).isEmpty
            && percentText.trimmingCharacters(in: .whitespaces).isEmpty
            && stepText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var hasAlert: Bool {
        positiveNumber(percentText) != nil || positiveNumber(stepText) != nil
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .circular))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .circular)
                .stroke(.quaternary)
        }
    }
}

/// A compact layout editor. Less frequently changed settings appear in a
/// popover anchored to the selected symbol, keeping the arrangement visible on
/// short laptop displays.
struct SymbolSettingsEditor: View {
    @Binding var rows: [SymbolSettingsEditorRow]
    @FocusState private var focusedSymbolID: UUID?
    @State private var selectedRowID: UUID?
    @State private var hoveredRowID: UUID?
    @State private var draggedRowID: UUID?
    @State private var dropTargetID: UUID?
    @State private var activeDropMode: SymbolDisplayMode?

    private var duplicateSymbols: Set<String> {
        duplicates(rows.compactMap { normalizePreferenceSymbol($0.symbol) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsCard {
                VStack(spacing: 0) {
                    ForEach(SymbolDisplayMode.allCases, id: \.self) { mode in
                        symbolLane(mode)
                        if mode != SymbolDisplayMode.allCases.last {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }

                    Divider()

                    HStack {
                        Button {
                            addSymbol()
                        } label: {
                            Label("Add Symbol", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)

                        Spacer()

                        Text(symbolCountLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                }
            }

            Text("Drag handles to arrange symbols. Click a symbol to edit its alert rules.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
        }
        .onChange(of: rows.map(\.id)) { _, ids in
            if let selectedRowID, !ids.contains(selectedRowID) {
                self.selectedRowID = nil
            }
        }
    }

    private var symbolCountLabel: String {
        rows.count == 1 ? "1 symbol" : "\(rows.count) symbols"
    }

    private func symbolLane(_ mode: SymbolDisplayMode) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: mode.settingsIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(mode.settingsTitle)
                    .fontWeight(.medium)
                Spacer()
                Text(mode.laneDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                let laneRows = rows.filter { $0.displayMode == mode }
                if laneRows.isEmpty {
                    Text(activeDropMode == mode ? "Release to move here" : "Drop symbols here")
                        .font(.caption)
                        .foregroundStyle(activeDropMode == mode ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
                } else {
                    SymbolFlowLayout(spacing: 7) {
                        ForEach(laneRows) { row in
                            symbolChip(row)
                        }
                    }
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .circular)
                    .fill(activeDropMode == mode ? Color.accentColor.opacity(0.08) : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .circular)
                            .stroke(
                                activeDropMode == mode
                                    ? Color.accentColor.opacity(0.6)
                                    : Color(nsColor: .separatorColor).opacity(0.7),
                                style: StrokeStyle(
                                    lineWidth: activeDropMode == mode ? 1.5 : 1,
                                    dash: laneRowsAreEmpty(mode) ? [4] : []
                                )
                            )
                    }
            }
            .onDrop(
                of: [UTType.plainText],
                delegate: SymbolLaneDropDelegate(
                    mode: mode,
                    rows: $rows,
                    draggedRowID: $draggedRowID,
                    dropTargetID: $dropTargetID,
                    activeDropMode: $activeDropMode
                )
            )
        }
        .padding(12)
    }

    private func laneRowsAreEmpty(_ mode: SymbolDisplayMode) -> Bool {
        !rows.contains { $0.displayMode == mode }
    }

    private func symbolChip(_ row: SymbolSettingsEditorRow) -> some View {
        let selected = selectedRowID == row.id
        let hovered = hoveredRowID == row.id
        let isDropTarget = dropTargetID == row.id
        let title = normalizePreferenceSymbol(row.symbol) ?? "New Symbol"

        return HStack(spacing: 6) {
            ZStack {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : .secondary)

                SymbolDragHandle(
                    symbolID: row.id,
                    onDragBegan: {
                        selectedRowID = nil
                        draggedRowID = row.id
                    },
                    onDragEnded: {
                        if draggedRowID == row.id {
                            draggedRowID = nil
                        }
                        dropTargetID = nil
                        activeDropMode = nil
                    }
                )
            }
            .frame(width: 18, height: 28)
            .help("Drag to reorder")

            Button {
                selectedRowID = selected ? nil : row.id
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .fontWeight(.medium)
                    if row.hasAlert {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(selected ? Color.white.opacity(0.9) : .secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .frame(height: 28)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .circular)
                .fill(chipBackground(selected: selected, hovered: hovered))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .circular)
                        .stroke(
                            isDropTarget ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isDropTarget ? 2 : 0.5
                        )
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .circular))
        .opacity(draggedRowID == row.id && activeDropMode != nil ? 0.35 : 1)
        .onHover { hovering in
            hoveredRowID = hovering ? row.id : (hoveredRowID == row.id ? nil : hoveredRowID)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: SymbolChipDropDelegate(
                targetID: row.id,
                targetMode: row.displayMode,
                rows: $rows,
                draggedRowID: $draggedRowID,
                dropTargetID: $dropTargetID,
                activeDropMode: $activeDropMode
            )
        )
        .popover(
            isPresented: inspectorPresentedBinding(for: row.id),
            arrowEdge: .bottom
        ) {
            symbolInspector(for: row.id)
        }
        .help(row.displayMode.settingsHelp)
        .contextMenu {
            ForEach(SymbolDisplayMode.allCases, id: \.self) { mode in
                Button {
                    move(row.id, to: mode)
                } label: {
                    if row.displayMode == mode {
                        Label(mode.settingsTitle, systemImage: "checkmark")
                    } else {
                        Text(mode.settingsTitle)
                    }
                }
            }

            Divider()

            Button("Remove Symbol", role: .destructive) {
                remove(row.id)
            }
        }
    }

    private func chipBackground(selected: Bool, hovered: Bool) -> Color {
        if selected {
            return .accentColor
        }
        if hovered {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.16)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    @ViewBuilder
    private func symbolInspector(for id: UUID) -> some View {
        if let row = binding(for: id) {
            let value = row.wrappedValue
            let errors = validationMessages(for: value)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("New Symbol", text: row.symbol)
                            .font(.headline)
                            .textFieldStyle(.plain)
                            .focused($focusedSymbolID, equals: value.id)
                            .onSubmit {
                                if let normalized = normalizePreferenceSymbol(row.wrappedValue.symbol) {
                                    row.wrappedValue.symbol = normalized
                                }
                            }
                        Text("Alert rules")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        selectedRowID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Close")

                    Button(role: .destructive) {
                        remove(value.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove symbol")
                }
                .padding(12)

                Divider()
                    .padding(.leading, 12)

                inspectorRow("Movement alert", description: "Notify after this change from the last alert") {
                    HStack(spacing: 5) {
                        TextField("Off", text: row.percentText)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 82)
                        Text("%")
                            .foregroundStyle(.secondary)
                            .frame(width: 12, alignment: .leading)
                    }
                }

                Divider()
                    .padding(.leading, 12)

                inspectorRow("Price-level alert", description: "Notify when price crosses each interval") {
                    HStack(spacing: 5) {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Off", text: row.stepText)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 96)
                    }
                }

                if !errors.isEmpty {
                    Divider()
                        .padding(.leading, 12)

                    Label(errors.joined(separator: " "), systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(12)
                }
            }
            .frame(width: 390)
        }
    }

    private func inspectorRow<Content: View>(
        _ title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content()
                .layoutPriority(1)
        }
        .padding(12)
    }

    private func inspectorPresentedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                selectedRowID == id && draggedRowID == nil
            },
            set: { presented in
                if !presented, selectedRowID == id {
                    selectedRowID = nil
                }
            }
        )
    }

    private func binding(for id: UUID) -> Binding<SymbolSettingsEditorRow>? {
        guard rows.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                rows.first(where: { $0.id == id })
                    ?? SymbolSettingsEditorRow(id: id)
            },
            set: { updated in
                guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
                rows[index] = updated
            }
        )
    }

    private func addSymbol() {
        let row = SymbolSettingsEditorRow()
        _ = insertSymbolRow(&rows, row, into: .menuBar)
        selectedRowID = row.id
        DispatchQueue.main.async {
            focusedSymbolID = row.id
        }
    }

    private func remove(_ id: UUID) {
        guard rows.contains(where: { $0.id == id }) else { return }
        if selectedRowID == id {
            selectedRowID = nil
        }
        rows.removeAll { $0.id == id }
    }

    private func move(_ id: UUID, to mode: SymbolDisplayMode) {
        withAnimation(.easeInOut(duration: 0.16)) {
            _ = moveSymbolRow(&rows, draggedID: id, over: nil, into: mode)
        }
    }

    private func validationMessages(for row: SymbolSettingsEditorRow) -> [String] {
        var messages: [String] = []
        let normalized = normalizePreferenceSymbol(row.symbol)
        if normalized == nil {
            messages.append("Enter a valid symbol.")
        } else if normalized.map(duplicateSymbols.contains) == true {
            messages.append("Each symbol must be unique.")
        }
        if invalidNumber(row.percentText) {
            messages.append("Movement alert must be greater than zero.")
        }
        if invalidNumber(row.stepText) {
            messages.append("Price-level alert must be greater than zero.")
        }
        if row.displayMode == .alertsOnly && !row.hasAlert {
            messages.append("Alerts Only needs at least one alert rule.")
        }
        return messages
    }
}

private struct SymbolDragHandle: NSViewRepresentable {
    let symbolID: UUID
    let onDragBegan: () -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> SymbolDragHandleView {
        SymbolDragHandleView()
    }

    func updateNSView(_ nsView: SymbolDragHandleView, context: Context) {
        nsView.symbolID = symbolID
        nsView.onDragBegan = onDragBegan
        nsView.onDragEnded = onDragEnded
    }
}

/// AppKit owns the dragging session so its end callback is delivered even when
/// the drop lands on a nested SwiftUI target, is rejected, or is cancelled.
/// SwiftUI's `onDrag` has no equivalent source-side completion callback.
final class SymbolDragHandleView: NSView, NSDraggingSource {
    var symbolID = UUID()
    var onDragBegan: () -> Void = {}
    var onDragEnded: () -> Void = {}

    private var mouseDownLocation: CGPoint?
    private var startedDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        startedDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !startedDragging, let mouseDownLocation else { return }
        let location = convert(event.locationInWindow, from: nil)
        guard hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y) >= 3 else {
            return
        }

        startedDragging = true
        let pasteboardItem = NSPasteboardItem()
        let pasteboardType = NSPasteboard.PasteboardType(UTType.plainText.identifier)
        pasteboardItem.setString(symbolID.uuidString, forType: pasteboardType)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
        draggingItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !startedDragging {
            mouseDownLocation = nil
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        session.animatesToStartingPositionsOnCancelOrFail = true
        onDragBegan()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        mouseDownLocation = nil
        startedDragging = false
        onDragEnded()
    }
}

/// A compact wrapping layout for symbols. Ice's layout bar scrolls on one
/// horizontal line because it mirrors the real macOS menu bar; Beacon symbols
/// are longer, so they flow onto additional lines at the available pane width.
private struct SymbolFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
            ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }
        let result = layout(subviews: subviews, availableWidth: availableWidth)
        return CGSize(width: proposal.width ?? result.width, height: result.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(subviews: subviews, availableWidth: bounds.width)
        for (index, origin) in result.origins.enumerated() {
            let size = result.sizes[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
        }
    }

    private func layout(
        subviews: Subviews,
        availableWidth: CGFloat
    ) -> (origins: [CGPoint], sizes: [CGSize], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > availableWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }

            origins.append(cursor)
            sizes.append(size)
            usedWidth = max(usedWidth, cursor.x + size.width)
            rowHeight = max(rowHeight, size.height)
            cursor.x += size.width + spacing
        }

        return (origins, sizes, usedWidth, cursor.y + rowHeight)
    }
}

private struct SymbolChipDropDelegate: DropDelegate {
    let targetID: UUID
    let targetMode: SymbolDisplayMode
    @Binding var rows: [SymbolSettingsEditorRow]
    @Binding var draggedRowID: UUID?
    @Binding var dropTargetID: UUID?
    @Binding var activeDropMode: SymbolDisplayMode?

    func validateDrop(info: DropInfo) -> Bool {
        guard let draggedRowID else { return false }
        return draggedRowID != targetID && rows.contains { $0.id == draggedRowID }
    }

    func dropEntered(info: DropInfo) {
        guard let draggedRowID, validateDrop(info: info) else { return }
        dropTargetID = targetID
        activeDropMode = targetMode
        withAnimation(.easeInOut(duration: 0.16)) {
            _ = moveSymbolRow(
                &rows,
                draggedID: draggedRowID,
                over: targetID,
                into: targetMode
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .cancel)
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetID {
            dropTargetID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let accepted = draggedRowID != nil
        draggedRowID = nil
        dropTargetID = nil
        activeDropMode = nil
        return accepted
    }
}

private struct SymbolLaneDropDelegate: DropDelegate {
    let mode: SymbolDisplayMode
    @Binding var rows: [SymbolSettingsEditorRow]
    @Binding var draggedRowID: UUID?
    @Binding var dropTargetID: UUID?
    @Binding var activeDropMode: SymbolDisplayMode?

    func validateDrop(info: DropInfo) -> Bool {
        guard let draggedRowID else { return false }
        // Accept same-lane background drops too, so `performDrop` always gets
        // the chance to clear the visual drag state. It intentionally does not
        // move those symbols; in-lane reordering only happens over another chip.
        return rows.contains { $0.id == draggedRowID }
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        activeDropMode = mode
        dropTargetID = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .cancel)
    }

    func dropExited(info: DropInfo) {
        if activeDropMode == mode {
            activeDropMode = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedRowID, validateDrop(info: info) else {
            self.draggedRowID = nil
            dropTargetID = nil
            activeDropMode = nil
            return false
        }
        if rows.first(where: { $0.id == draggedRowID })?.displayMode != mode {
            withAnimation(.easeInOut(duration: 0.16)) {
                _ = moveSymbolRow(&rows, draggedID: draggedRowID, over: nil, into: mode)
            }
        }
        self.draggedRowID = nil
        dropTargetID = nil
        activeDropMode = nil
        return true
    }
}

@discardableResult
func moveSymbolRow(
    _ rows: inout [SymbolSettingsEditorRow],
    draggedID: UUID,
    over targetID: UUID?,
    into mode: SymbolDisplayMode
) -> Bool {
    guard let sourceIndex = rows.firstIndex(where: { $0.id == draggedID }) else {
        return false
    }

    if let targetID {
        guard draggedID != targetID,
              let originalTargetIndex = rows.firstIndex(where: { $0.id == targetID })
        else { return false }

        let sourceMode = rows[sourceIndex].displayMode
        var row = rows.remove(at: sourceIndex)
        row.displayMode = mode
        guard let targetIndex = rows.firstIndex(where: { $0.id == targetID }) else {
            rows.insert(row, at: min(sourceIndex, rows.endIndex))
            return false
        }
        let movingForwardInSameLane =
            sourceMode == mode && sourceIndex < originalTargetIndex
        rows.insert(row, at: movingForwardInSameLane ? targetIndex + 1 : targetIndex)
        return true
    }

    guard rows[sourceIndex].displayMode != mode else {
        return false
    }
    var row = rows.remove(at: sourceIndex)
    row.displayMode = mode
    _ = insertSymbolRow(&rows, row, into: mode)
    return true
}

@discardableResult
func insertSymbolRow(
    _ rows: inout [SymbolSettingsEditorRow],
    _ row: SymbolSettingsEditorRow,
    into mode: SymbolDisplayMode
) -> Int {
    var row = row
    row.displayMode = mode

    let insertionIndex: Int
    switch mode {
    case .menuBar:
        insertionIndex = rows.firstIndex { $0.displayMode != .menuBar } ?? rows.endIndex
    case .dropdown:
        insertionIndex = rows.firstIndex { $0.displayMode == .alertsOnly } ?? rows.endIndex
    case .alertsOnly:
        insertionIndex = rows.endIndex
    }
    rows.insert(row, at: insertionIndex)
    return insertionIndex
}

private extension SymbolDisplayMode {
    var settingsTitle: String {
        switch self {
        case .menuBar: "Menu Bar"
        case .dropdown: "List Only"
        case .alertsOnly: "Alerts Only"
        }
    }

    var settingsIcon: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .dropdown: "list.bullet"
        case .alertsOnly: "bell"
        }
    }

    var laneDescription: String {
        switch self {
        case .menuBar: "Rotates in the menu-bar title"
        case .dropdown: "Only in the price list"
        case .alertsOnly: "Hidden from the price list"
        }
    }

    var settingsHelp: String {
        switch self {
        case .menuBar: "Show in the price list and rotate through the menu-bar title."
        case .dropdown: "Show in the price list without using the menu-bar title."
        case .alertsOnly: "Fetch only for alerts; do not show in the price list."
        }
    }
}

private func positiveNumber(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let value = Double(trimmed), formatPreferenceNumber(value) != nil else { return nil }
    return value
}

private func invalidNumber(_ text: String) -> Bool {
    !text.trimmingCharacters(in: .whitespaces).isEmpty && positiveNumber(text) == nil
}

private func duplicates(_ values: [String]) -> Set<String> {
    var seen = Set<String>()
    var result = Set<String>()
    for value in values where !seen.insert(value).inserted {
        result.insert(value)
    }
    return result
}
