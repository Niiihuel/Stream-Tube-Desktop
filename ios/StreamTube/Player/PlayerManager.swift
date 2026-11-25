import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Controls ad-free HLS playback via AVPlayer, automatic SponsorBlock skipping,
/// Lock Screen / Dynamic Island Now Playing controls, and resume progress persistence.
@MainActor
final class PlayerManager: ObservableObject {
    nonisolated let client: StreamTubeClient
    let player = AVPlayer()

    @Published var currentVideo: FfiVideoItem?
    @Published var bundle: FfiPlaybackBundle?
    @Published var details: FfiWatchDetails?
    @Published var isLoadingStream = false
    @Published var isLoadingDetails = false
    @Published var errorMessage: String?
    @Published var isWatchSheetExpanded = false

    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var selectedHeight: UInt32 = 0
    @Published var selectedAudio: String?
    @Published var playbackSpeed: Double = 1.0
    @Published var sponsorSkipBanner: String?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var skippedSegmentUUIDs = Set<String>()
    private var lastProgressSave: TimeInterval = 0
    private var loadTask: Task<Void, Never>?

    init(client: StreamTubeClient) {
        self.client = client
        player.allowsExternalPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true
        setupPeriodicObserver()
        setupRemoteTransportControls()
    }

    func play(video: FfiVideoItem, playlistId: String? = nil) {
        loadTask?.cancel()
        if let prev = currentVideo {
            client.recordWatchStop(videoId: prev.id, progressSecs: currentTime)
        }

        currentVideo = video
        details = nil
        bundle = nil
        errorMessage = nil
        sponsorSkipBanner = nil
        skippedSegmentUUIDs.removeAll()
        currentTime = 0
        duration = Double(video.durationSecs ?? 0)
        isWatchSheetExpanded = true
        isLoadingStream = true
        isLoadingDetails = true

        player.pause()
        player.replaceCurrentItem(with: nil)

        let c = client
        let videoId = video.id
        let initialQuality = c.getSettings().defaultQuality

        loadTask = Task {
            // Launch stream extraction and watch details (SponsorBlock + RYD + Related) concurrently
            async let streamTask: Result<FfiPlaybackBundle, Error> = Task.detached(priority: .userInitiated) {
                Result { try c.resolvePlayback(videoId: videoId, maxHeight: initialQuality, preferredAudio: nil) }
            }.value

            async let detailsTask: Result<FfiWatchDetails, Error> = Task.detached(priority: .userInitiated) {
                Result { try c.watchDetails(videoId: videoId, playlistId: playlistId) }
            }.value

            let streamRes = await streamTask
            guard !Task.isCancelled else { return }
            isLoadingStream = false

            switch streamRes {
            case .success(let resolved):
                bundle = resolved
                selectedHeight = resolved.selectedMaxHeight
                selectedAudio = resolved.selectedAudio
                playbackSpeed = resolved.playbackSpeed
                if resolved.durationSecs > 0 {
                    duration = Double(resolved.durationSecs)
                }
                startAVPlayer(url: resolved.streamUrl, fallbackUrl: resolved.directHlsUrl, seekTo: resolved.resumePositionSecs, speed: resolved.playbackSpeed)
                c.recordWatchStart(video: video)
                updateNowPlayingMetadata(title: resolved.title, author: resolved.author, thumbnailUrl: video.thumbnail)
            case .failure(let err):
                errorMessage = err.localizedDescription
            }

            let detailsRes = await detailsTask
            guard !Task.isCancelled else { return }
            isLoadingDetails = false

            if case .success(let watchInfo) = detailsRes {
                details = watchInfo
                if var updated = currentVideo, updated.id == watchInfo.id {
                    updated.title = watchInfo.title
                    if updated.channelName.isEmpty {
                        updated.channelName = watchInfo.channel.name
                    }
                    updated.channelId = watchInfo.channel.id
                    updated.channelAvatar = watchInfo.channel.avatar
                    currentVideo = updated
                    updateNowPlayingMetadata(title: watchInfo.title, author: watchInfo.channel.name, thumbnailUrl: updated.thumbnail)
                }
            }
        }
    }

    private func startAVPlayer(url: String, fallbackUrl: String?, seekTo: Double, speed: Double) {
        guard let streamURL = URL(string: url) else {
            errorMessage = "URL de stream inválida"
            return
        }
        let asset = AVURLAsset(url: streamURL)
        let item = AVPlayerItem(asset: asset)

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }

        player.replaceCurrentItem(with: item)
        if seekTo > 1.0 {
            let target = CMTime(seconds: seekTo, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
        player.rate = Float(speed)
        isPlaying = true
    }

    func switchQuality(height: UInt32) {
        guard let videoId = currentVideo?.id else { return }
        let savedTime = currentTime
        let wasPlaying = isPlaying
        let audio = selectedAudio
        let speed = playbackSpeed
        selectedHeight = height

        let c = client
        Task {
            do {
                let newUrl = try await Task.detached(priority: .userInitiated) {
                    try c.switchPlaybackStream(videoId: videoId, maxHeight: height, preferredAudio: audio)
                }.value
                startAVPlayer(url: newUrl, fallbackUrl: bundle?.directHlsUrl, seekTo: savedTime, speed: speed)
                if !wasPlaying {
                    player.pause()
                    isPlaying = false
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func switchAudioTrack(_ trackName: String?) {
        guard let videoId = currentVideo?.id else { return }
        let savedTime = currentTime
        let height = selectedHeight
        let speed = playbackSpeed
        selectedAudio = trackName

        let c = client
        Task {
            do {
                let newUrl = try await Task.detached(priority: .userInitiated) {
                    try c.switchPlaybackStream(videoId: videoId, maxHeight: height, preferredAudio: trackName)
                }.value
                startAVPlayer(url: newUrl, fallbackUrl: bundle?.directHlsUrl, seekTo: savedTime, speed: speed)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func setSpeed(_ speed: Double) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = Float(speed)
        }
        if let channelId = details?.channel.id ?? currentVideo?.channelId,
           !channelId.isEmpty,
           client.getSettings().rememberSpeedPerChannel {
            client.setChannelSpeed(channelId: channelId, speed: speed)
        }
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = Float(playbackSpeed)
            isPlaying = true
        }
        syncNowPlayingPlaybackState()
    }

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        syncNowPlayingPlaybackState()
    }

    func closePlayer() {
        if let v = currentVideo {
            client.recordWatchStop(videoId: v.id, progressSecs: currentTime)
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentVideo = nil
        bundle = nil
        details = nil
        isPlaying = false
        isWatchSheetExpanded = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func handlePlaybackEnded() {
        isPlaying = false
        guard client.getSettings().autoplayNext,
              let related = details?.related else { return }
        for item in related {
            if case .video(let nextVideo) = item, !nextVideo.isShort {
                play(video: nextVideo)
                break
            }
        }
    }

    // MARK: - SponsorBlock Periodic Monitor & Progress Persistence

    private func setupPeriodicObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cmTime in
            Task { @MainActor in
                self?.onTick(cmTime)
            }
        }
    }

    private func onTick(_ cmTime: CMTime) {
        let secs = cmTime.seconds
        guard secs.isFinite && secs >= 0 else { return }
        currentTime = secs

        if let itemDur = player.currentItem?.duration.seconds, itemDur.isFinite && itemDur > 0 {
            duration = itemDur
        }
        isPlaying = player.timeControlStatus == .playing

        // 1. Automatic SponsorBlock skipping
        if let segments = details?.sponsorSegments, !segments.isEmpty {
            for seg in segments where seg.action == "skip" {
                if secs >= seg.startSecs && secs < seg.endSecs - 0.35 {
                    let target = seg.endSecs
                    // Allow re-skipping if user manually scrubbed far back, but avoid tight seek loops
                    if !skippedSegmentUUIDs.contains(seg.uuid) || (secs - seg.startSecs) < 1.0 {
                        skippedSegmentUUIDs.insert(seg.uuid)
                        seek(to: target)
                        client.markSponsorViewed(uuid: seg.uuid)
                        if client.getSettings().sbNotify {
                            showSponsorToast("SponsorBlock saltó: \(seg.categoryTitle)")
                        }
                        break
                    }
                }
            }
        }

        // 2. Persist watch progress every 5 seconds
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastProgressSave >= 5.0, let videoId = currentVideo?.id {
            lastProgressSave = now
            client.recordWatchProgress(
                videoId: videoId,
                progressSecs: secs,
                durationSecs: duration,
                playing: isPlaying
            )
            syncNowPlayingPlaybackState()
        }
    }

    private func showSponsorToast(_ text: String) {
        sponsorSkipBanner = text
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if sponsorSkipBanner == text {
                sponsorSkipBanner = nil
            }
        }
    }

    // MARK: - iOS Lock Screen / Control Center / Dynamic Island

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.player.play()
                self.player.rate = Float(self.playbackSpeed)
                self.isPlaying = true
                self.syncNowPlayingPlaybackState()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.player.pause()
                self.isPlaying = false
                self.syncNowPlayingPlaybackState()
            }
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.seek(to: self.currentTime + 10)
            }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.seek(to: self.currentTime - 10)
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self.seek(to: posEvent.positionTime)
            }
            return .success
        }
    }

    private func updateNowPlayingMetadata(title: String, author: String, thumbnailUrl: String) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = author
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let url = URL(string: thumbnailUrl) {
            Task.detached(priority: .utility) {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                await MainActor.run {
                    var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    current[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                }
            }
        }
    }

    private func syncNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
