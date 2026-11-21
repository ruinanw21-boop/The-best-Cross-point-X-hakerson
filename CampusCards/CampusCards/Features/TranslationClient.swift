import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum TranslationServiceError: Error, Equatable {
    case invalidAddress
    case invalidRequest
    case unavailable
    case timeout
    case offline
    case invalidResponse
}

struct TranslationClient {
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: NoTranslationRedirects(), delegateQueue: nil)
    }()

    private let baseAddress: String
    private let session: URLSession

    init(baseAddress: String, session: URLSession? = nil) {
        self.baseAddress = baseAddress
        self.session = session ?? Self.defaultSession
    }

    func translate(text: String, source: CardLanguage) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationServiceError.invalidRequest
        }
        var request = URLRequest(url: try endpoint(), timeoutInterval: 120)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            text: text,
            source_language: source == .english ? "en" : "zh",
            target_language: source == .english ? "zh" : "en"
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: NoTranslationRedirects())
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw TranslationServiceError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .dataNotAllowed:
                throw TranslationServiceError.offline
            default:
                throw TranslationServiceError.unavailable
            }
        }
        guard let http = response as? HTTPURLResponse else {
            throw TranslationServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        if http.statusCode == 200 {
            guard let body = try? decoder.decode(TranslationBody.self, from: data),
                  !body.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranslationServiceError.invalidResponse
            }
            return body.translation
        }

        let code = (try? decoder.decode(ErrorBody.self, from: data))?.error.code
        switch (http.statusCode, code) {
        case (400, "invalid_request"):
            throw TranslationServiceError.invalidRequest
        case (504, "upstream_timeout"):
            throw TranslationServiceError.timeout
        case (502, "translation_failed"), (500...599, _):
            throw TranslationServiceError.unavailable
        default:
            throw TranslationServiceError.invalidResponse
        }
    }

    func endpoint() throws -> URL {
        let address = baseAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !address.contains("\\"),
              var components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              ["", "/"].contains(components.percentEncodedPath) else {
            throw TranslationServiceError.invalidAddress
        }
        components.path = "/translate"
        guard let url = components.url else { throw TranslationServiceError.invalidAddress }
        return url
    }

    private struct RequestBody: Encodable {
        let text: String
        let source_language: String
        let target_language: String
    }

    private struct TranslationBody: Decodable {
        let translation: String
    }

    private struct ErrorBody: Decodable {
        struct ServiceError: Decodable { let code: String }
        let error: ServiceError
    }
}

// A 307/308 could otherwise forward the student's text to another service.
private final class NoTranslationRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
