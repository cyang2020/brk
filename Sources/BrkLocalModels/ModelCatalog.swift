import Foundation

/// What a local model is for. Each role has one model at a time.
public enum LocalModelRole: String, CaseIterable, Hashable, Sendable, Codable {
    /// Text to vectors: search by meaning, the nearest groups for a new tab, near-duplicate candidates, Tidy's clusters.
    case search
    /// Pick an option, a score or yes/no with probabilities (the Jev shape).
    case decision
}

/// One file of a model, pinned: the address names a commit, the digest is checked before the file is used.
public struct ModelFile: Hashable, Sendable {
    public var name: String
    public var url: URL
    public var bytes: Int64
    public var sha256: String
}

/// A model Brk can download and run on this Mac. Nothing is bundled; the user downloads each one from its card.
public struct LocalModel: Hashable, Sendable, Identifiable {
    public var id: String
    public var role: LocalModelRole
    public var title: String
    /// One line for the card: what it does for the user.
    public var purpose: String
    public var file: ModelFile
    public var license: String
    public var source: URL
    /// llama-server arguments besides the model, socket and log.
    public var serverArguments: [String]
    /// Decision models: the letter temperature and the many-option one (each file's own, from its model card).
    public var temperature: Double = 1
    public var knockoutTemperature: Double = 1
    /// The memory the helper holds while loaded, measured on an M1 with 16 GB (b6baac6767:verify/ai-native/b-local-models).
    public var residentMB: Int
    /// Languages the model was trained for; the card says when the user's titles are outside them.
    public var languages: String

    public var bytes: Int64 { file.bytes }
}

public enum ModelCatalog {
    /// EmbeddingGemma 2, Q8_0 GGUF converted by ggml-org from google/embeddinggemma-2 (Apache 2.0, released 2026-10-06).
    public static let embeddingGemma2 = LocalModel(
        id: "embeddinggemma-2-q8",
        role: .search,
        title: "EmbeddingGemma 2",
        purpose: "Finds tabs, history and archived tabs by meaning, and groups similar tabs.",
        file: ModelFile(name: "embeddinggemma-2-Q8_0.gguf",
                        url: URL(string: "https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/6ea3e3a309d12a4779cfda98b8c19800d2d5da71/embeddinggemma-2-Q8_0.gguf")!,
                        bytes: 309_855_456, sha256: "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135"),
        license: "Apache 2.0",
        source: URL(string: "https://huggingface.co/google/embeddinggemma-2")!,
        serverArguments: ["--embeddings", "--pooling", "mean", "-c", "4096", "-ub", "2048", "-b", "2048", "-np", "4", "--cache-ram", "0", "--no-webui"],
        residentMB: 500,
        languages: "100+ languages, Chinese included")

    /// JevK5 v0.3 4B, Q4_K_M GGUF (allebee/jevk5, Apache-2.0). Q8_0 gives the same answer as bf16 more often (229 against
    /// 221 of JevBench's 231 public items) at 4.48 GB; on this Mac's labelled tabs the two were measured side by side.
    public static let jevK5Q4 = LocalModel(
        id: "jevk5-4b-v0.3-q4",
        role: .decision,
        title: "JevK5 4B",
        purpose: "Answers Brk's yes/no and pick-one questions with a probability, without sending anything off this Mac.",
        file: ModelFile(name: "jevk5-4b-v0.3-Q4_K_M.gguf",
                        url: URL(string: "https://huggingface.co/alibiserikbay/JevK5-GGUF/resolve/ec67b0bfce5119a8b11a2cdb430bb43e3fa3e82a/jevk5-4b-v0.3-Q4_K_M.gguf")!,
                        bytes: 2_708_804_000, sha256: "94ca0d7745c47f79091b0892ca657c81d9dc9e4ed0238ba0a7ea261d8938c882"),
        license: "Apache 2.0",
        source: URL(string: "https://github.com/allebee/jevk5")!,
        serverArguments: ["-c", "8192", "-np", "1", "--cache-ram", "0", "--no-webui"],
        temperature: 1.22,
        knockoutTemperature: 0.93,
        residentMB: 3_200,
        languages: jevK5Languages)

    public static let jevK5Q8 = LocalModel(
        id: "jevk5-4b-v0.3-q8",
        role: .decision,
        title: "JevK5 4B (8-bit)",
        purpose: jevK5Q4.purpose,
        file: ModelFile(name: "jevk5-4b-v0.3-Q8_0.gguf",
                        url: URL(string: "https://huggingface.co/alibiserikbay/JevK5-GGUF/resolve/ec67b0bfce5119a8b11a2cdb430bb43e3fa3e82a/jevk5-4b-v0.3-Q8_0.gguf")!,
                        bytes: 4_482_402_720, sha256: "aea433883bc7ed399f2fbd539e53d2eac7caf71a946fe6650995a413979d4a30"),
        license: "Apache 2.0",
        source: jevK5Q4.source,
        serverArguments: jevK5Q4.serverArguments,
        temperature: 1.22,
        knockoutTemperature: 0.93,
        residentMB: 4_300,
        languages: jevK5Languages)

    /// Its card says English only; on this Mac's 121 labelled tabs, 63 with Chinese titles, Chinese did as well as
    /// English (placement 58 of 63 against 54 of 58, naming 31 of 31, injection 12 of 12; b6baac6767:verify/ai-native/b-local-models).
    static let jevK5Languages = "English only by its card; measured as good on Chinese tab titles"

    public static let all: [LocalModel] = [embeddingGemma2, jevK5Q4, jevK5Q8]

    /// The model each role offers by default.
    public static func standard(_ role: LocalModelRole) -> LocalModel {
        switch role {
        case .search: embeddingGemma2
        case .decision: jevK5Q4
        }
    }

    public static func model(id: String) -> LocalModel? { all.first { $0.id == id } }
}

/// The llama.cpp build the helper runs: upstream's macOS arm64 release (MIT), pinned by tag and digest. scripts/build.sh
/// puts its llama-server and libraries in Brk.app/Contents/Helpers/llama; Brk never downloads code at run time.
public enum LlamaRuntime {
    public static let tag = "b12202"
    public static let archive = URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/b12202/llama-b12202-bin-macos-arm64.tar.gz")!
    public static let sha256 = "e70cd5918fb1db75652cee66bd6ab9c933cc0c5acf632f15df672c00829ebcaf"
    /// The Intel build's copy (scripts/add-llama-runtime.sh picks it by the app's architecture); upstream builds it without Metal.
    public static let archiveX64 = URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/b12202/llama-b12202-bin-macos-x64.tar.gz")!
    public static let sha256X64 = "02ce0277e0e393f52debf96668fb61a67e3348b31b20875f2162663afda15f2a"
    public static let license = "MIT"

    /// Where the helper is: `BRK_LLAMA_SERVER` (tests), else the app bundle's copy, else Homebrew's (development builds).
    public static func executable(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment,
                                  fileManager: FileManager = .default) -> URL? {
        var candidates: [URL] = []
        if let override = environment["BRK_LLAMA_SERVER"], !override.isEmpty { candidates.append(URL(fileURLWithPath: override)) }
        candidates.append(bundle.bundleURL.appendingPathComponent("Contents/Helpers/llama/llama-server"))
        candidates += ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"].map { URL(fileURLWithPath: $0) }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
