import AppKit
import SnapshotTesting
import SwiftUI

/// Shared helpers for snapshotting SwiftUI views in macOS tests.
enum SnapshotTestHelper {
    /// Default content width simulating a typical Mactrix window.
    static let defaultWidth: CGFloat = 600

    /// Renders a SwiftUI view into an NSView suitable for snapshot assertion.
    @MainActor
    static func hostView(_ view: some View, width: CGFloat = defaultWidth, height: CGFloat? = nil) -> NSView {
        let sized: AnyView
        if let height {
            sized = AnyView(view.frame(width: width, height: height))
        } else {
            sized = AnyView(view.frame(width: width).fixedSize(horizontal: false, vertical: true))
        }
        let hosting = NSHostingView(rootView: sized)
        hosting.frame.size = hosting.fittingSize
        return hosting
    }

    /// Asserts a snapshot with a perceptual precision tolerance for cross-machine rendering differences.
    @MainActor
    static func assertViewSnapshot(
        _ view: some View,
        named name: String? = nil,
        width: CGFloat = defaultWidth,
        height: CGFloat? = nil,
        record: SnapshotTestingConfiguration.Record = .missing,
        precision: Float = 0.99,
        perceptualPrecision: Float = 0.98,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let nsView = hostView(view, width: width, height: height)
        withSnapshotTesting(record: record) {
            assertSnapshot(
                of: nsView,
                as: .image(precision: precision, perceptualPrecision: perceptualPrecision),
                named: name,
                file: file,
                testName: testName,
                line: line
            )
        }
    }
}
