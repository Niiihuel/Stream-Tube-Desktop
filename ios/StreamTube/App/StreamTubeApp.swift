import SwiftUI
import AVFoundation

@main
struct StreamTubeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var playerManager: PlayerManager

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        _playerManager = StateObject(wrappedValue: PlayerManager(client: state.client))
        Self.configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
                .environmentObject(playerManager)
                .preferredColorScheme(.dark)
                .tint(Color(hex: 0xFF0033))
                .onOpenURL { url in
                    Task {
                        await handleIncomingURL(url)
                    }
                }
        }
    }

    /// Configures iOS audio session so ad-free playback continues when the iPhone is locked
    /// or when switching apps (Background Audio + Picture-in-Picture + AirPlay).
    static func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("[StreamTube] AudioSession error: \(error)")
        }
    }

    @MainActor
    private func handleIncomingURL(_ url: URL) async {
        do {
            let target = try await appState.resolveURL(url.absoluteString)
            switch target {
            case .video(let videoId):
                let placeholder = FfiVideoItem(
                    id: videoId,
                    title: "Cargando…",
                    channelName: "",
                    channelId: nil,
                    channelAvatar: nil,
                    thumbnail: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
                    compactThumbnail: nil,
                    durationText: nil,
                    durationSecs: nil,
                    viewsText: nil,
                    publishedText: nil,
                    publishedTs: nil,
                    descriptionSnippet: nil,
                    isLive: false,
                    isShort: false,
                    isUpcoming: false,
                    playlistId: nil,
                    resumeProgress: nil
                )
                playerManager.play(video: placeholder)
            case .channel(let channelId):
                appState.presentedChannelId = channelId
            case .playlist(let playlistId):
                appState.presentedPlaylistId = playlistId
            }
        } catch {
            appState.toastMessage = "No se pudo abrir el enlace: \(error.localizedDescription)"
        }
    }
}
