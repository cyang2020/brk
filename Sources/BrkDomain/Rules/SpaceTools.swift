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
    /// The space's Pinned and Today rows, as its sidebar lists them: the Library's Spaces card draws them small.
    public var pinned: [Row] = []
    public var today: [Row] = []
}

public struct SpaceDeletionRequest: Sendable, Equatable, Codable {
    public let id: SpaceID
    public let title: String
    public let token: String
    /// Brk's own sentence after Arc's, when the Space has AI conversations: where they go ("3 段 AI 对话会移到 购物。").
    public var conversations: String? = nil
    public init(id: SpaceID, title: String, token: String, conversations: String? = nil) {
        self.id = id; self.title = title; self.token = token; self.conversations = conversations
    }
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
        var request = SpaceDeletionRequest(id: id, title: state.displayTitle(of: id), token: ctx.newID())
        // Its conversations move to the profile's first other Space; the dialog says how many and where (in the list's
        // language). With none, or no other Space of the profile, it is Arc's dialog as it is.
        if let profile = state.doc.spaces[id]?.profile,
           let first = state.doc.spaceOrder.first(where: { $0 != id && state.doc.spaces[$0]?.profile == profile }) {
            let count = state.conversationSpaces(profile).values.filter { $0 == id }.count
            if count > 0 {
                let language = state.listLanguage(profile, system: ctx.systemLanguage)
                request.conversations = AIThreadWords.spaceDeletionMoves(count, to: state.displayTitle(of: first), language)
            }
        }
        state.session.windows[window]?.pendingSpaceDeletion = request
    }

    mutating func confirmSpaceDeletion(_ id: SpaceID, token: String, confirmed: Bool, in window: WindowID) {
        guard let request = state.session.windows[window]?.pendingSpaceDeletion, request.id == id, request.token == token else { return }
        state.session.windows[window]?.pendingSpaceDeletion = nil
        // The deletion itself says "Space deleted! Use ⌘Z to undo" (Arc, P15 c).
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
