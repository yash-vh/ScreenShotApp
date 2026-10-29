import AppKit
import AudioToolbox
import AVFoundation

/// Manages feedback sounds for screen captures and actions using the official macOS screenshot sound.
@MainActor
public enum SoundManager {
    private static let soundURL: URL? = {
        // 1. Try bundled app resource first
        if let bundledURL = Bundle.main.url(forResource: "ScreenCapture", withExtension: "aif") {
            return bundledURL
        }
        // 2. Try macOS system CoreAudio sound directory
        let systemPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        if FileManager.default.fileExists(atPath: systemPath) {
            return URL(fileURLWithPath: systemPath)
        }
        return nil
    }()

    private static var systemSoundID: SystemSoundID? = {
        guard let url = soundURL else { return nil }
        var soundID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        return status == noErr ? soundID : nil
    }()

    private static var audioPlayer: AVAudioPlayer? = {
        guard let url = soundURL else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }()

    /// Plays the authentic macOS camera shutter sound.
    public static func playShutterSound() {
        if let soundID = systemSoundID {
            AudioServicesPlaySystemSound(soundID)
            return
        }
        if let player = audioPlayer {
            player.currentTime = 0
            player.play()
            return
        }
        NSSound.beep()
    }
}
