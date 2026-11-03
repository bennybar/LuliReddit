import Network
import XCTest
@testable import Ilay

/// Cancel in the progress dialog stops a download blocked on a server that never answers.
final class DownloadCancelTests: XCTestCase {
    func testCancelStopsADownloadBlockedOnASilentServer() async throws {
        // A server that accepts the connection and never answers. https: plain http would
        // stop at App Transport Security rather than reach it.
        let listener = try NWListener(using: .tcp, on: .any)
        let queue = DispatchQueue(label: "silent-server")
        var held: [NWConnection] = []
        listener.newConnectionHandler = { connection in
            held.append(connection)
            connection.start(queue: queue)
        }
        let ready = expectation(description: "listening")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 5)
        defer {
            queue.sync { held.forEach { $0.cancel() } }
            listener.cancel()
        }
        let port = try XCTUnwrap(listener.port?.rawValue)
        let dest = FileManager.default.temporaryDirectory.appending(path: "ilay-dl-\(UUID().uuidString).bin")

        let job = Task { try await downloadTo("https://127.0.0.1:\(port)/x", dest: dest) }
        try await Task.sleep(for: .milliseconds(300)) // Well into the blocked request.
        let started = Date()
        job.cancel()
        do {
            try await job.value
            XCTFail("It finished instead of being cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        // It used to wait for the server (or the 90 s read timeout).
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}
