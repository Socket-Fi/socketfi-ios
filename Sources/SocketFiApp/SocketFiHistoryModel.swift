import Foundation
import Combine
import SocketFiNativeKit

@MainActor
final class SocketFiHistoryModel: ObservableObject {
    @Published private(set) var items: [SocketFiHistoryItem] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingMore = false
    @Published private(set) var loaded = false
    @Published private(set) var error: String?
    @Published private(set) var pageError: String?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var nextCursor: String?
    private var seenCursors = Set<String>()
    private let load: (String?) async throws -> SocketFiHistoryPage

    init(load: @escaping (String?) async throws -> SocketFiHistoryPage) { self.load = load }

    func refresh() async {
        guard !loading, !loadingMore else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await load(nil)
            try Task.checkCancellation()
            items = page.transactions
            nextCursor = page.nextCursor
            seenCursors = []
            loaded = true; updatedAt = Date(); error = nil; pageError = nil
        } catch is CancellationError { }
        catch let failure as URLError where failure.code == .cancelled { }
        catch { self.error = Self.message(error) }
    }

    func loadMore() async {
        guard !loading, !loadingMore, let cursor = nextCursor else { return }
        loadingMore = true; pageError = nil
        defer { loadingMore = false }
        do {
            let page = try await load(cursor)
            try Task.checkCancellation()
            guard page.nextCursor != cursor, page.nextCursor.map({ !seenCursors.contains($0) }) ?? true else {
                throw SocketFiNativeError.invalidResponse
            }
            let known = Set(items.map(\.id))
            // One transaction can have several indexed events. Deduplicate event
            // IDs, never hashes, so swaps and multiple transfers stay complete.
            items.append(contentsOf: page.transactions.filter { !known.contains($0.id) })
            seenCursors.insert(cursor)
            nextCursor = page.nextCursor
        } catch is CancellationError { }
        catch let failure as URLError where failure.code == .cancelled { }
        catch { pageError = Self.message(error) }
    }

    private static func message(_ error: Error) -> String {
        if case SocketFiNativeError.requestFailed(let status, let code, _) = error {
            if status == 401 || status == 403 { return "Sign in again to load this account’s history." }
            if code == "HISTORY_NOT_INDEXED" { return "This account is not indexed yet. Try again shortly." }
            if status == 429 { return "Too many requests. Try again in a minute." }
            return "Transaction history is temporarily unavailable. Pull down or tap Retry."
        }
        if error is URLError { return "Couldn’t connect to history. Check your connection and retry." }
        return "History could not be verified for this account. Please retry."
    }
}
