import AVFoundation
import Foundation

@main
struct NodebayProcessAudioEqualizerHarness {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func signal(interleaved: Bool, frames: AVAudioFrameCount = 4_096) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                   channels: 2, interleaved: interleaved)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for audio in buffers {
            let values = audio.mData!.assumingMemoryBound(to: Float.self)
            let channels = Int(audio.mNumberChannels)
            for frame in 0..<Int(frames) {
                for channel in 0..<channels {
                    values[frame * channels + channel] = Float(sin(2 * Double.pi * 1_000 * Double(frame) / 48_000)) * 0.25
                }
            }
        }
        return buffer
    }

    static func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        var squares = 0.0
        var count = 0
        for audio in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            let values = audio.mData!.assumingMemoryBound(to: Float.self)
            for index in 0..<(Int(audio.mDataByteSize) / MemoryLayout<Float>.size) {
                require(values[index].isFinite, "output must stay finite")
                squares += Double(values[index] * values[index])
                count += 1
            }
        }
        return sqrt(squares / Double(count))
    }

    static func main() {
        for sourceInterleaved in [false, true] {
            for outputInterleaved in [false, true] {
                let input = signal(interleaved: sourceInterleaved)
                let output = signal(interleaved: outputInterleaved)
                let eq = NodebayRealtimeEqualizer(sampleRate: 48_000, profile: .init(gains: []))
                eq.process(input: input.audioBufferList, output: output.mutableAudioBufferList)
                require(rms(output) == 0, "unmuted probe must not double the original audio")
                require(eq.healthSnapshot().lastSignal != nil, "probe must detect actual samples")
                require(!eq.healthSnapshot().invalidLayout, "interleaved/separate channel mapping must work")
                eq.setRoutesOutput(true)
                eq.process(input: input.audioBufferList, output: output.mutableAudioBufferList)
                let flat = rms(output)
                require(abs(flat - rms(input)) < 0.000001, "flat audio must preserve both channels")
                eq.update(profile: .init(gains: [0, 0, -12, 0, 0]))
                eq.process(input: input.audioBufferList, output: output.mutableAudioBufferList)
                let ratio = rms(output) / flat
                require(ratio < 0.32 && ratio > 0.20, "real process DSP must apply a live 12 dB cut")
                eq.setRoutesOutput(false)
                eq.process(input: input.audioBufferList, output: output.mutableAudioBufferList)
                require(rms(output) == 0, "restored passthrough must silence Nodebay output")
            }
        }

        let stereo = signal(interleaved: true)
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: 4_096)!
        mono.frameLength = 4_096
        let eq = NodebayRealtimeEqualizer(sampleRate: 48_000, profile: .init(gains: []))
        eq.setRoutesOutput(true)
        eq.process(input: stereo.audioBufferList, output: mono.mutableAudioBufferList)
        require(eq.healthSnapshot().invalidLayout, "unsupported channel count must fail safely")
        require(rms(mono) == 0, "incompatible output must be cleared")

        let silent = signal(interleaved: false)
        for buffer in UnsafeMutableAudioBufferListPointer(silent.mutableAudioBufferList) {
            memset(buffer.mData!, 0, Int(buffer.mDataByteSize))
        }
        let probe = NodebayRealtimeEqualizer(sampleRate: 48_000, profile: .init(gains: []))
        let output = signal(interleaved: false)
        probe.process(input: silent.audioBufferList, output: output.mutableAudioBufferList)
        require(probe.healthSnapshot().lastSignal == nil, "zero-filled permission-denied buffers cannot authorize muting")
        require(rms(output) == 0, "silent probe output")
        UnsafeMutableAudioBufferListPointer(silent.mutableAudioBufferList)[0].mData!.assumingMemoryBound(to: Float.self)[0] = .nan
        probe.process(input: silent.audioBufferList, output: output.mutableAudioBufferList)
        require(probe.healthSnapshot().invalidLayout, "nonfinite input must fail safely")
        require(rms(output) == 0, "invalid probe output")
        print("Process EQ signal, live update, four channel layouts, silent probe and failure checks passed")
    }
}
