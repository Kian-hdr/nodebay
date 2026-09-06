import AVFoundation
import Foundation

let sampleRate = 44_100.0
let frameCount: AVAudioFrameCount = 44_100
let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

func renderedRMS(centerGain: Float) throws -> Float {
    let engine = AVAudioEngine()
    var phase = 0.0
    let increment = 2.0 * Double.pi * 1_000.0 / sampleRate
    let source = AVAudioSourceNode(format: format) { _, _, frames, audioBufferList in
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for frame in 0..<Int(frames) {
            let sample = Float(sin(phase)) * 0.25
            phase += increment
            for buffer in buffers {
                buffer.mData!.assumingMemoryBound(to: Float.self)[frame] = sample
            }
        }
        return noErr
    }
    let equalizer = AVAudioUnitEQ(numberOfBands: 5)
    let frequencies: [Float] = [60, 250, 1_000, 4_000, 12_000]
    for (index, band) in equalizer.bands.enumerated() {
        band.filterType = .parametric
        band.frequency = frequencies[index]
        band.bandwidth = 1
        band.gain = index == 2 ? centerGain : 0
        band.bypass = false
    }
    equalizer.globalGain = 0
    equalizer.bypass = false

    engine.attach(source)
    engine.attach(equalizer)
    engine.connect(source, to: equalizer, format: format)
    engine.connect(equalizer, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
    try engine.start()

    let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096)!
    var remaining = frameCount
    var sumSquares = 0.0
    var samples = 0
    while remaining > 0 {
        let requested = min(remaining, output.frameCapacity)
        let status = try engine.renderOffline(requested, to: output)
        if status == .success, let channel = output.floatChannelData?[0] {
            for index in 0..<Int(output.frameLength) {
                let value = Double(channel[index])
                sumSquares += value * value
                samples += 1
            }
            remaining -= output.frameLength
        } else if status != .insufficientDataFromInputNode {
            throw NSError(domain: "NodebayEQHarness", code: Int(status.rawValue))
        }
    }
    engine.stop()
    return Float(sqrt(sumSquares / Double(samples)))
}

func liveUpdateRMSPair() throws -> (flat: Float, cut: Float) {
    let engine = AVAudioEngine()
    var phase = 0.0
    let increment = 2.0 * Double.pi * 1_000.0 / sampleRate
    let source = AVAudioSourceNode(format: format) { _, _, frames, audioBufferList in
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for frame in 0..<Int(frames) {
            let sample = Float(sin(phase)) * 0.25
            phase += increment
            for buffer in buffers {
                buffer.mData!.assumingMemoryBound(to: Float.self)[frame] = sample
            }
        }
        return noErr
    }
    let equalizer = AVAudioUnitEQ(numberOfBands: 5)
    for (index, band) in equalizer.bands.enumerated() {
        band.filterType = .parametric
        band.frequency = [60, 250, 1_000, 4_000, 12_000][index]
        band.bandwidth = 1
        band.gain = 0
        band.bypass = false
    }
    equalizer.bypass = false
    engine.attach(source)
    engine.attach(equalizer)
    engine.connect(source, to: equalizer, format: format)
    engine.connect(equalizer, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
    try engine.start()

    func renderSecond() throws -> Float {
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096)!
        var remaining = frameCount
        var sumSquares = 0.0
        var samples = 0
        while remaining > 0 {
            let requested = min(remaining, output.frameCapacity)
            let status = try engine.renderOffline(requested, to: output)
            if status == .success, let channel = output.floatChannelData?[0] {
                for index in 0..<Int(output.frameLength) {
                    let value = Double(channel[index])
                    sumSquares += value * value
                    samples += 1
                }
                remaining -= output.frameLength
            } else if status != .insufficientDataFromInputNode {
                throw NSError(domain: "NodebayEQLiveHarness", code: Int(status.rawValue))
            }
        }
        return Float(sqrt(sumSquares / Double(samples)))
    }

    let flat = try renderSecond()
    equalizer.bands[2].gain = -12
    guard engine.isRunning else { fatalError("Live gain update stopped the audio engine") }
    let cut = try renderSecond()
    guard engine.isRunning else { fatalError("Audio engine stopped after rendering the updated gain") }
    engine.stop()
    return (flat, cut)
}

let flat = try renderedRMS(centerGain: 0)
let cut = try renderedRMS(centerGain: -12)
let ratio = cut / flat
guard ratio < 0.32 else {
    fatalError("Expected the 1 kHz EQ cut to attenuate the signal; ratio=\(ratio)")
}
let live = try liveUpdateRMSPair()
let liveRatio = live.cut / live.flat
guard liveRatio < 0.32 else {
    fatalError("Expected a live 1 kHz update to attenuate without restarting; ratio=\(liveRatio)")
}
print(String(format: "AVAudioUnitEQ signal check passed: flat %.6f, cut %.6f, ratio %.3f; live ratio %.3f", flat, cut, ratio, liveRatio))
