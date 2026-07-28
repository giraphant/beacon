import AppKit
import BeaconCore
import SwiftUI
import XCTest

@testable import Beacon

/// Guards the layout regression that forced the first structured-settings
/// implementation to be reverted: an NSTableView-backed List could render no
/// rows or make the settings window chase an unbounded ideal size.
@MainActor
final class StructuredSettingsRenderTests: XCTestCase {
    private var retainedWindows: [NSWindow] = []

    func testLayoutEditorRendersEveryDragHandleWithoutAnEmbeddedInspector() throws {
        let entries = [
            SymbolSettingsEntry(
                symbol: "BTC", displayMode: .menuBar,
                alertPercent: 1, boundaryStep: 1000
            ),
            SymbolSettingsEntry(symbol: "NVDA", displayMode: .dropdown),
            SymbolSettingsEntry(symbol: "SOL", displayMode: .alertsOnly, alertPercent: 2.5),
        ]
        let rows = entries.map { SymbolSettingsEditorRow(entry: $0) }
        let host = render(
            UnifiedEditorFixture(rows: rows),
            size: NSSize(width: 620, height: 460)
        )

        XCTAssertNil(firstSubview(of: NSTableView.self, in: host))
        XCTAssertEqual(
            allSubviews(of: SymbolDragHandleView.self, in: host).count,
            rows.count,
            "every symbol should use the AppKit drag source with a guaranteed end callback"
        )
        XCTAssertEqual(
            allSubviews(of: NSTextField.self, in: host).count,
            0,
            "symbol fields should live in a popover rather than extending the settings page"
        )
        XCTAssertLessThanOrEqual(host.fittingSize.height, 500)
        try writePNG(host, to: "/tmp/beacon-unified-settings.png")
    }

    func testManySymbolsWrapInsideANarrowSettingsPane() throws {
        let symbols = [
            "BTC", "HYPE", "QQQ", "NVDA", "GOOGL", "AAPL",
            "HOOD", "JUP", "XPL", "ETH", "SOL",
        ]
        let rows = symbols.enumerated().map { index, symbol in
            SymbolSettingsEditorRow(
                entry: SymbolSettingsEntry(
                    symbol: symbol,
                    displayMode: index == 0 ? .menuBar : .dropdown,
                    alertPercent: index.isMultiple(of: 2) ? 1 : nil
                )
            )
        }
        let host = render(
            UnifiedEditorFixture(rows: rows),
            size: NSSize(width: 560, height: 560)
        )

        XCTAssertNil(firstSubview(of: NSTableView.self, in: host))
        XCTAssertNil(firstSubview(of: NSScrollView.self, in: host))
        XCTAssertLessThanOrEqual(host.fittingSize.width, 560)
        try writePNG(host, to: "/tmp/beacon-wrapping-settings.png")
    }

    func testEditorRowRoundTripsAllSettingsForOneSymbol() {
        let entry = SymbolSettingsEntry(
            symbol: "JUP",
            displayMode: .alertsOnly,
            alertPercent: 3.5,
            boundaryStep: 0.05
        )
        XCTAssertEqual(SymbolSettingsEditorRow(entry: entry).entry, entry)
    }

    func testDragReordersWithinAndAcrossDisplayGroups() {
        let btc = SymbolSettingsEditorRow(entry: SymbolSettingsEntry(symbol: "BTC"))
        let eth = SymbolSettingsEditorRow(entry: SymbolSettingsEntry(symbol: "ETH"))
        let sol = SymbolSettingsEditorRow(entry: SymbolSettingsEntry(symbol: "SOL"))
        let nvda = SymbolSettingsEditorRow(
            entry: SymbolSettingsEntry(symbol: "NVDA", displayMode: .dropdown)
        )
        var rows = [btc, eth, sol, nvda]

        XCTAssertTrue(moveSymbolRow(
            &rows,
            draggedID: btc.id,
            over: sol.id,
            into: .menuBar
        ))
        XCTAssertEqual(rows.map(\.symbol), ["ETH", "SOL", "BTC", "NVDA"])

        XCTAssertTrue(moveSymbolRow(
            &rows,
            draggedID: btc.id,
            over: nvda.id,
            into: .dropdown
        ))
        XCTAssertEqual(rows.map(\.symbol), ["ETH", "SOL", "BTC", "NVDA"])
        XCTAssertEqual(rows.first(where: { $0.id == btc.id })?.displayMode, .dropdown)

        XCTAssertTrue(moveSymbolRow(
            &rows,
            draggedID: eth.id,
            over: nil,
            into: .alertsOnly
        ))
        XCTAssertEqual(rows.map(\.symbol), ["SOL", "BTC", "NVDA", "ETH"])
        XCTAssertEqual(rows.last?.displayMode, .alertsOnly)
    }

    func testDroppingOnSameLaneBackgroundDoesNotMoveSymbolToEnd() {
        let rows = ["QQQ", "NVDA", "GOOGL", "AAPL", "HOOD"].map {
            SymbolSettingsEditorRow(
                entry: SymbolSettingsEntry(symbol: $0, displayMode: .dropdown)
            )
        }
        var editedRows = rows
        let appleID = rows[3].id

        XCTAssertFalse(moveSymbolRow(
            &editedRows,
            draggedID: appleID,
            over: nil,
            into: .dropdown
        ))
        XCTAssertEqual(editedRows.map(\.symbol), ["QQQ", "NVDA", "GOOGL", "AAPL", "HOOD"])
    }

    private func render<V: View>(_ view: V, size: NSSize) -> NSHostingView<AnyView> {
        let fixedRoot = AnyView(
            view.frame(
                width: size.width,
                height: size.height,
                alignment: .topLeading
            )
        )
        let host = NSHostingView(rootView: fixedRoot)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        retainedWindows.append(window)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return host
    }

    private func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = firstSubview(of: type, in: child) { return match }
        }
        return nil
    }

    private func allSubviews<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
        var matches = view as? T == nil ? [] : [view as! T]
        for child in view.subviews {
            matches.append(contentsOf: allSubviews(of: type, in: child))
        }
        return matches
    }

    private func writePNG<V: View>(_ host: NSHostingView<V>, to path: String) throws {
        let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
    }
}

private struct UnifiedEditorFixture: View {
    @State var rows: [SymbolSettingsEditorRow]

    var body: some View {
        SymbolSettingsEditor(rows: $rows)
            .padding(24)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
