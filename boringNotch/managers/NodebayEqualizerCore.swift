import Foundation

enum NodebayEqualizerPreset: String, CaseIterable, Identifiable, Codable {
    case flat = "Flat"
    case bassBoost = "Bass Boost"
    case vocal = "Vocal"
    case electronic = "Electronic"
    case custom = "Custom"

    var id: String { rawValue }
}

enum NodebayEqualizerTone: Int, CaseIterable, Identifiable, Sendable {
    case bass
    case mid
    case treble

    var id: Int { rawValue }

    var bandIndices: [Int] {
        switch self {
        case .bass: [0, 1]
        case .mid: [2]
        case .treble: [3, 4]
        }
    }

    var name: String {
        switch self {
        case .bass: "Bass"
        case .mid: "Mid"
        case .treble: "Treble"
        }
    }
}

enum NodebayEqualizerCurveScale {
    static func normalizedY(for gain: Float) -> Float {
        let range = NodebayEqualizerProfile.gainRange
        let clamped = min(range.upperBound, max(range.lowerBound, gain))
        if clamped >= 0 {
            return 0.5 - 0.5 * (clamped / range.upperBound)
        }
        return 0.5 + 0.5 * (clamped / range.lowerBound)
    }

    static func gain(atNormalizedY normalizedY: Float) -> Float {
        let y = min(1, max(0, normalizedY))
        let range = NodebayEqualizerProfile.gainRange
        if y <= 0.5 {
            return range.upperBound * ((0.5 - y) / 0.5)
        }
        return range.lowerBound * ((y - 0.5) / 0.5)
    }
}

struct NodebayEqualizerProfile: Equatable, Sendable {
    static let frequencies: [Float] = [60, 250, 1_000, 4_000, 12_000]
    static let gainRange: ClosedRange<Float> = -12...6

    let gains: [Float]

    init(gains: [Float]) {
        self.gains = (0..<Self.frequencies.count).map { index in
            min(Self.gainRange.upperBound, max(Self.gainRange.lowerBound, gains.indices.contains(index) ? gains[index] : 0))
        }
    }

    var headroom: Float {
        -max(0, gains.max() ?? 0)
    }

    func gain(for tone: NodebayEqualizerTone) -> Float {
        let values = tone.bandIndices.compactMap { gains.indices.contains($0) ? gains[$0] : nil }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    func setting(_ value: Float, for tone: NodebayEqualizerTone) -> Self {
        var updated = gains
        let clamped = min(Self.gainRange.upperBound, max(Self.gainRange.lowerBound, value))
        for index in tone.bandIndices where updated.indices.contains(index) {
            updated[index] = clamped
        }
        return Self(gains: updated)
    }

    static func preset(_ preset: NodebayEqualizerPreset, custom: [Float]) -> Self {
        switch preset {
        case .flat: .init(gains: [0, 0, 0, 0, 0])
        case .bassBoost: .init(gains: [6, 4, 1, -1, -2])
        case .vocal: .init(gains: [-2, 0, 4, 3, 0])
        case .electronic: .init(gains: [4, 2, -1, 2, 4])
        case .custom: .init(gains: custom)
        }
    }
}
