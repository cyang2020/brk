import BrkBase
import Foundation

/// Every rule that spans entities, run after each transition and after decoding a file. It repairs; it never
/// decides: an absent active item stays absent (the space shows an empty card) until a user action fills it.
///
/// 1. (Split membership, pane count and focus are kept by `SidebarTree` itself and need no repair.)
/// 2. `activeBySpace` entries name existing tabs or splits of that window's spaces; dangling entries are removed.
/// 3. Every window's space exists; `spaceOrder` lists exactly the spaces.
/// 4. Overlay, rename and dialog targets exist; otherwise they close.
/// 5. Every visible tab (named by an existing `activeBySpace` entry of its window's current space, or a pane of
///    one) is in `session.loaded`; `live` has entries only for loaded tabs.
/// 6. Archive and history caps; sidebar width within Metrics.sidebar bounds.
func normalize(_ state: inout AppState) {
    // TODO(W1): rules 1 to 6, each a small private function.
    fatalError("not implemented")
}
