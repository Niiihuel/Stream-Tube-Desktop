import SwiftUI
import AVKit

/// Native iOS AVPlayerViewController wrapper with Picture-in-Picture (PiP),
/// AirPlay, native subtitle/audio track menus, and hardware-accelerated playback.
struct AVPlayerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    var showsPlaybackControls: Bool = true

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        uiViewController.showsPlaybackControls = showsPlaybackControls
    }
}
