import CryptoKit
import Foundation
@testable import BrkLocalModels
import XCTest

final class UnixHTTPTests: XCTestCase {
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

    /// A negative chunk size made the reader slice backwards and crash Brk; a size past the end overflowed.
    func testABadChunkSizeIsABadReplyNotACrash() {
        XCTAssertEqual(UnixHTTP.dechunk(Data("3\r\nabc\r\n0\r\n\r\n".utf8)), Data("abc".utf8))
        XCTAssertNil(UnixHTTP.dechunk(Data("-5\r\nabcdefgh\r\n0\r\n\r\n".utf8)))
        XCTAssertNil(UnixHTTP.dechunk(Data("7fffffffffffffff\r\nabc\r\n".utf8)))
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
}
