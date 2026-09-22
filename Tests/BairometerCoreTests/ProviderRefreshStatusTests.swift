import XCTest
@testable import BairometerCore

final class ProviderRefreshStatusTests: XCTestCase {
    func testDisplayNames() {
        XCTAssertEqual(ProviderRefreshStatus.idle.displayName, "Idle")
        XCTAssertEqual(ProviderRefreshStatus.refreshing.displayName, "Refreshing")
        XCTAssertEqual(ProviderRefreshStatus.succeeded(Date(timeIntervalSince1970: 1)).displayName, "Updated")
        XCTAssertEqual(ProviderRefreshStatus.failed(Date(timeIntervalSince1970: 1)).displayName, "Failed")
    }
}
