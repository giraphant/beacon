import BeaconCore
import SwiftUI

/// UI row for the symbol table. The rule cells keep the user's raw text —
/// parsing happens on serialize, so half-typed numbers don't get clobbered
/// mid-edit.
struct SymbolRow: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var inMenuBar: Bool
    var percentText: String
    var stepText: String

    init(entry: SymbolTableEntry = SymbolTableEntry(symbol: "")) {
        symbol = entry.symbol
        inMenuBar = entry.inMenuBar
        percentText = entry.alertPercent.flatMap(formatRuleValue) ?? ""
        stepText = entry.boundaryStep.flatMap(formatRuleValue) ?? ""
    }

    var entry: SymbolTableEntry {
        SymbolTableEntry(
            symbol: symbol, inMenuBar: inMenuBar,
            alertPercent: Self.parseRuleText(percentText),
            boundaryStep: Self.parseRuleText(stepText)
        )
    }

    static func parseRuleText(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value.isFinite, value > 0 else { return nil }
        return value
    }
}

/// The Symbols pane's table editor: column header, editable rows, an add
/// button and a footnote. Its own view (not a chunk of SettingsView) so the
/// offscreen render test exercises exactly what ships.
struct SymbolTableEditor: View {
    @Binding var rows: [SymbolRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Symbol").frame(maxWidth: .infinity, alignment: .leading)
                Text("Menu Bar").frame(width: 64)
                Text("Alert %").frame(width: 72)
                Text("Step").frame(width: 84)
                // ⊖ column spacer, bounded on BOTH axes — an unbounded child
                // here balloons the whole pane's ideal height into a blank
                // window (Color.clear and even a framed Spacer both do).
                Color.clear.frame(width: 20, height: 1)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)

            // No row selection: a selectable List swallows the first click,
            // so the text fields would never get focus and the table reads as
            // display-only. Rows delete via their own ⊖ instead.
            List {
                ForEach($rows) { $row in
                    HStack(spacing: 8) {
                        TextField("Symbol", text: $row.symbol, prompt: Text("SYMBOL"))
                            .textFieldStyle(.plain)
                            .frame(maxWidth: .infinity)
                        Toggle("In menu bar", isOn: $row.inMenuBar)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .frame(width: 64)
                        ruleField("Alert %", text: $row.percentText, width: 72)
                        ruleField("Step", text: $row.stepText, width: 84)
                        Button {
                            rows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .frame(width: 20)
                    }
                }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            // Fixed, not row-count-based: a height that moves with every
            // add/remove changes the pane's ideal size, and the hosting view
            // chases that by resizing (and so moving) the window.
            .frame(height: 300)

            Button {
                rows.append(SymbolRow())
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)

            // No `.fixedSize(horizontal: false, vertical: true)` here: during
            // the window's ideal-size probe the proposal is unbounded, and
            // fixedSize turns this text into a ~1500pt-tall column that the
            // window then grows to fit (the "blank pane" bug).
            Text("Checked symbols cycle through the menu-bar title; unchecked ones only appear in the dropdown. Drag rows to reorder. Alert % notifies when the price moves that percent since the last alert, Step when it crosses a multiple of that step — leave a cell empty for no alert.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// A rule cell: free text, red while it holds something that isn't a
    /// positive number (which serializes as "no rule").
    private func ruleField(_ title: String, text: Binding<String>, width: CGFloat) -> some View {
        let invalid = SymbolRow.parseRuleText(text.wrappedValue) == nil
            && !text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
        return TextField(title, text: text, prompt: Text("—"))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(invalid ? Color.red : Color.primary)
            .frame(width: width)
    }
}
