import XCTest
@testable import Bairometer

final class AboutInformationTests: XCTestCase {
    func testReleaseBuildInformationDisplaysVersionAndBuildNumber() {
        let information = AboutBuildInformation(
            shortVersion: "1.2.3",
            buildNumber: "45"
        )

        XCTAssertEqual(information.displayText, "Version 1.2.3 (build 45)")
    }

    func testDevelopmentBuildInformationIsUsedWhenReleaseMetadataIsIncomplete() {
        XCTAssertEqual(
            AboutBuildInformation(shortVersion: nil, buildNumber: nil).displayText,
            AboutBuildInformation.developmentText
        )
        XCTAssertEqual(
            AboutBuildInformation(shortVersion: "1.2.3", buildNumber: nil).displayText,
            AboutBuildInformation.developmentText
        )
        XCTAssertEqual(
            AboutBuildInformation(shortVersion: " ", buildNumber: "45").displayText,
            AboutBuildInformation.developmentText
        )
    }

    func testExternalLinksUseTheCanonicalProjectDestinations() {
        XCTAssertEqual(
            AboutLinks.github.absoluteString,
            "https://github.com/Prontsevich/bairometer"
        )
        XCTAssertEqual(
            AboutLinks.issue.absoluteString,
            "https://github.com/Prontsevich/bairometer/issues/new"
        )
        XCTAssertEqual(
            AboutLinks.email.absoluteString,
            "mailto:prontsevich@gmail.com"
        )
        XCTAssertEqual(
            AboutLinks.telegram.absoluteString,
            "https://t.me/s_prontsevich"
        )
        XCTAssertEqual(
            AboutLinks.boosty.absoluteString,
            "https://boosty.to/sergey.pro"
        )
    }
}
