import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation

enum SplitParentScenarios {

    private static func pointer(_ app: AppUnderTest, _ phase: PointerPhase, _ point: CGPoint) throws {
        _ = try app.send(.pointer(window: app.window, phase: phase, point: point))
    }


    /// What the removed split toolbar's buttons did, through the commands the View menu and the pane header's split
    /// menu send (`.maximizeSplitPane` restores while the split is expanded).
    static func splitTool(_ app: AppUnderTest, _ action: ActionID) throws {
        let expanded = try app.view().content.expanded
        try app.dispatch(action == .maximizeSplitPane && expanded ? .split(.restore) : action.spec.command)
    }


}
