import Darwin
import Dispatch
import XCTest
@testable import BrkApp

final class ContextMenuDriverTests: XCTestCase {
    @MainActor func testMenuDriverCreatedOnMainActorCanFinishOnBackgroundQueue() {
        let alreadyClosed = DispatchSemaphore(value:0)
        alreadyClosed.signal()
        let driver = ContextMenuCapture.makeDriver(prefix:nil,index:nil,pid:getpid(),done:alreadyClosed)
        DispatchQueue.global(qos:.userInteractive).async(execute:driver)
        XCTAssertEqual(driver.wait(timeout:.now()+5),.success)
    }
}
