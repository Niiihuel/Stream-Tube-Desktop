import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var playerManager: PlayerManager
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("Inicio", systemImage: "house.fill")
                    }
                    .tag(0)

                if !appState.settings.hideShorts {
                    ShortsView()
                        .tabItem {
                            Label("Shorts", systemImage: "bolt.square.fill")
                        }
                        .tag(1)
                }

                SubscriptionsView()
                    .tabItem {
                        Label("Suscripciones", systemImage: "rectangle.stack.person.crop.fill")
                    }
                    .tag(2)

                SearchView()
                    .tabItem {
                        Label("Buscar", systemImage: "magnifyingglass")
                    }
                    .tag(3)

                LibraryAndSettingsView()
                    .tabItem {
                        Label("Biblioteca", systemImage: "folder.fill")
                    }
                    .tag(4)
            }

            if let current = playerManager.currentVideo, !playerManager.isWatchSheetExpanded {
                MiniPlayerBar(video: current)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 54)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let toast = appState.toastMessage {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, playerManager.currentVideo != nil ? 120 : 66)
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $playerManager.isWatchSheetExpanded) {
            WatchView()
                .environmentObject(appState)
                .environmentObject(playerManager)
        }
        .sheet(isPresented: Binding(
            get: { appState.presentedChannelId != nil },
            set: { if !$0 { appState.presentedChannelId = nil } }
        )) {
            if let channelId = appState.presentedChannelId {
                NavigationStack {
                    ChannelDetailView(channelId: channelId)
                }
                .environmentObject(appState)
                .environmentObject(playerManager)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.presentedPlaylistId != nil },
            set: { if !$0 { appState.presentedPlaylistId = nil } }
        )) {
            if let playlistId = appState.presentedPlaylistId {
                NavigationStack {
                    RemotePlaylistDetailView(playlistId: playlistId)
                }
                .environmentObject(appState)
                .environmentObject(playerManager)
            }
        }
    }
}

struct MiniPlayerBar: View {
    let video: FfiVideoItem
    @EnvironmentObject private var playerManager: PlayerManager

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: video.compactThumbnail ?? video.thumbnail)) { img in
                img.resizable().aspectRatio(16 / 9, contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color(white: 0.2))
            }
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(video.channelName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                playerManager.togglePlayPause()
            } label: {
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Button {
                playerManager.closePlayer()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottom) {
            if playerManager.duration > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color(hex: 0xFF0033))
                        .frame(width: geo.size.width * min(1, max(0, playerManager.currentTime / playerManager.duration)))
                }
                .frame(height: 2)
                .clipShape(Capsule())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            playerManager.isWatchSheetExpanded = true
        }
    }
}
