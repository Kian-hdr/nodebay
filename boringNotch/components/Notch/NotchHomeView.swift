//
//  NotchHomeView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool

    var body: some View {
        HStack {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace).frame(width: 120).padding(.all, 5 * (vm.notchSize.height / 190))
            MusicControlsView(horizontalMediaGestureFeedback: horizontalMediaGestureFeedback)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringMusicArea = hovering
        }
        .onDisappear {
            isHoveringMusicArea = false
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened)
            )
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
            .allowsHitTesting(false)
    }
                

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .interpolation(.high)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened)
            )
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork,
           let bundleIdentifier = musicManager.bundleIdentifier, !bundleIdentifier.isEmpty {
            AppIcon(for: bundleIdentifier)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    let horizontalMediaGestureFeedback: CGFloat
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @State private var isHoveringDownload = false
    @State private var showEqualizer = false
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            songInfoAndSlider
            slotToolbar
                .disabled(musicManager.selectableSourceChoices.isEmpty)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MediaSourcePicker()
                .padding(.bottom, 6)
            MarqueeText(musicManager.songTitle.isEmpty
                        ? (musicManager.selectableSourceChoices.isEmpty ? "Nothing playing" : "Untitled media")
                        : musicManager.songTitle,
                        font: .headline, color: .white, frameWidth: width)
            MarqueeText(
                musicManager.artistName,
                font: .headline,
                color: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            .fontWeight(.medium)
            if Defaults[.enableLyrics] {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let currentElapsed: Double = {
                        guard musicManager.isPlaying else { return musicManager.elapsedTime }
                        let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                        let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                        return min(max(progressed, 0), musicManager.songDuration)
                    }()
                    let lyricDisplay: (line: String, displayDuration: Double?, animationID: Double?) = {
                        if LyricsService.shared.isFetchingLyrics { return ("Loading lyrics…", nil, nil) }
                        if !LyricsService.shared.syncedLyrics.isEmpty {
                            let context = LyricsService.shared.lyricLineContext(at: currentElapsed)
                            let displayDuration = context.endTime.map { max($0 - currentElapsed, 0) }
                            return (context.text, displayDuration, context.startTime)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        let line = trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                        return (line, nil, nil)
                    }()
                    let line = lyricDisplay.line
                    let isPersian = line.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    let lyricFont: Font = isPersian
                        ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize)
                        : .subheadline
                    TimedLyricText(
                        line,
                        font: lyricFont,
                        nsFont: .subheadline,
                        color: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                        displayDuration: lyricDisplay.displayDuration,
                        animationID: lyricDisplay.animationID,
                        frameWidth: width
                    )
                    .lineLimit(1)
                    .opacity(musicManager.isPlaying ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var currentMediaDownloadButton: some View {
        Button {
            Task { await musicManager.downloadActiveMediaToNodebay() }
        } label: {
            ZStack {
                Circle()
                    .fill(isHoveringDownload ? Color.gray.opacity(0.2) : .clear)
                if musicManager.isResolvingCurrentMediaDownload {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.body.weight(.medium))
                        .foregroundStyle(isHoveringDownload ? .primary : .secondary)
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(musicManager.isResolvingCurrentMediaDownload)
        .opacity(musicManager.isResolvingCurrentMediaDownload ? 0.65 : 1)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
                isHoveringDownload = hovering
            }
        }
        .help(musicManager.isResolvingCurrentMediaDownload ? "Preparing download…" : "Download current media to Nodebay")
        .accessibilityLabel("Download current media to Nodebay")
        .accessibilityHint("Adds the downloaded file to the Nodebay shelf")
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
            .disabled(musicManager.selectableSourceChoices.isEmpty)
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .overlay(alignment: .trailing) {
            HStack(spacing: 2) {
                EqualizerControl(isPresented: $showEqualizer)
                if musicManager.canDownloadActiveMedia {
                    currentMediaDownloadButton
                }
            }
            .padding(.trailing, 4)
        }
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
        // If calendar and camera are both visible alongside music, hide the edge slots
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
            .scaleEffect(horizontalMediaGestureFeedback > 0 ? 1.12 : 1)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.62), value: horizontalMediaGestureFeedback)
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
            .scaleEffect(horizontalMediaGestureFeedback < 0 ? 1.12 : 1)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.62), value: horizontalMediaGestureFeedback)
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

private struct EqualizerControl: View {
    @Binding var isPresented: Bool
    @ObservedObject private var equalizer = NodebayEqualizerManager.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var isHoveringButton = false
    @State private var isHoveringPopover = false
    @State private var popoverInteractionActive = false
    @State private var dismissTask: Task<Void, Never>?

    private var isAvailable: Bool {
        equalizer.isAvailable(for: musicManager.activeSourceID)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isAvailable && !equalizer.isBypassed ? .primary : .secondary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1 : 0.45)
        .help(isAvailable ? "Equalizer" : "Equalizer unavailable for this source")
        .accessibilityLabel("Equalizer")
        .accessibilityValue(isAvailable ? (equalizer.isBypassed ? "Bypassed" : equalizer.preset.rawValue) : "Unavailable for this source")
        .onHover { hovering in
            isHoveringButton = hovering
            if hovering {
                cancelScheduledDismissal()
            } else {
                scheduleDismissalIfNeeded()
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            EqualizerPopover(source: musicManager.activeSourceID)
                .onHover { hovering in
                    isHoveringPopover = hovering
                    if hovering {
                        cancelScheduledDismissal()
                    } else {
                        scheduleDismissalIfNeeded()
                    }
                }
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                beginPopoverInteractionIfNeeded()
            } else {
                finishPopoverInteractionIfNeeded()
            }
        }
        .onChange(of: musicManager.activeSourceID) { _, _ in
            isPresented = false
        }
        .onDisappear {
            isPresented = false
            finishPopoverInteractionIfNeeded()
        }
    }

    private func cancelScheduledDismissal() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    private func scheduleDismissalIfNeeded() {
        guard isPresented, !isHoveringButton, !isHoveringPopover else { return }
        cancelScheduledDismissal()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isHoveringButton, !isHoveringPopover else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                isPresented = false
            }
        }
    }

    private func beginPopoverInteractionIfNeeded() {
        guard !popoverInteractionActive else { return }
        SharingStateManager.shared.beginInteraction()
        popoverInteractionActive = true
    }

    private func finishPopoverInteractionIfNeeded() {
        cancelScheduledDismissal()
        isHoveringPopover = false
        guard popoverInteractionActive else { return }
        SharingStateManager.shared.endInteraction()
        popoverInteractionActive = false
    }
}

private struct EqualizerPopover: View {
    let source: MusicManager.MediaSourceID
    @ObservedObject private var equalizer = NodebayEqualizerManager.shared

    private var available: Bool { equalizer.isAvailable(for: source) }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                if available {
                    Toggle("Equalizer", isOn: Binding(
                        get: { !equalizer.isBypassed },
                        set: { equalizer.setBypassed(!$0, source: source) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Equalizer")
                    .accessibilityHint("Turns sound adjustments on or off")
                    .help(equalizer.isBypassed ? "Turn equalizer on" : "Turn equalizer off")
                }
                Spacer()
                Button("Reset") { equalizer.reset(source: source) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!available)
                    .accessibilityHint("Returns the sound curve to flat")
            }
            .overlay {
                Text("Equalizer")
                    .font(.headline)
                    .allowsHitTesting(false)
            }

            if available {
                EqualizerCurveEditor(
                    gains: NodebayEqualizerTone.allCases.map { equalizer.profile.gain(for: $0) },
                    onChange: { tone, value in
                        equalizer.setToneGain(value, tone: tone, source: source)
                    }
                )
                .disabled(equalizer.isBypassed)
                .opacity(equalizer.isBypassed ? 0.45 : 1)

                Text("Processing locally")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    "Equalizer Unavailable",
                    systemImage: "waveform.slash",
                    description: Text(equalizer.availabilityMessage(for: source))
                )
                .frame(minHeight: 140)
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}

private struct EqualizerCurveEditor: View {
    let gains: [Float]
    let onChange: (NodebayEqualizerTone, Float) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeTone: NodebayEqualizerTone?
    @FocusState private var focusedToneIndex: Int?

    private let graphHeight: CGFloat = 126
    private let handleDiameter: CGFloat = 22

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(NodebayEqualizerTone.allCases) { tone in
                    VStack(spacing: 1) {
                        Text(tone.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(signedValue(gain(for: tone)))
                            .font(.headline.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            GeometryReader { geometry in
                let points = curvePoints(in: geometry.size)

                ZStack {
                    grid(in: geometry.size)
                    curve(points: points, width: geometry.size.width)

                    ForEach(NodebayEqualizerTone.allCases) { tone in
                        let point = points[tone.rawValue]
                        Circle()
                            .fill(.background)
                            .overlay {
                                Circle().stroke(
                                    activeTone == tone ? Color.accentColor : Color.primary.opacity(0.22),
                                    lineWidth: activeTone == tone ? 2 : 1
                                )
                            }
                            .shadow(color: .black.opacity(0.14), radius: 4, y: 1)
                            .frame(width: handleDiameter, height: handleDiameter)
                            .contentShape(Circle())
                            .position(point)
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .named("equalizerCurve"))
                                    .onChanged { gesture in
                                        activeTone = tone
                                        focusedToneIndex = tone.rawValue
                                        onChange(tone, gain(at: gesture.location.y, height: geometry.size.height))
                                    }
                                    .onEnded { _ in
                                        activeTone = nil
                                        Task { @MainActor in
                                            focusedToneIndex = nil
                                        }
                                    }
                            )
                            .focusable()
                            .focused($focusedToneIndex, equals: tone.rawValue)
                            .accessibilityElement()
                            .accessibilityLabel(tone.name)
                            .accessibilityValue("\(signedValue(gain(for: tone))) decibels")
                            .accessibilityHint("Drag vertically or use VoiceOver to adjust")
                            .accessibilityAdjustableAction { direction in
                                switch direction {
                                case .increment: onChange(tone, gain(for: tone) + 1)
                                case .decrement: onChange(tone, gain(for: tone) - 1)
                                @unknown default: break
                                }
                            }
                    }
                }
                .coordinateSpace(name: "equalizerCurve")
                .animation(reduceMotion || activeTone != nil ? nil : .snappy(duration: 0.22), value: gains)
            }
            .frame(height: graphHeight)
        }
        .onDisappear {
            activeTone = nil
            focusedToneIndex = nil
        }
    }

    private func grid(in size: CGSize) -> some View {
        Canvas { context, _ in
            for row in 0...6 {
                let y = CGFloat(row) * size.height / 6
                var path = Path()
                path.move(to: CGPoint(x: 4, y: y))
                path.addLine(to: CGPoint(x: size.width - 4, y: y))
                context.stroke(
                    path,
                    with: .color(.secondary.opacity(row == 3 ? 0.32 : 0.13)),
                    lineWidth: row == 3 ? 1 : 0.7
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func curve(points: [CGPoint], width: CGFloat) -> some View {
        Canvas { context, _ in
            guard let first = points.first, let last = points.last else { return }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: first.y))
            path.addLine(to: first)
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let midpoint = (previous.x + current.x) / 2
                path.addCurve(
                    to: current,
                    control1: CGPoint(x: midpoint, y: previous.y),
                    control2: CGPoint(x: midpoint, y: current.y)
                )
            }
            path.addLine(to: CGPoint(x: width, y: last.y))
            context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    private func curvePoints(in size: CGSize) -> [CGPoint] {
        NodebayEqualizerTone.allCases.map { tone in
            CGPoint(
                x: size.width * (0.16 + CGFloat(tone.rawValue) * 0.34),
                y: yPosition(for: gain(for: tone), height: size.height)
            )
        }
    }

    private func gain(for tone: NodebayEqualizerTone) -> Float {
        gains.indices.contains(tone.rawValue) ? gains[tone.rawValue] : 0
    }

    private func yPosition(for gain: Float, height: CGFloat) -> CGFloat {
        let normalized = CGFloat(NodebayEqualizerCurveScale.normalizedY(for: gain))
        return handleDiameter / 2 + normalized * (height - handleDiameter)
    }

    private func gain(at y: CGFloat, height: CGFloat) -> Float {
        let usableHeight = max(1, height - handleDiameter)
        let normalized = min(1, max(0, (y - handleDiameter / 2) / usableHeight))
        let value = NodebayEqualizerCurveScale.gain(atNormalizedY: Float(normalized))
        return value.rounded()
    }

    private func signedValue(_ value: Float) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }
}

private struct MediaSourcePicker: View {
    @ObservedObject private var musicManager = MusicManager.shared

    private var sources: [MusicManager.MediaSourceChoice] {
        musicManager.selectableSourceChoices.filter(\.isAvailable)
    }

    var body: some View {
        if !sources.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(sources) { source in
                            sourceTab(source)
                                .id(source.id)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .frame(height: 24)
                .onChange(of: musicManager.activeSourceID) { _, selected in
                    proxy.scrollTo(selected)
                }
                .onAppear { proxy.scrollTo(musicManager.activeSourceID) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Media sources")
        }
    }

    private func sourceTab(_ source: MusicManager.MediaSourceChoice) -> some View {
        let selected = source.id == musicManager.activeSourceID
        return Button {
            musicManager.selectMediaSource(source.id)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selected ? "checkmark" : (source.isPlaying ? "speaker.wave.2.fill" : "play.rectangle"))
                    .font(.caption2)
                Text(tabTitle(source))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150)
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(selected ? Color.accentColor : Color.secondary)
        .help(sourceLabel(source))
        .accessibilityLabel(sourceLabel(source))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sourceLabel(_ source: MusicManager.MediaSourceChoice) -> String {
        let activity = source.isPlaying ? "Playing" : "Paused"
        let track = source.title.isEmpty ? "" : ": \(source.title)"
        return "\(source.displayName), \(activity)\(track)"
    }

    private func tabTitle(_ source: MusicManager.MediaSourceChoice) -> String {
        if case .browserTab = source.id, !source.title.isEmpty {
            return source.title
        }
        return source.displayName
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: musicManager.volumeControlSupported ? AudioOutputRouteResolver.shared.volumeSymbol(for: CGFloat(volumeSliderValue)) : "speaker.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool

    var body: some View {
        mainContent
            .transition(.opacity)
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: (shouldShowCamera && Defaults[.showCalendar]) ? 10 : 15) {
            MusicPlayerView(
                albumArtNamespace: albumArtNamespace,
                horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
                isHoveringMusicArea: $isHoveringMusicArea
            )

            if Defaults[.showCalendar] {
                CalendarView()
                    .frame(width: shouldShowCamera ? 170 : 215)
                    .onHover { isHovering in
                        vm.isHoveringCalendar = isHovering
                    }
                    .environmentObject(vm)
                    .transition(.opacity)
            }

            if shouldShowCamera {
                CameraPreviewView(webcamManager: webcamManager)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: shouldShowCamera)
            }
        }
        .transition(.opacity)
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void


    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0...duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                    : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(
                Defaults[.playerColorTinting]
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
            )
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    func timeString(from seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
