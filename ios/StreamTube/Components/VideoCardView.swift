import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%d:%02d", m, s)
    }
}

struct VideoCardView: View {
    let video: FfiVideoItem
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var playerManager: PlayerManager

    var body: some View {
        Button {
            if let playlistId = video.playlistId {
                appState.presentedPlaylistId = playlistId
            } else {
                playerManager.play(video: video)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: video.thumbnail)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16 / 9, contentMode: .fill)
                        default:
                            Rectangle()
                                .fill(Color(white: 0.14))
                                .aspectRatio(16 / 9, contentMode: .fill)
                                .overlay {
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .bottom) {
                        if let progress = video.resumeProgress, progress > 0.02 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.25))
                                    Rectangle()
                                        .fill(Color(hex: 0xFF0033))
                                        .frame(width: geo.size.width * progress)
                                }
                            }
                            .frame(height: 3.5)
                            .clipShape(Capsule())
                        }
                    }

                    if video.isLive {
                        Text("EN VIVO")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(hex: 0xFF0033), in: RoundedRectangle(cornerRadius: 5))
                            .padding(8)
                    } else if let dur = video.durationText, !dur.isEmpty {
                        Text(dur)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 5))
                            .padding(8)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    if let avatar = video.channelAvatar, let url = URL(string: avatar) {
                        Button {
                            if let cid = video.channelId {
                                appState.presentedChannelId = cid
                            }
                        } label: {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color(white: 0.2))
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Circle()
                            .fill(Color(white: 0.2))
                            .frame(width: 36, height: 36)
                            .overlay {
                                Text(String(video.channelName.prefix(1)).uppercased())
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(subtitleText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                appState.addToWatchLater(video)
            } label: {
                Label("Guardar en Ver más tarde", systemImage: "clock")
            }
            Button {
                appState.addToFavorites(video)
            } label: {
                Label("Añadir a Favoritos", systemImage: "heart")
            }
            if let channelId = video.channelId {
                Button {
                    appState.presentedChannelId = channelId
                } label: {
                    Label("Ir al canal", systemImage: "person.crop.circle")
                }
            }
            if let shareURL = URL(string: "https://youtu.be/\(video.id)") {
                ShareLink(item: shareURL) {
                    Label("Compartir enlace", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var subtitleText: String {
        var parts: [String] = []
        if !video.channelName.isEmpty {
            parts.append(video.channelName)
        }
        if let views = video.viewsText, !views.isEmpty {
            parts.append(views)
        }
        if let pub = video.publishedText, !pub.isEmpty {
            parts.append(pub)
        }
        return parts.joined(separator: " • ")
    }
}

struct CompactVideoRow: View {
    let video: FfiVideoItem
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            playerManager.play(video: video)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: video.compactThumbnail ?? video.thumbnail)) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                        } else {
                            Rectangle().fill(Color(white: 0.15)).aspectRatio(16 / 9, contentMode: .fill)
                        }
                    }
                    .frame(width: 148, height: 83)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if let dur = video.durationText, !dur.isEmpty {
                        Text(dur)
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                            .padding(5)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !video.channelName.isEmpty {
                        Text(video.channelName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        if let views = video.viewsText {
                            Text(views)
                        }
                        if let pub = video.publishedText {
                            Text("• \(pub)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                appState.addToWatchLater(video)
            } label: {
                Label("Ver más tarde", systemImage: "clock")
            }
            Button {
                appState.addToFavorites(video)
            } label: {
                Label("Favoritos", systemImage: "heart")
            }
        }
    }
}

struct FeedItemRow: View {
    let item: FfiFeedItem
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch item {
        case .video(let video):
            VideoCardView(video: video)
        case .channel(let channel):
            Button {
                appState.presentedChannelId = channel.id
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: channel.avatar ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color(white: 0.2))
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(channel.name)
                            .font(.subheadline.weight(.semibold))
                        if let subs = channel.subscribersText {
                            Text(subs)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        case .playlist(let playlist):
            Button {
                appState.presentedPlaylistId = playlist.id
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: playlist.thumbnail ?? "")) { img in
                        img.resizable().aspectRatio(16 / 9, contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color(white: 0.16))
                    }
                    .frame(width: 128, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        if let ch = playlist.channelName {
                            Text(ch)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let count = playlist.videoCountText {
                            Text(count)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }
}
