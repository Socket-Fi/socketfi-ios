import Foundation
import Security

public actor SocketFiSessionStore {
    private let service: String
    private let accountKey = "session"

    public init(service: String) {
        precondition(!service.isEmpty)
        self.service = service
    }

    public func save(_ session: SocketFiSession) throws {
        let data = try JSONEncoder.socketFi.encode(session)
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: accountKey,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw SocketFiNativeError.configuration("Unable to save the SocketFi session securely.")
        }
    }

    public func load() throws -> SocketFiSession? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: accountKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        guard let data = result as? Data else { return nil }
        return try JSONDecoder.socketFi.decode(SocketFiSession.self, from: data)
    }

    public func clear() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: accountKey,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private extension JSONEncoder {
    static var socketFi: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var socketFi: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
