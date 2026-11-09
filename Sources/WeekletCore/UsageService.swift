import Foundation

public struct HTTPPayload: Sendable {
    public let status: Int
    public let body: Data
    public let retryAfter: String?

    public init(status: Int, body: Data, retryAfter: String? = nil) {
        self.status = status
        self.body = body
        self.retryAfter = retryAfter
    }
}

public protocol UsageTransport: Sendable {
    func getUsage(for provider: Provider, credential: Credential) async throws -> HTTPPayload
}

final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class FixedEndpointTransport: UsageTransport, Sendable {
    private let session: URLSession
    private let maximumBodySize = 1_048_576

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    static func request(for provider: Provider, credential: Credential) -> URLRequest {
        // URLs are compile-time constants; no configured base URL can redirect credentials.
        var request = URLRequest(url: provider.usageURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Weeklet/1.0", forHTTPHeaderField: "User-Agent")
        credential.authorize(&request)
        switch provider {
        case .claude:
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        case .codex:
            if let accountID = credential.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
        }
        return request
    }

    public func getUsage(for provider: Provider, credential: Credential) async throws -> HTTPPayload {
        let (bytes, response) = try await session.bytes(for: Self.request(for: provider, credential: credential))
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse,
              response.url == provider.usageURL else { throw UsageFailure.invalidResponse }
        guard response.expectedContentLength <= maximumBodySize else { throw UsageFailure.invalidResponse }
        var body = Data()
        for try await byte in bytes {
            guard body.count < maximumBodySize else { throw UsageFailure.invalidResponse }
            body.append(byte)
        }
        return HTTPPayload(status: response.statusCode, body: body,
                           retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }
}

public protocol UsageFetching: Sendable {
    func fetch(_ provider: Provider, allowInteraction: Bool) async -> Result<WeeklyUsage, UsageFailure>
}

public struct UsageService: UsageFetching, Sendable {
    private let credentials: any CredentialReading
    private let transport: any UsageTransport

    public init(credentials: any CredentialReading = LocalCredentialReader(),
                transport: any UsageTransport = FixedEndpointTransport()) {
        self.credentials = credentials
        self.transport = transport
    }

    public func fetch(_ provider: Provider, allowInteraction: Bool = false) async -> Result<WeeklyUsage, UsageFailure> {
        do {
            let credential = try await credentials.read(for: provider, allowInteraction: allowInteraction)
            try Task.checkCancellation()
            let payload = try await transport.getUsage(for: provider, credential: credential)
            switch payload.status {
            case 200: return .success(try ProviderContracts.parse(payload.body, for: provider))
            case 401: return .failure(.expiredSession)
            case 403: return .failure(.unsupportedAuth)
            case 429: return .failure(.rateLimited(until: Self.retryDate(payload.retryAfter, now: Date())))
            case 300..<400: return .failure(.redirectBlocked)
            default: return .failure(.serviceUnavailable)
            }
        } catch let failure as UsageFailure { return .failure(failure) }
        catch is CancellationError { return .failure(.cancelled) }
        catch let error as URLError {
            switch error.code {
            case .timedOut: return .failure(.timeout)
            case .cancelled: return .failure(.cancelled)
            default: return .failure(.offline)
            }
        } catch { return .failure(.serviceUnavailable) }
    }

    static func retryDate(_ header: String?, now: Date) -> Date {
        if let header {
            if let seconds = Double(header), seconds.isFinite, seconds >= 0 {
                return now.addingTimeInterval(max(1, seconds))
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            if let date = formatter.date(from: header), date > now { return date }
        }
        return now.addingTimeInterval(300)
    }
}
