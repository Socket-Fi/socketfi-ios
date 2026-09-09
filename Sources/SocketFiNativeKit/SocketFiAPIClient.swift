import Foundation

@MainActor
public struct SocketFiAPIClient: Sendable {
    private let configuration: SocketFiConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configuration: SocketFiConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        bearerToken: String? = nil,
        response: Response.Type
    ) async throws -> Response {
        let url = configuration.apiBaseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.clientID, forHTTPHeaderField: "X-SocketFi-Client-ID")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)

        return try await send(request, response: response)
    }

    public func get<Response: Decodable>(
        _ path: String,
        query: [String: String] = [:],
        bearerToken: String? = nil,
        response: Response.Type
    ) async throws -> Response {
        guard var components = URLComponents(url: configuration.apiBaseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw SocketFiNativeError.invalidResponse
        }
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw SocketFiNativeError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.clientID, forHTTPHeaderField: "X-SocketFi-Client-ID")
        if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
        return try await send(request, response: response)
    }

    private func send<Response: Decodable>(_ request: URLRequest, response: Response.Type) async throws -> Response {
        let (data, urlResponse) = try await session.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw SocketFiNativeError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? decoder.decode(SocketFiAPIError.self, from: data)
            throw SocketFiNativeError.requestFailed(
                status: httpResponse.statusCode,
                code: error?.code,
                message: error?.error ?? error?.message ?? "SocketFi request failed (\(httpResponse.statusCode))."
            )
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SocketFiNativeError.invalidResponse
        }
    }
}

private struct SocketFiAPIError: Decodable {
    let error: String?
    let message: String?
    let code: String?
}
