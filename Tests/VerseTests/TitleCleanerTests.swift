import XCTest
@testable import Verse

final class TitleCleanerTests: XCTestCase {
    func testStripsFeatParenthetical() {
        XCTAssertEqual(TitleCleaner.clean("Like Him (feat. Lola Young)"), "Like Him")
        XCTAssertEqual(TitleCleaner.clean("Sicko Mode (with Drake)"), "Sicko Mode")
        XCTAssertEqual(TitleCleaner.clean("Stan [feat. Dido]"), "Stan")
    }
    func testStripsDashSuffixes() {
        XCTAssertEqual(TitleCleaner.clean("Come Together - Remastered 2009"), "Come Together")
        XCTAssertEqual(TitleCleaner.clean("Let It Be - Single Version"), "Let It Be")
    }
    func testLeavesCleanTitlesAlone() {
        XCTAssertEqual(TitleCleaner.clean("WITHOUT ME"), "WITHOUT ME")
        XCTAssertEqual(TitleCleaner.clean("Plain Song"), "Plain Song")
    }
    func testVariants() {
        XCTAssertEqual(TitleCleaner.variants("Plain Song"), ["Plain Song"])
        XCTAssertEqual(TitleCleaner.variants("Like Him (feat. Lola Young)"),
                       ["Like Him (feat. Lola Young)", "Like Him"])
    }
}
