import SwiftUI
import AVFoundation

struct ShortsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var shorts: [FfiVideoItem] = []
    @State private var continuation: String?
    @State private var activeId: String?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geo in
            if isLoading && shorts.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Cargando Shorts…")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(shorts, id: \.id) { short in
                            ShortPageCell(
                                video: short,
                                isActive: activeId == short.id || (activeId == nil && shorts.first?.id == short.id)
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(short.id)
                            .onAppear {
                                if short.id == shorts.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $activeId)
            }
        }
        .background(Color.black)
        .task {
            if shorts.isEmpty {
                await loadInitial()
            }
        }
    }

    private func loadInitial() async {
        isLoading = true
        if let page = try? await appState.fetchShorts(continuation: nil) {
            shorts = page.videos
            continuation = page.continuation
            activeId = page.videos.first?.id
        }
        isLoading = false
    }

    private func loadMore() async {
        guard let token = continuation, !isLoading else { return }
        isLoading = true
        if let page = try? await appState.fetchShorts(continuation: token) {
            let existing = Set(shorts.map(\.id))
            shorts.append(contentsOf: page.videos.filter { !existing.contains($0.id) })
            continuation = page.continuation
        }
        isLoading = false
    }
}

struct ShortPageCell: View {
    let video: FfiVideoItem
    let isActive: Bool
    @EnvironmentObject private var appState: AppState

    @State private var shortPlayer = AVPlayer()
    @State private var title: String = ""
    @State private var channelName: String = ""
    @State private var channelId: String?
    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black

            if isActive {
                AVPlayerRepresentable(player: shortPlayer, showsPlaybackControls: false)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if shortPlayer.timeControlStatus == .playing {
                            shortPlayer.pause()
                        } else {
                            shortPlayer.play()
                        }
                    }
            } else {
                AsyncImage(url: URL(string: video.thumbnail)) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Color.black
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 180)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                if !channelName.isEmpty {
                    Button {
                        if let channelId {
                            appState.presentedChannelId = channelId
                        }
                    } label: {
                        Text("@\(channelName)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 26)
        }
        .task(id: isActive) {
            guard isActive else {
                shortPlayer.pause()
                return
            }
            title = video.title
            channelName = video.channelName
            channelId = video.channelId
            let c = appState.client
            let vid = video.id
            async let pb = Task.detached(priority: .userInitiated) {
                try? c.resolvePlayback(videoId: vid, maxHeight: 1080, preferredAudio: nil)
            }.value
            async let wd = Task.detached(priority: .utility) {
                try? c.watchDetails(videoId: vid, playlistId: nil)
            }.value
            if let bundle = await pb, let url = URL(string: bundle.streamUrl) {
                isLoading = false
                if title.isEmpty { title = bundle.title }
                if channelName.isEmpty { channelName = bundle.author }
                if channelId == nil && !bundle.channelId.isEmpty { channelId = bundle.channelId }
                shortPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
                shortPlayer.play()
            }
            if let info = await wd {
                title = info.title
                channelName = info.channel.name
                channelId = info.channel.id
            }
        }
        .onDisappear {
            shortPlayer.pause()
        }
    }
}
