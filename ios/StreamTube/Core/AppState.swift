import Foundation
import SwiftUI

/// Bridges the Rust `StreamTubeClient` (via UniFFI) to SwiftUI off the main thread.
@MainActor
final class AppState: ObservableObject {
    nonisolated let client: StreamTubeClient

    @Published var settings: FfiSettings
    @Published var authStatus: FfiAuthStatus
    @Published var subscriptions: [FfiSubscription] = []
    @Published var localPlaylists: [FfiLocalPlaylist] = []
    @Published var toastMessage: String?
    @Published var presentedChannelId: String?
    @Published var presentedPlaylistId: String?

    init() {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("StreamTube", isDirectory: true)
        let path = supportDir?.path ?? ""
        let coreClient = StreamTubeClient(dataDir: path)
        self.client = coreClient
        self.settings = coreClient.getSettings()
        self.authStatus = coreClient.authStatus()
        self.subscriptions = coreClient.subscriptions()
        self.localPlaylists = coreClient.localPlaylists()
    }

    func reloadLocalState() {
        settings = client.getSettings()
        authStatus = client.authStatus()
        subscriptions = client.subscriptions()
        localPlaylists = client.localPlaylists()
    }

    func updateSettings(_ updated: FfiSettings) {
        client.saveSettings(settings: updated)
        settings = client.getSettings()
    }

    func toggleSubscription(channelId: String, name: String, avatar: String?) -> Bool {
        if client.isSubscribed(channelId: channelId) {
            client.unsubscribe(channelId: channelId)
            subscriptions = client.subscriptions()
            return false
        } else {
            client.subscribe(channelId: channelId, name: name, avatar: avatar)
            subscriptions = client.subscriptions()
            return true
        }
    }

    func isSubscribed(_ channelId: String) -> Bool {
        subscriptions.contains(where: { $0.channelId == channelId })
    }

    func addToWatchLater(_ video: FfiVideoItem) {
        if let watchLater = localPlaylists.first(where: { $0.name == "Watch later" }) ?? localPlaylists.first {
            client.addToLocalPlaylist(playlistId: watchLater.id, video: video)
            localPlaylists = client.localPlaylists()
            showToast("Guardado en Ver más tarde")
        }
    }

    func addToFavorites(_ video: FfiVideoItem) {
        if let fav = localPlaylists.first(where: { $0.name == "Favorites" }) {
            client.addToLocalPlaylist(playlistId: fav.id, video: video)
            localPlaylists = client.localPlaylists()
            showToast("Añadido a Favoritos")
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    // MARK: - Async Off-Main-Thread FFI Wrappers

    func fetchHomeFeed() async throws -> FfiFeedPage {
        let c = client
        return try await Task.detached(priority: .userInitiated) {
            try c.homeFeed()
        }.value
    }

    func fetchExploreFeed(channelId: String) async throws -> FfiFeedPage {
        let c = client
        return try await Task.detached(priority: .userInitiated) {
            try c.exploreFeed(channelId: channelId)
        }.value
    }

    func continueFeed(token: String, source: String) async throws -> FfiFeedPage {
        let c = client
        return try await Task.detached(priority: .userInitiated) {
            try c.continueFeed(continuation: token, source: source)
        }.value
    }

    func fetchShorts(continuation: String?) async throws -> FfiShortsPage {
        let c = client
        return try await Task.detached(priority: .userInitiated) {
            try c.shortsFeed(continuation: continuation)
        }.value
    }

    func refreshSubscriptionsFeed(filter: [String]? = nil) async throws -> FfiRefreshResult {
        let c = client
        let res = try await Task.detached(priority: .userInitiated) {
            try c.refreshSubscriptions(channelFilter: filter)
        }.value
        subscriptions = client.subscriptions()
        return res
    }

    func search(query: String, filter: FfiSearchFilter) async throws -> FfiFeedPage {
        let c = client
        return try await Task.detached(priority: .userInitiated) {
            try c.search(query: query, filter: filter)
        }.value
    }

    func suggestions(for query: String) async -> [String] {
        let c = client
        return await Task.detached(priority: .utility) {
            c.searchSuggestions(query: query)
        }.value
    }

    func fetchChannel(channelId: String, tabParams: String? = nil) async throws -> FfiChannelPage {
        let c = client
        return try await Task.detached(priority: .userInitiated) {
            try c.channelPage(channelId: channelId, tabParams: tabParams)
        }.value
    }

    func fetchRemotePlaylist(playlistId: String) async throws -> FfiPlaylistPage {
        let c = client
        return try await Task.detached(priority: .userInitiated) {
            try c.remotePlaylist(playlistId: playlistId)
        }.value
    }

    func fetchComments(token: String) async throws -> FfiCommentPage {
        let c = client
        return try await Task.detached(priority: .userInitiated) {
            try c.comments(token: token)
        }.value
    }

    func resolveURL(_ url: String) async throws -> FfiResolvedTarget {
        let c = client
        return try await Task.detached(priority: .userInitiated) {
            try c.resolveYoutubeUrl(url: url)
        }.value
    }
}
