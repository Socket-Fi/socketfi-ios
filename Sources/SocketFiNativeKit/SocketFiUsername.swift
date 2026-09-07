import Foundation

public enum SocketFiUsername {
    public static func suggested() -> String {
        let word = ["fox", "otter", "bird", "panda", "wolf"].randomElement() ?? "fox"
        return "socketfi_\(word)\(Int.random(in: 100...999))"
    }

    public static func normalize(_ value: String) -> String {
        value.lowercased().map { $0.isWhitespace ? "_" : String($0) }.joined()
    }

    public static func isValid(_ value: String) -> Bool {
        value.range(
            of: "^[a-z0-9](?:[a-z0-9_-]{1,28}[a-z0-9])$",
            options: .regularExpression
        ) != nil && value.count >= 3 && value.count <= 30 && !value.contains(where: \.isWhitespace)
    }
}
