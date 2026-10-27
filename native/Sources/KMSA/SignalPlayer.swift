import AVFAudio

// Substitute an in-memory player when checking triggers, so verification never emits audio.
protocol SignalPlayer: AnyObject {
    var currentDevice: String? { get set }
    var volume: Float { get set }
    var numberOfLoops: Int { get set }
    var delegate: AVAudioPlayerDelegate? { get set }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func stop()
}

extension AVAudioPlayer: SignalPlayer {}

final class SilentCheckPlayer: SignalPlayer {
    var currentDevice: String?
    var volume: Float = 0
    var numberOfLoops = 0
    weak var delegate: AVAudioPlayerDelegate?
    var onPlay: () -> Bool = { false }
    var onPrepare: () -> Bool = { true }
    private(set) var stopped = false
    func prepareToPlay() -> Bool { onPrepare() }
    func play() -> Bool { onPlay() }
    func stop() { stopped = true }
}
