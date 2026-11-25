import SwiftUI

struct ChannelDetailView: View {
    let channelId: String
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var page: FfiChannelPage?
    @State private var items: [FfiFeedItem] = []
    @State private var continuation: String?
    @State private var isLoading = true
    @State private var isSubscribed = false

    var body: some View {
        ScrollView {
            if let page {
                VStack(alignment: .leading, spacing: 14) {
                    if let banner = page.banner, let url = URL(string: banner) {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color(white: 0.14)
                        }
                        .frame(height: 100)
                        .clipped()
                    }

                    HStack(spacing: 14) {
                        AsyncImage(url: URL(string: page.info.avatar ?? "")) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color(white: 0.22))
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(page.info.name)
                                .font(.title3.weight(.bold))
                            if let handle = page.info.handle {
                                Text(handle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let subs = page.info.subscribersText {
                                Text(subs)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    Button {
                        isSubscribed = appState.toggleSubscription(
                            channelId: page.info.id,
                            name: page.info.name,
                            avatar: page.info.avatar
                        )
                    } label: {
                        Text(isSubscribed ? "Suscrito" : "Suscribirse")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(isSubscribed ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSubscribed ? Color(white: 0.2) : Color.white, in: Capsule())
                    }
                    .padding(.horizontal, 16)

                    // Channel Tabs
                    if !page.tabs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(page.tabs.enumerated()), id: \.offset) { _, tab in
                                    CategoryChip(title: tab.title, isSelected: tab.selected) {
                                        Task { await load(params: tab.params) }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    LazyVStack(spacing: 18) {
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                            FeedItemRow(item: item)
                                .onAppear {
                                    if idx >= items.count - 4, let tok = continuation, !isLoading {
                                        Task { await loadMore(token: tok) }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            }
        }
        .navigationTitle(page?.info.name ?? "Canal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cerrar") { dismiss() }
            }
        }
        .task {
            await load(params: nil)
        }
    }

    private func load(params: String?) async {
        isLoading = true
        if let fetched = try? await appState.fetchChannel(channelId: channelId, tabParams: params) {
            page = fetched
            items = fetched.items
            continuation = fetched.continuation
            isSubscribed = fetched.isSubscribed
        }
        isLoading = false
    }

    private func loadMore(token: String) async {
        isLoading = true
        if let more = try? await appState.continueFeed(token: token, source: "browse") {
            items.append(contentsOf: more.items)
            continuation = more.continuation
        }
        isLoading = false
    }
}

struct RemotePlaylistDetailView: View {
    let playlistId: String
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var playerManager: PlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var page: FfiPlaylistPage?
    @State private var videos: [FfiVideoItem] = []
    @State private var continuation: String?
    @State private var isLoading = true

    var body: some View {
        List {
            if let page {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(page.info.title)
                            .font(.headline.weight(.bold))
                        if let author = page.info.channelName {
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let first = videos.first {
                            Button {
                                dismiss()
                                playerManager.play(video: first, playlistId: playlistId)
                            } label: {
                                Label("Reproducir todo (\(videos.count))", systemImage: "play.fill")
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            ForEach(videos, id: \.id) { video in
                CompactVideoRow(video: video)
                    .onTapGesture {
                        dismiss()
                        playerManager.play(video: video, playlistId: playlistId)
                    }
                    .onAppear {
                        if video.id == videos.last?.id, let next = continuation, !isLoading {
                            Task { await loadMore(token: next) }
                        }
                    }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Lista de reproducción")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cerrar") { dismiss() }
            }
        }
        .task {
            if let fetched = try? await appState.fetchRemotePlaylist(playlistId: playlistId) {
                page = fetched
                videos = fetched.videos
                continuation = fetched.continuation
            }
            isLoading = false
        }
    }

    private func loadMore(token: String) async {
        isLoading = true
        if let more = try? await appState.continueFeed(token: token, source: "browse") {
            for item in more.items {
                if case .video(let v) = item {
                    videos.append(v)
                }
            }
            continuation = more.continuation
        }
        isLoading = false
    }
}
