import Foundation

public enum OutputTag {}
public typealias OutputID = ID<OutputTag>

public enum OutputIntent: String, Hashable, Sendable, Codable { case mhtml, pdf, print }

public struct OutputRequest: Hashable, Sendable, Codable {
    public let id: OutputID
    public let document: DocumentToken
    public let intent: OutputIntent
    public let suggestedName: String
    public init(id: OutputID, document: DocumentToken, intent: OutputIntent, suggestedName: String) {
        self.id = id; self.document = document; self.intent = intent; self.suggestedName = suggestedName
    }
}

public struct OutputDestinationPrompt: Hashable, Sendable {
    public let request: OutputRequest
    public init(request: OutputRequest) { self.request = request }
}

public enum PrintAnswer: Hashable, Sendable { case submitted, cancelled, failed(String), ownerGone }

public enum OutputResult: Hashable, Sendable, Codable {
    case saved(FileReceipt)
    case submittedToPrintSystem
    case cancelled(PartialFile)
    case failed(String, PartialFile)
}

public enum OutputStage: Hashable, Sendable, Codable {
    case choosingDestination, rendering, printing, cancelling
    case terminal(OutputResult)
}

public struct OutputUpdate: Hashable, Sendable, Codable {
    public let id: OutputID
    public let document: DocumentToken
    public let stage: OutputStage
    public init(id: OutputID, document: DocumentToken, stage: OutputStage) {
        self.id = id; self.document = document; self.stage = stage
    }

    public var message: String {
        switch stage {
        case .choosingDestination: "Choose where to save"
        case .rendering: "Preparing page…"
        case .printing: "Print dialog open"
        case .cancelling: "Cancelling output…"
        case .terminal(.saved(let file)): "Saved \(file.url.lastPathComponent)"
        case .terminal(.submittedToPrintSystem): "Submitted to print system"
        case .terminal(.cancelled(.retained(let url, _))): "Output cancelled; recovery files: \(url.path)"
        case .terminal(.cancelled(.unknown)): "Output cancelled; temporary file state is unknown"
        case .terminal(.cancelled): "Output cancelled"
        case .terminal(.failed(let error, .retained(let url, _))): "Output failed: \(error); recovery files: \(url.path)"
        case .terminal(.failed(let error, .unknown)): "Output failed: \(error); temporary file state is unknown"
        case .terminal(.failed(let error, _)): "Output failed: \(error)"
        }
    }
}
