import Foundation

/// Native DevTools observers share one reply stream, including across consumer types.
@MainActor
enum CefDevToolsRequestIDs {
    private static var last: Int32 = 0
    static func next() -> Int {
        precondition(last < Int32.max)
        last += 1
        return Int(last)
    }
}
