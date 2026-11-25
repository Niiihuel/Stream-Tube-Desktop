import SwiftUI

struct WatchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var playerManager: PlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var showDescription = false
    @State private var showComments = false
    @State private var showPlaylistPicker = false
    @State private var showLiveChat = false
    @State private var userRating: Int8 = 0
    @State private var isSubscribed = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar for minimizing to miniplayer
            HStack {
                Button {
                    playerManager.isWatchSheetExpanded = false
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                }

                Spacer()

                if let bundle = playerManager.bundle {
                    // Quality selector
                    Menu {
                        Button {
                            playerManager.switchQuality(height: 0)
                        } label: {
                            Label("Auto (Adaptativo)", systemImage: playerManager.selectedHeight == 0 ? "checkmark" : "")
                        }
                        ForEach(bundle.qualities, id: \.height) { q in
                            Button {
                                playerManager.switchQuality(height: q.height)
                            } label: {
                                Label(q.label, systemImage: playerManager.selectedHeight == q.height ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Text(playerManager.selectedHeight == 0 ? "Auto" : "\(playerManager.selectedHeight)p")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.18), in: Capsule())
                    }

                    // Audio language selector (when dubbed tracks exist)
                    if bundle.audioTracks.count > 1 {
                        Menu {
                            ForEach(bundle.audioTracks, id: \.displayName) { track in
                                Button {
                                    playerManager.switchAudioTrack(track.displayName)
                                } label: {
                                    Label(
                                        track.isOriginal ? "\(track.displayName) (Original)" : track.displayName,
                                        systemImage: playerManager.selectedAudio == track.displayName ? "checkmark" : "waveform"
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "globe")
                                .font(.subheadline)
                                .padding(7)
                                .background(Color(white: 0.18), in: Circle())
                        }
                    }

                    // Speed selector
                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { spd in
                            Button {
                                playerManager.setSpeed(spd)
                            } label: {
                                Label(
                                    String(format: "%.2gx", spd),
                                    systemImage: abs(playerManager.playbackSpeed - spd) < 0.01 ? "checkmark" : ""
                                )
                            }
                        }
                    } label: {
                        Text(String(format: "%.2gx", playerManager.playbackSpeed))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.18), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 8)
            .background(Color.black)

            // Video Player Area
            ZStack(alignment: .top) {
                Color.black
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        if playerManager.isLoadingStream {
                            ProgressView()
                                .tint(.white)
                        } else if let err = playerManager.errorMessage {
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text(err)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                if let v = playerManager.currentVideo {
                                    Button("Reintentar") {
                                        appState.client.invalidateStream(videoId: v.id)
                                        playerManager.play(video: v)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                        } else {
                            AVPlayerRepresentable(player: playerManager.player)
                        }
                    }

                // SponsorBlock Live Skip Banner
                if let banner = playerManager.sponsorSkipBanner {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.end.fill")
                            .foregroundStyle(.green)
                        Text(banner)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            // SponsorBlock Segment Bar under Video
            if let segments = playerManager.details?.sponsorSegments,
               !segments.isEmpty,
               playerManager.duration > 0 {
                SponsorTimelineBar(segments: segments, duration: playerManager.duration)
                    .frame(height: 4)
            }

            // Metadata, Actions, Chapters & Related
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let title = playerManager.details?.title ?? playerManager.currentVideo?.title ?? ""
                    Text(title)
                        .font(.headline.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    if let details = playerManager.details {
                        HStack(spacing: 8) {
                            if !details.viewsText.isEmpty {
                                Text(details.viewsText)
                            }
                            if !details.dateText.isEmpty {
                                Text("• \(details.dateText)")
                            }
                            Spacer()
                            Button(showDescription ? "Ocultar info" : "Más info") {
                                withAnimation { showDescription.toggle() }
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                        if showDescription && !details.description.isEmpty {
                            Text(details.description)
                                .font(.footnote)
                                .foregroundStyle(.primary.opacity(0.9))
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                        }

                        // Channel Row + Subscribe Button
                        HStack(spacing: 10) {
                            Button {
                                let cid = details.channel.id
                                if !cid.isEmpty {
                                    playerManager.isWatchSheetExpanded = false
                                    dismiss()
                                    appState.presentedChannelId = cid
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    AsyncImage(url: URL(string: details.channel.avatar ?? "")) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        Circle().fill(Color(white: 0.2))
                                    }
                                    .frame(width: 38, height: 38)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(details.channel.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        if let subs = details.channel.subscribersText, !appState.settings.hideSubscriberCounts {
                                            Text(subs)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            if !details.channel.id.isEmpty {
                                Button {
                                    isSubscribed = appState.toggleSubscription(
                                        channelId: details.channel.id,
                                        name: details.channel.name,
                                        avatar: details.channel.avatar
                                    )
                                } label: {
                                    Text(isSubscribed ? "Suscrito" : "Suscribirse")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(isSubscribed ? .white : .black)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(isSubscribed ? Color(white: 0.2) : Color.white, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)

                        // Action Pills: Like / Return YouTube Dislike / Save / Comments / Live Chat / Share
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // Like + RYD Dislike pill
                                HStack(spacing: 12) {
                                    Button {
                                        let next: Int8 = userRating == 1 ? 0 : 1
                                        userRating = next
                                        appState.client.setRating(videoId: details.id, rating: next)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: userRating == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                                            Text(details.votes?.likesCompact ?? details.likesText ?? "Me gusta")
                                        }
                                    }

                                    Divider().frame(height: 14)

                                    Button {
                                        let next: Int8 = userRating == -1 ? 0 : -1
                                        userRating = next
                                        appState.client.setRating(videoId: details.id, rating: next)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: userRating == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                            if let ryd = details.votes {
                                                Text(ryd.dislikesCompact)
                                            }
                                        }
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(white: 0.15), in: Capsule())

                                Button {
                                    showPlaylistPicker = true
                                } label: {
                                    Label("Guardar", systemImage: "plus.rectangle.on.rectangle")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(white: 0.15), in: Capsule())
                                }

                                if !appState.settings.hideComments, details.commentsToken != nil {
                                    Button {
                                        showComments = true
                                    } label: {
                                        Label(
                                            details.commentCountText ?? "Comentarios",
                                            systemImage: "bubble.left.and.bubble.right"
                                        )
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(white: 0.15), in: Capsule())
                                    }
                                }

                                if details.liveChatTopToken != nil {
                                    Button {
                                        showLiveChat = true
                                    } label: {
                                        Label("Chat en vivo", systemImage: "dot.radiowaves.left.and.right")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color(white: 0.15), in: Capsule())
                                    }
                                }

                                if let shareURL = URL(string: "https://youtu.be/\(details.id)") {
                                    ShareLink(item: shareURL) {
                                        Label("Compartir", systemImage: "square.and.arrow.up")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color(white: 0.15), in: Capsule())
                                    }
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                        }

                        // Chapters Horizontal Strip
                        if !details.chapters.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Capítulos")
                                    .font(.subheadline.weight(.bold))
                                    .padding(.horizontal, 16)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(Array(details.chapters.enumerated()), id: \.offset) { _, ch in
                                            Button {
                                                playerManager.seek(to: ch.startSecs)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(formatTime(ch.startSecs))
                                                        .font(.caption2.monospacedDigit().weight(.bold))
                                                        .foregroundStyle(Color(hex: 0xFF0033))
                                                    Text(ch.title)
                                                        .font(.caption)
                                                        .foregroundStyle(.primary)
                                                        .lineLimit(2)
                                                }
                                                .frame(width: 150, alignment: .leading)
                                                .padding(10)
                                                .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 10))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        // Related Videos
                        if !appState.settings.hideRelated && !details.related.isEmpty {
                            Divider().padding(.horizontal, 16)
                            Text("Relacionados")
                                .font(.subheadline.weight(.bold))
                                .padding(.horizontal, 16)

                            LazyVStack(spacing: 12) {
                                ForEach(Array(details.related.enumerated()), id: \.offset) { _, item in
                                    if case .video(let v) = item {
                                        CompactVideoRow(video: v)
                                    } else {
                                        FeedItemRow(item: item)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    } else if playerManager.isLoadingDetails {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: playerManager.details?.id) { _, _ in
            if let d = playerManager.details {
                userRating = d.userRating
                isSubscribed = d.isSubscribed
            }
        }
        .sheet(isPresented: $showComments) {
            if let token = playerManager.details?.commentsToken {
                CommentsSheetView(
                    initialToken: token,
                    topToken: playerManager.details?.commentsTopToken,
                    newestToken: playerManager.details?.commentsNewestToken
                )
                .environmentObject(appState)
            }
        }
        .sheet(isPresented: $showLiveChat) {
            if let token = playerManager.details?.liveChatTopToken {
                LiveChatSheetView(initialToken: token)
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: $showPlaylistPicker) {
            if let video = playerManager.currentVideo {
                AddToPlaylistSheet(video: video)
                    .environmentObject(appState)
            }
        }
    }
}

extension FfiSettings {
    var hideSubscriberCounts: Bool { false }
}

struct SponsorTimelineBar: View {
    let segments: [FfiSponsorSegment]
    let duration: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(white: 0.18))
                ForEach(segments, id: \.uuid) { seg in
                    let startRatio = max(0, min(1, seg.startSecs / duration))
                    let endRatio = max(startRatio, min(1, seg.endSecs / duration))
                    Rectangle()
                        .fill(Color(hex: seg.colorRgb))
                        .frame(width: max(2, geo.size.width * (endRatio - startRatio)))
                        .offset(x: geo.size.width * startRatio)
                }
            }
        }
    }
}

struct CommentsSheetView: View {
    let initialToken: String
    let topToken: String?
    let newestToken: String?
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var comments: [FfiComment] = []
    @State private var continuation: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(comments, id: \.id) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            AsyncImage(url: URL(string: c.authorAvatar ?? "")) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color(white: 0.25))
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())

                            Text(c.author)
                                .font(.caption.weight(.bold))
                            if c.isCreator {
                                Text("Creador")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: 0xFF0033), in: Capsule())
                            }
                            Spacer()
                            Text(c.published)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Text(c.text)
                            .font(.footnote)

                        if !c.likes.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.thumbsup")
                                Text(c.likes)
                                if c.hearted {
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .onAppear {
                        if c.id == comments.last?.id, let next = continuation, !isLoading {
                            Task { await loadPage(token: next, reset: false) }
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
            .navigationTitle("Comentarios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if topToken != nil || newestToken != nil {
                        Menu("Ordenar") {
                            if let topToken {
                                Button("Principales") {
                                    Task { await loadPage(token: topToken, reset: true) }
                                }
                            }
                            if let newestToken {
                                Button("Más recientes") {
                                    Task { await loadPage(token: newestToken, reset: true) }
                                }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task {
                if comments.isEmpty {
                    await loadPage(token: initialToken, reset: true)
                }
            }
        }
    }

    private func loadPage(token: String, reset: Bool) async {
        isLoading = true
        if let page = try? await appState.fetchComments(token: token) {
            if reset {
                comments = page.comments
            } else {
                comments.append(contentsOf: page.comments)
            }
            continuation = page.continuation
        }
        isLoading = false
    }
}

struct LiveChatSheetView: View {
    let initialToken: String
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [FfiChatMessage] = []

    var body: some View {
        NavigationStack {
            List(messages, id: \.id) { msg in
                HStack(alignment: .top, spacing: 8) {
                    Text(msg.author)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(msg.role == "owner" ? .yellow : (msg.role == "moderator" ? .blue : .secondary))
                    Text(msg.text)
                        .font(.caption)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Chat en vivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task {
                var nextToken: String? = initialToken
                while !Task.isCancelled, let tok = nextToken {
                    let c = appState.client
                    guard let batch = try? await Task.detached(priority: .utility, operation: {
                        try c.liveChat(token: tok)
                    }).value else { break }
                    messages.append(contentsOf: batch.messages)
                    if messages.count > 250 {
                        messages.removeFirst(messages.count - 250)
                    }
                    nextToken = batch.nextToken
                    let waitMs = max(1500, min(batch.timeoutMs, 8000))
                    try? await Task.sleep(nanoseconds: waitMs * 1_000_000)
                }
            }
        }
    }
}

struct AddToPlaylistSheet: View {
    let video: FfiVideoItem
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Listas locales") {
                    ForEach(appState.localPlaylists, id: \.id) { pl in
                        let contains = appState.client.localPlaylistContains(playlistId: pl.id, videoId: video.id)
                        Button {
                            if contains {
                                appState.client.removeFromLocalPlaylist(playlistId: pl.id, videoId: video.id)
                            } else {
                                appState.client.addToLocalPlaylist(playlistId: pl.id, video: video)
                            }
                            appState.reloadLocalState()
                        } label: {
                            HStack {
                                Text(pl.name)
                                Spacer()
                                Image(systemName: contains ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(contains ? Color(hex: 0xFF0033) : .secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Nueva lista") {
                    HStack {
                        TextField("Nombre de la lista", text: $newPlaylistName)
                        Button("Crear") {
                            let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            let id = appState.client.createLocalPlaylist(name: name)
                            appState.client.addToLocalPlaylist(playlistId: id, video: video)
                            newPlaylistName = ""
                            appState.reloadLocalState()
                        }
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Guardar video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
