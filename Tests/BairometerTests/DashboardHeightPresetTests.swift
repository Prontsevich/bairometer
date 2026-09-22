import XCTest
@testable import Bairometer

final class DashboardHeightPresetTests: XCTestCase {
    func testPresetsUseStableStorageValuesAndViewportHeights() {
        XCTAssertEqual(DashboardHeightPreset.storageKey, "dashboard-height-preset")
        XCTAssertEqual(DashboardHeightPreset.compact.rawValue, "compact")
        XCTAssertEqual(DashboardHeightPreset.standard.rawValue, "standard")
        XCTAssertEqual(DashboardHeightPreset.tall.rawValue, "tall")

        XCTAssertEqual(DashboardHeightPreset.compact.viewportHeight, 320)
        XCTAssertEqual(DashboardHeightPreset.standard.viewportHeight, 460)
        XCTAssertEqual(DashboardHeightPreset.tall.viewportHeight, 640)
    }
}
