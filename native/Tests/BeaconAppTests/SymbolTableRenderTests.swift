import AppKit
import BeaconCore
import SwiftUI
import XCTest

@testable import Beacon

/// Offscreen render harness for the Settings symbol table. Regressions this
/// guards against are the ones that shipped: a List that renders zero rows,
/// and layout that shoves the table outside the visible pane.
@MainActor
final class SymbolTableRenderTests: XCTestCase {
    func testEditorRendersAllRowsInsideThePane() throws {
        var rows = [
            SymbolRow(entry: SymbolTableEntry(symbol: "BTC", inMenuBar: true, alertPercent: 1, boundaryStep: 1000)),
            SymbolRow(entry: SymbolTableEntry(symbol: "ETH", inMenuBar: true)),
            SymbolRow(entry: SymbolTableEntry(symbol: "NVDA", inMenuBar: false, alertPercent: 2.5)),
        ]
        let host = NSHostingView(rootView: SymbolTableEditor(rows: Binding(
            get: { rows }, set: { rows = $0 }
        )).padding(20))
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 520)

        // A real (never-shown) window: NSTableView won't build rows without a
        // window backing it.
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        // The regression that shipped as a "blank pane": one unbounded child
        // balloons the hosting view's ideal height, the window stretches, and
        // the visible viewport shows only empty canvas.
        XCTAssertLessThanOrEqual(
            host.bounds.height, 600,
            "editor's ideal height ballooned — some child has unbounded height"
        )

        let table = try XCTUnwrap(firstTableView(in: host), "the bordered List lost its NSTableView")
        XCTAssertEqual(table.numberOfRows, rows.count, "List renders no/wrong rows")

        let tableFrame = table.convert(table.bounds, to: host)
        XCTAssertTrue(
            host.bounds.intersects(tableFrame),
            "table sits outside the pane: \(tableFrame) vs \(host.bounds)"
        )
        XCTAssertGreaterThan(tableFrame.height, 100, "table collapsed: \(tableFrame)")

        // PNG for eyeballing after any UI change: /tmp/beacon-symbol-table.png
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/beacon-symbol-table.png"))

        // Objective presence check, band by band: every part of the editor —
        // header labels, table, add button, caption — must have put ink on
        // its stripe of the canvas. Eyeballing PNGs misses faint or missing
        // text; counting non-background pixels doesn't.
        let bands: [(name: String, y: ClosedRange<CGFloat>)] = [
            ("header", 0...40),
            ("table", 60...340),
            ("footer (+ / caption)", (host.bounds.height - 70)...(host.bounds.height - 4)),
        ]
        for band in bands {
            var inked = 0
            for y in stride(from: band.y.lowerBound, to: band.y.upperBound, by: 2) {
                for x in stride(from: CGFloat(0), to: host.bounds.width, by: 4) {
                    guard let color = rep.colorAt(
                        x: Int(x * rep.size.width / host.bounds.width * CGFloat(rep.pixelsWide) / rep.size.width),
                        y: Int(y * CGFloat(rep.pixelsHigh) / host.bounds.height)
                    ) else { continue }
                    if color.brightnessComponent < 0.85 { inked += 1 }
                }
            }
            print("BAND \(band.name): inked=\(inked)")
            XCTAssertGreaterThan(inked, 20, "band '\(band.name)' rendered nothing")
        }
    }

    private func firstTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews {
            if let table = firstTableView(in: subview) { return table }
        }
        return nil
    }
}
