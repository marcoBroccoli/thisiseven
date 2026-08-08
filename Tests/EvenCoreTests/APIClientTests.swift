@testable import EvenCore
import Foundation
import XCTest

/// Captures the request a client call actually puts on the wire.
private final class RequestRecorder: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var lastPath: String?
    nonisolated(unsafe) static var response: (Int, Data) = (200, Data("{}".utf8))

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastPath = request.url?.path
        // URLProtocol strips httpBody into the stream; read whichever is set.
        if let body = request.httpBody {
            Self.lastBody = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            buffer.deallocate()
            stream.close()
            Self.lastBody = data
        } else {
            Self.lastBody = nil
        }

        let (status, payload) = Self.response
        let http = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    private func makeClient() -> EvenAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestRecorder.self]
        return EvenAPIClient(
            environment: .localhost,
            session: URLSession(configuration: configuration),
            tokenProvider: { "test-token" }
        )
    }

    /// Regression: the server's week guard is a case-sensitive string compare
    /// against a Postgres uuid (lowercase). `UUID.uuidString` is UPPERCASE, so
    /// sending it raw made every pour 409 `week_already_closed` — the ritual
    /// looked like it worked while the week stayed open.
    func testCloseWeekSendsTheWeekIDLowercased() async throws {
        let client = makeClient()
        let weekID = UUID(uuidString: "9D822D8D-D536-4BBD-BF46-22C7E0358ABC")!
        RequestRecorder.response = (200, Data("""
        {"closed_week":{"id":"9d822d8d-d536-4bbd-bf46-22c7e0358abc","index":1,"started_on":"2026-08-01"},
         "new_week":{"id":"9c17ec13-bed7-4012-b31e-c4e5ee5c6d1d","index":2,"started_on":"2026-08-08"}}
        """.utf8))

        let response = try await client.closeWeek(weekId: weekID)
        XCTAssertEqual(response.newWeek.index, 2)

        let body = try XCTUnwrap(RequestRecorder.lastBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["week_id"] as? String, "9d822d8d-d536-4bbd-bf46-22c7e0358abc")
        XCTAssertEqual(RequestRecorder.lastPath, "/v1/week/close")
    }

    /// No guard id → no body at all, which the handler accepts.
    func testCloseWeekWithoutAGuardSendsNoBody() async throws {
        let client = makeClient()
        RequestRecorder.lastBody = nil
        RequestRecorder.response = (200, Data("""
        {"closed_week":{"id":"9d822d8d-d536-4bbd-bf46-22c7e0358abc","index":1,"started_on":"2026-08-01"},
         "new_week":{"id":"9c17ec13-bed7-4012-b31e-c4e5ee5c6d1d","index":2,"started_on":"2026-08-08"}}
        """.utf8))

        _ = try await client.closeWeek(weekId: nil)
        XCTAssertNil(RequestRecorder.lastBody)
    }

    func testCloseWeekSurfacesTheAlreadyClosedCode() async {
        let client = makeClient()
        RequestRecorder.response = (409, Data("""
        {"error":{"code":"week_already_closed","message":"that week was already poured out"}}
        """.utf8))

        do {
            _ = try await client.closeWeek(weekId: UUID())
            XCTFail("expected a 409")
        } catch {
            XCTAssertEqual((error as? APIError)?.code, "week_already_closed")
        }
    }
}
