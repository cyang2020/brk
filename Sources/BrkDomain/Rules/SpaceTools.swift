import BrkBase
import Foundation

public struct SpaceManagerRow: Sendable, Equatable, Codable, Identifiable {
    public let id: SpaceID
    public let title: String
    public let icon: SpaceIcon
    public let profileName: String
    public let theme: ResolvedTheme
    public let tabCount: Int
    public let active: Bool
}

public struct SpaceDeletionRequest: Sendable, Equatable, Codable {
    public let id: SpaceID
    public let title: String
    public let token: String
}

public enum SpaceExportOutcome: Sendable, Equatable {
    case saved, cancelled, failed(String)
}

struct SpaceExportOperation: Sendable, Equatable {
    let token: String
    let space: SpaceID
}

extension Work {
    mutating func requestSpaceDeletion(_ id: SpaceID, in window: WindowID) {
        guard state.doc.spaces[id] != nil,
              state.doc.spaceOrder.count > 1 else { return }
        let request = SpaceDeletionRequest(id: id, title: state.displayTitle(of: id), token: ctx.newID())
        state.session.windows[window]?.pendingSpaceDeletion = request
    }

    mutating func confirmSpaceDeletion(_ id: SpaceID, token: String, confirmed: Bool, in window: WindowID) {
        guard let request = state.session.windows[window]?.pendingSpaceDeletion, request.id == id, request.token == token else { return }
        state.session.windows[window]?.pendingSpaceDeletion = nil
        if confirmed { spaces(.delete(id), in: window) }
    }

    mutating func exportSpace(_ id: SpaceID, in window: WindowID) {
        guard state.doc.windows[window]?.kind == .standard,
              state.session.windows[window]?.spaceExport == nil,
              let document = exportDocument(for: .space(.space(id)), in: window) else { return }
        let token = ctx.newID()
        state.session.windows[window]?.spaceExport = SpaceExportOperation(token: token, space: id)
        state.session.windows[window]?.spaceExportMessage = nil
        effects.append(.exportSpaceFolder(window, token: token, document: document))
    }

    mutating func spaceExportFinished(_ window: WindowID, token: String, outcome: SpaceExportOutcome) {
        guard state.session.windows[window]?.spaceExport?.token == token else { return }
        state.session.windows[window]?.spaceExport = nil
        state.session.windows[window]?.spaceExportMessage = switch outcome {
        case .saved: "Bookmarks exported into a new folder."
        case .cancelled: nil
        case .failed(let message): "Export failed: \(message). Choose Export into Folder to retry."
        }
    }
}
