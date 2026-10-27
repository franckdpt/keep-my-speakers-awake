public enum CaptureState: String, Codable, Equatable {
    case clear, microphone, unknown

    public static func detect(audioKnown: Bool, microphoneBusy: Bool) -> CaptureState {
        // A positive microphone observation blocks even if another audio read failed.
        if microphoneBusy { return .microphone }
        if !audioKnown { return .unknown }
        return .clear
    }
}
