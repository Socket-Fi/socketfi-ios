import Foundation

/// Exact, nonnegative integer arithmetic for Stellar token amounts (up to i128).
public enum SocketFiAmount {
    public static let maximum = "170141183460469231731687303715884105727"

    public static func normalized(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw SocketFiNativeError.configuration("Enter a valid amount.")
        }
        let result = String(value.drop(while: { $0 == "0" }))
        let number = result.isEmpty ? "0" : result
        guard !greater(number, than: maximum) else {
            throw SocketFiNativeError.configuration("The amount is too large.")
        }
        return number
    }

    public static func atomic(_ input: String, decimals: Int) throws -> String {
        guard (0...18).contains(decimals), input.count <= 80 else {
            throw SocketFiNativeError.configuration("Unsupported amount precision.")
        }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty else {
            throw SocketFiNativeError.configuration("Enter an amount such as 1.25.")
        }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= decimals else {
            throw SocketFiNativeError.configuration("This token supports up to \(decimals) decimal places.")
        }
        return try normalized(String(parts[0]) + fraction + String(repeating: "0", count: decimals - fraction.count))
    }

    public static func display(_ atomic: String, decimals: Int) -> String {
        guard (0...18).contains(decimals), let number = try? normalized(atomic) else { return "—" }
        guard decimals > 0 else { return number }
        let padded = String(repeating: "0", count: max(0, decimals + 1 - number.count)) + number
        let split = padded.index(padded.endIndex, offsetBy: -decimals)
        let fraction = padded[split...].reversed().drop(while: { $0 == "0" }).reversed()
        return String(padded[..<split]) + (fraction.isEmpty ? "" : "." + String(fraction))
    }

    public static func greater(_ lhs: String, than rhs: String) -> Bool {
        lhs.count == rhs.count ? lhs > rhs : lhs.count > rhs.count
    }

    public static func minimumOutput(_ amount: String, slippageBps: Int) throws -> String {
        let value = try normalized(amount)
        guard (0...10_000).contains(slippageBps) else { throw SocketFiNativeError.invalidResponse }
        var carry = 0
        var result = ""
        for digit in value.utf8.reversed() {
            let next = Int(digit - 48) * (10_000 - slippageBps) + carry
            result.append(String(next % 10))
            carry = next / 10
        }
        while carry > 0 { result.append(String(carry % 10)); carry /= 10 }
        let product = String(result.reversed())
        return try normalized(product.count > 4 ? String(product.dropLast(4)) : "0")
    }
}

/// Only the ScVal encodings used by token transfer and Aquarius swap_chained.
/// StrKey checksum and version are checked before encoding an address.
public enum SocketFiXDR {
    public static func isAddress(_ value: String, contractOnly: Bool = false) -> Bool {
        guard let decoded = try? addressBytes(value) else { return false }
        return !contractOnly || decoded.version == 16
    }

    public static func address(_ value: String) throws -> String {
        let decoded = try addressBytes(value)
        var bytes: [UInt8] = [0, 0, 0, 18, 0, 0, 0, decoded.version == 16 ? 1 : 0]
        if decoded.version == 48 { bytes += [0, 0, 0, 0] }
        return Data(bytes + decoded.payload).base64EncodedString()
    }

    public static func integer(_ value: String, unsigned: Bool = false) throws -> String {
        let number = try SocketFiAmount.normalized(value)
        var bytes = [UInt8](repeating: 0, count: 16)
        for digit in number.utf8 {
            var carry = Int(digit - 48)
            for index in stride(from: 15, through: 0, by: -1) {
                let next = Int(bytes[index]) * 10 + carry
                bytes[index] = UInt8(next & 255)
                carry = next >> 8
            }
            guard carry == 0 else { throw SocketFiNativeError.invalidResponse }
        }
        return Data([0, 0, 0, unsigned ? 9 : 10] + bytes).base64EncodedString()
    }

    private static func addressBytes(_ value: String) throws -> (version: UInt8, payload: [UInt8]) {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        guard value.utf8.count == 56 else { throw SocketFiNativeError.configuration("Enter a valid Stellar G… or C… address.") }
        var bytes: [UInt8] = []
        var bits: UInt32 = 0
        var count = 0
        for char in value.utf8 {
            guard let digit = alphabet.firstIndex(of: char) else { throw SocketFiNativeError.invalidResponse }
            bits = (bits << 5) | UInt32(digit)
            count += 5
            if count >= 8 {
                count -= 8
                bytes.append(UInt8((bits >> count) & 255))
            }
        }
        guard bytes.count == 35, bytes[0] == 16 || bytes[0] == 48 else {
            throw SocketFiNativeError.invalidResponse
        }
        var crc: UInt16 = 0
        for byte in bytes.prefix(33) {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = (crc & 0x8000) != 0 ? (crc &<< 1) ^ 0x1021 : crc &<< 1 }
        }
        guard bytes[33] == UInt8(crc & 255), bytes[34] == UInt8(crc >> 8) else {
            throw SocketFiNativeError.configuration("The address checksum is invalid. Check the recipient address.")
        }
        return (bytes[0], Array(bytes[1...32]))
    }
}
