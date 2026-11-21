import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import CampusCards

final class TranslationClientTests: XCTestCase {
    private func client(_ address: String) -> TranslationClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranslationStub.self]
        return TranslationClient(baseAddress: address, session: URLSession(configuration: config))
    }

    func testEnglishToChineseSendsOnlyConfirmedTextAndWireLanguageCodes() async throws {
        let result = try await client("https://english.test/")
            .translate(text: "Which desk should I go to?", source: .english)
        XCTAssertEqual(result, "我该去哪个服务台？")
    }

    func testChineseToEnglishPreservesTheEditedText() async throws {
        let result = try await client("http://10.1.2.3:8000")
            .translate(text: "请把护照复印件交到一楼服务台。", source: .chinese)
        XCTAssertEqual(result, "Please give the passport copy to the first-floor service desk.")
    }

    func testInvalidAddressAndBlankInputAreRejectedBeforeSending() async {
        for invalid in ["", "10.1.2.3:8000", "file:///local", "http://user:pw@host",
                        "http://host:0", "http://host:65536", "https://host?secret=1",
                        "https://host#fragment", "https://host/translate", "https://host/a%2Fb"] {
            await assertFailure(.invalidAddress, address: invalid)
        }
        await assertFailure(.invalidRequest, address: "https://unexpected.test", text: " \n ")
    }

    func testServiceAndTransportErrorsHaveDistinctRetrySemantics() async {
        await assertFailure(.invalidRequest, address: "https://invalid-request.test")
        await assertFailure(.unavailable, address: "https://service-failure.test")
        await assertFailure(.timeout, address: "https://upstream-timeout.test")
        await assertFailure(.timeout, address: "https://network-timeout.test")
        await assertFailure(.offline, address: "https://offline.test")
    }

    func testMalformedAndUnexpectedResponsesNeverBecomeTranslations() async {
        for host in ["blank", "malformed", "wrong-code", "unknown", "redirect"] {
            await assertFailure(.invalidResponse, address: "https://\(host).test")
        }
    }

    func testHTTPRepliesArrivingInReverseOrderKeepTheLatestDeadline() async throws {
        let host = UUID().uuidString.lowercased() + ".test"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledTranslationStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = TranslationClient(baseAddress: "https://\(host)", session: session)
        let arrivals = AsyncStream<ControlledTranslationStub>.makeStream()
        let continuation = arrivals.continuation
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name(host), object: nil, queue: nil
        ) { notification in
            if let request = notification.object as? ControlledTranslationStub {
                continuation.yield(request)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            continuation.finish()
        }
        var incoming = arrivals.stream.makeAsyncIterator()
        var draft = ReplyDraft(taskID: UUID())
        draft.original = "周五 16:00 前"
        let firstToken = try XCTUnwrap(draft.beginTranslation())
        let firstText = draft.original
        let firstTask = Task {
            defer { continuation.finish() }
            return try await client.translate(text: firstText, source: .chinese)
        }
        let firstArrival = await incoming.next()
        let firstHTTP = try XCTUnwrap(firstArrival)
        firstHTTP.assertBody(text: firstText, source: "zh", target: "en")

        draft.original = "周五 15:30 前"
        let secondToken = try XCTUnwrap(draft.beginTranslation())
        let secondText = draft.original
        let secondTask = Task {
            defer { continuation.finish() }
            return try await client.translate(text: secondText, source: .chinese)
        }
        let secondArrival = await incoming.next()
        let secondHTTP = try XCTUnwrap(secondArrival)
        secondHTTP.assertBody(text: secondText, source: "zh", target: "en")

        secondHTTP.reply(with: "By 15:30 Friday")
        let secondResult = try await secondTask.value
        XCTAssertTrue(draft.receiveTranslation(secondResult, for: secondToken))
        firstHTTP.reply(with: "By 16:00 Friday")
        let firstResult = try await firstTask.value
        XCTAssertFalse(draft.receiveTranslation(firstResult, for: firstToken))
        XCTAssertEqual(draft.original, "周五 15:30 前")
        XCTAssertEqual(draft.translation, "By 15:30 Friday")
        XCTAssertTrue(draft.canConfirm)
    }

    private func assertFailure(
        _ expected: TranslationServiceError, address: String, text: String = "test",
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await client(address).translate(text: text, source: .english)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? TranslationServiceError, expected, file: file, line: line)
        }
    }
}

private final class TranslationStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return XCTFail("Missing URL") }
        XCTAssertEqual(url.path, "/translate")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let status: Int
        let json: String
        switch url.host {
        case "english.test":
            assertBody(text: "Which desk should I go to?", source: "en", target: "zh")
            (status, json) = (200, #"{"translation":"我该去哪个服务台？"}"#)
        case "10.1.2.3":
            XCTAssertEqual(url.port, 8000)
            assertBody(text: "请把护照复印件交到一楼服务台。", source: "zh", target: "en")
            (status, json) = (200, #"{"translation":"Please give the passport copy to the first-floor service desk."}"#)
        case "invalid-request.test":
            (status, json) = (400, #"{"error":{"code":"invalid_request"}}"#)
        case "service-failure.test":
            (status, json) = (502, #"{"error":{"code":"translation_failed"}}"#)
        case "upstream-timeout.test":
            (status, json) = (504, #"{"error":{"code":"upstream_timeout"}}"#)
        case "network-timeout.test":
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        case "offline.test":
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        case "blank.test":
            (status, json) = (200, #"{"translation":"  "}"#)
        case "malformed.test":
            (status, json) = (200, "{}")
        case "wrong-code.test":
            (status, json) = (400, #"{"error":{"code":"something_else"}}"#)
        case "unknown.test":
            (status, json) = (404, "{}")
        case "redirect.test":
            (status, json) = (307, "{}")
        default:
            XCTFail("Unexpected request to \(url)")
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

}

private final class ControlledTranslationStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let host = request.url?.host else { return XCTFail("Missing host") }
        NotificationCenter.default.post(name: Notification.Name(host), object: self)
    }

    func reply(with translation: String) {
        guard let url = request.url else { return XCTFail("Missing URL") }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        let data = try! JSONEncoder().encode(["translation": translation])
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private extension URLProtocol {
    func assertBody(text: String, source: String, target: String) {
        do {
            let data: Data
            if let body = request.httpBody {
                data = body
            } else {
                let stream = try XCTUnwrap(request.httpBodyStream)
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 1024)
                var body = Data()
                while true {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
                    if count == 0 { break }
                    body.append(contentsOf: bytes.prefix(count))
                }
                data = body
            }
            let fields = try JSONDecoder().decode([String: String].self, from: data)
            XCTAssertEqual(fields, ["text": text, "source_language": source, "target_language": target])
        } catch {
            XCTFail("Could not read translation request: \(error)")
        }
    }
}
