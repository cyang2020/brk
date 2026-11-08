import CryptoKit
import Foundation
@testable import BrkLocalModels
import XCTest

final class UnixHTTPTests: XCTestCase {
    func testParsesLengthAndChunkedReplies() throws {
        let plain = Data("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Type: application/json\r\n\r\nhello".utf8)
        XCTAssertEqual(try UnixHTTP.parse(plain, complete: false)?.body, Data("hello".utf8))
        XCTAssertNil(try UnixHTTP.parse(plain.prefix(plain.count - 2), complete: false))
        let chunked = Data("HTTP/1.1 503 Busy\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nwiki\r\n5\r\npedia\r\n0\r\n\r\n".utf8)
        let reply = try XCTUnwrap(try UnixHTTP.parse(chunked, complete: false))
        XCTAssertEqual(reply.status, 503)
        XCTAssertEqual(String(decoding: reply.body, as: UTF8.self), "wikipedia")
        XCTAssertNil(UnixHTTP.dechunk(Data("4\r\nwik".utf8)))
        XCTAssertThrowsError(try UnixHTTP.parse(Data("garbage\r\n\r\n".utf8), complete: true))
    }

    /// A real exchange over a socket file: a one-shot server on a thread answers a POST.
    func testRoundTripOverASocket() async throws {
        let folder = URL(fileURLWithPath: "/tmp/brk-uh-\(getpid())-\(Int.random(in: 0..<1_000_000))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("s.sock")
        let listener = try OneShotServer(path: path.path, reply: "HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\n{\"ok\":true}")
        let body = try await UnixHTTP(socket: path, timeout: 5).post("/v1/embeddings", json: Data("{\"input\":[\"a\"]}".utf8))
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "{\"ok\":true}")
        XCTAssertTrue(listener.received.hasPrefix("POST /v1/embeddings HTTP/1.1\r\n"))
        XCTAssertTrue(listener.received.hasSuffix("{\"input\":[\"a\"]}"))
        do {
            _ = try await UnixHTTP(socket: folder.appendingPathComponent("none.sock"), timeout: 1).get("/health")
            XCTFail("connected to nothing")
        } catch let failure as UnixHTTP.Failure {
            guard case .connect = failure else { return XCTFail("\(failure)") }
        }
    }
}

/// Accepts one connection, reads the request, writes `reply`, closes.
final class OneShotServer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    var received: String { lock.withLock { text } }

    init(path: String, reply: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            let bytes = Array(path.utf8)
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0, listen(fd, 1) == 0 else { throw POSIXError(.EADDRINUSE) }
        Thread.detachNewThread { [self] in
            let client = accept(fd, nil, nil)
            var buffer = [UInt8](repeating: 0, count: 65_536)
            var got = Data()
            while true {
                let count = recv(client, &buffer, buffer.count, 0)
                if count <= 0 { break }
                got.append(buffer, count: count)
                if let head = got.range(of: Data("\r\n\r\n".utf8)) {
                    let headers = String(decoding: got[..<head.lowerBound], as: UTF8.self)
                    let length = headers.components(separatedBy: "\r\n").compactMap { line -> Int? in
                        line.lowercased().hasPrefix("content-length:") ? Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) : nil
                    }.first ?? 0
                    if got.count - head.upperBound >= length { break }
                }
            }
            lock.withLock { text = String(decoding: got, as: UTF8.self) }
            _ = reply.withCString { send(client, $0, strlen($0), 0) }
            close(client)
            close(fd)
        }
    }
}

@MainActor
final class ModelStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("brk-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: folder) }

    private func model(bytes: Data, sha: String? = nil) throws -> LocalModel {
        let source = folder.appendingPathComponent("source.gguf")
        try bytes.write(to: source)
        let digest = sha ?? SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        var model = ModelCatalog.embeddingGemma2
        model.id = "test-model"
        model.file = ModelFile(name: "m.gguf", url: source, bytes: Int64(bytes.count), sha256: digest)
        return model
    }

    private func wait(_ store: ModelStore, _ model: LocalModel, until done: (ModelInstall) -> Bool) async throws {
        for _ in 0..<200 {
            if done(store.state(model)) { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("state stayed \(store.state(model))")
    }

    func testDownloadVerifiesAndSurvivesARestart() async throws {
        let model = try model(bytes: Data(repeating: 7, count: 300_000))
        let store = ModelStore(root: folder.appendingPathComponent("Local Models"), models: [model])
        var seen: [ModelInstall] = []
        store.onChange = { _, state in seen.append(state) }
        XCTAssertEqual(store.state(model), .absent)
        store.download(model)
        try await wait(store, model) { $0 == .ready }
        XCTAssertTrue(seen.contains(.verifying))
        XCTAssertNotNil(store.file(model))
        let again = ModelStore(root: store.root, models: [model])
        XCTAssertEqual(again.state(model), .ready)
        again.remove(model)
        XCTAssertEqual(again.state(model), .absent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: again.fileURL(model).path))
    }

    func testAWrongDigestIsDeletedAndReported() async throws {
        let model = try model(bytes: Data("not the model".utf8), sha: String(repeating: "0", count: 64))
        let store = ModelStore(root: folder.appendingPathComponent("Local Models"), models: [model])
        store.download(model)
        try await wait(store, model) { if case .failed = $0 { true } else { false } }
        guard case .failed(let message) = store.state(model) else { return XCTFail() }
        XCTAssertTrue(message.contains("not the published one"), message)
        XCTAssertNil(store.file(model))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(model).appendingPathExtension("partial").path))
    }

    func testATamperedFileIsNotReadyAtLaunch() async throws {
        let model = try model(bytes: Data(repeating: 1, count: 1_000))
        let store = ModelStore(root: folder.appendingPathComponent("Local Models"), models: [model])
        store.download(model)
        try await wait(store, model) { $0 == .ready }
        try Data(repeating: 1, count: 999).write(to: store.fileURL(model))
        XCTAssertEqual(ModelStore(root: store.root, models: [model]).state(model), .absent)
    }

    func testSizesReadLikeFinder() {
        XCTAssertEqual(ModelStore.size(309_855_456), "310 MB")
        XCTAssertEqual(ModelStore.size(2_708_804_000), "2.71 GB")
    }
}

final class ModelHelperTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: "/tmp/brk-mh-\(getpid())-\(Int.random(in: 0..<1_000_000))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    private func script(_ body: String) throws -> URL {
        let url = folder.appendingPathComponent("fake-server-\(Int.random(in: 0..<1_000_000))")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func helper(_ executable: URL, readyTimeout: Duration = .seconds(2)) throws -> ModelHelper {
        let file = folder.appendingPathComponent("m.gguf")
        try Data([1]).write(to: file)
        return ModelHelper(model: ModelCatalog.embeddingGemma2, modelFile: file, executable: executable,
                           runFolder: folder.appendingPathComponent("run"), idleTimeout: .seconds(60), readyTimeout: readyTimeout)
    }

    func testAHelperThatExitsIsReportedAndStopsBeingRetried() async throws {
        let helper = try helper(try script("echo starting >&2; exit 3"))
        for _ in 0..<3 {
            do { _ = try await helper.use { try await $0.get("/health") }; XCTFail("started") } catch let failure as ModelHelper.Failure {
                guard case .notReady = failure else { return XCTFail("\(failure)") }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        do { _ = try await helper.use { try await $0.get("/health") }; XCTFail("started") } catch let failure as ModelHelper.Failure {
            XCTAssertEqual(failure, .keepsStopping)
        }
        let log = try String(contentsOf: folder.appendingPathComponent("run/search.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("starting"))
    }

    /// Stop ends the whole process group, children included.
    func testStopEndsTheGroup() async throws {
        let marker = folder.appendingPathComponent("child.pid")
        let helper = try helper(try script("sleep 60 & echo $! > \(marker.path); sleep 60"), readyTimeout: .seconds(1))
        do { _ = try await helper.use { try await $0.get("/health") } } catch {}
        let child = try XCTUnwrap(Int32(try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        await helper.stop()
        for _ in 0..<40 where kill(child, 0) == 0 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNotEqual(kill(child, 0), 0, "the helper's child outlived stop")
    }

    func testNoRuntimeAndNoModelFile() async throws {
        let missing = ModelHelper(model: ModelCatalog.embeddingGemma2, modelFile: folder.appendingPathComponent("absent.gguf"),
                                  executable: URL(fileURLWithPath: "/bin/sh"), runFolder: folder)
        do { _ = try await missing.use { try await $0.get("/health") }; XCTFail() } catch let failure as ModelHelper.Failure {
            XCTAssertEqual(failure, .noModelFile)
        }
        let noRuntime = try helper(folder.appendingPathComponent("no-such-server"))
        do { _ = try await noRuntime.use { try await $0.get("/health") }; XCTFail() } catch let failure as ModelHelper.Failure {
            XCTAssertEqual(failure, .noRuntime)
        }
    }
}

/// Runs the real models through the real helper when BRK_LOCAL_MODELS_TEST=1 and the files are in ~/.cache/brk-models
/// (verify/ai-native/b-local-models/README.md). Skipped otherwise.
final class RealModelTests: XCTestCase {
    private func setup() throws -> (URL, URL) {
        guard ProcessInfo.processInfo.environment["BRK_LOCAL_MODELS_TEST"] == "1" else { throw XCTSkip("set BRK_LOCAL_MODELS_TEST=1") }
        guard let runtime = LlamaRuntime.executable() else { throw XCTSkip("no llama-server") }
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/brk-models")
        return (runtime, cache)
    }

    func testEmbeddingGemma2FindsTheChineseTab() async throws {
        let (runtime, cache) = try setup()
        let file = cache.appendingPathComponent("embeddinggemma-2-gguf/embeddinggemma-2-Q8_0.gguf")
        let run = URL(fileURLWithPath: "/tmp/brk-real-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: run) }
        let helper = ModelHelper(model: ModelCatalog.embeddingGemma2, modelFile: file, executable: runtime, runFolder: run)
        let embedder = LocalEmbedder(helper: helper)
        let index = SemanticIndex(file: run.appendingPathComponent("p.vectors"))
        let entries = [IndexEntry(kind: .tab, id: "1", title: "MySQL 索引优化实战 - 掘金", url: "https://juejin.cn/post/1"),
                       IndexEntry(kind: .history, id: "2", title: "东京自由行攻略 - 小红书", url: "https://www.xiaohongshu.com/explore/2"),
                       IndexEntry(kind: .archive, id: "3", title: "Tokyo Metro Route Map", url: "https://www.tokyometro.jp/en/subwaymap/")]
        try await index.reconcile(entries, embedder: embedder)
        let query = try await embedder.embed([.query("the article about database indexes")])[0]
        let hits = await index.search(query, limit: 1)
        XCTAssertEqual(hits.first?.key, "tab:1")
        let running = await helper.isRunning
        XCTAssertTrue(running)
        await helper.stop()
    }

    func testJevK5AnswersTheReadmeExamples() async throws {
        let (runtime, cache) = try setup()
        let file = cache.appendingPathComponent("jevk5-gguf/jevk5-4b-v0.3-Q4_K_M.gguf")
        let run = URL(fileURLWithPath: "/tmp/brk-real-j-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: run) }
        let helper = ModelHelper(model: ModelCatalog.jevK5Q4, modelFile: file, executable: runtime, runFolder: run)
        let decider = LocalDecider(helper: helper)
        let reply = try await decider.decide(JevRequest(
            state: .text("Order #7120 shows delivered to No. 17; the customer lives at No. 71."),
            questions: [("what", .choice("What happened to the parcel?", [("delivered", nil), ("misdelivered", nil), ("unknown", nil)])),
                        ("refund", .noul("Is a refund permitted under the policy? Refunds need a receipt; the customer has none."))]))
        XCTAssertEqual(reply.answers["what"]?.choice, "misdelivered")
        XCTAssertLessThan(try XCTUnwrap(reply.answers["refund"]?.noul), 0.5)
        XCTAssertGreaterThan(reply.usage.inputTokens, 100)
        await helper.stop()
    }
}
