import BrkDomain
import Foundation
import XCTest

final class IndependentCalendarBoundaryTests: XCTestCase {
    func testMalformedSelectedCalendarFailsWithoutTerminatingTheProcess() throws {
        let selectedFile = Data("BEGIN:VCALENDAR\nBEGIN:VEVENT\n:value\nEND:VEVENT\nEND:VCALENDAR\n".utf8)
        XCTAssertThrowsError(try CalendarFile.meetings(selectedFile))
    }
}
