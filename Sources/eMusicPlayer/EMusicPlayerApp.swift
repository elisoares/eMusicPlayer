import AppKit
import Combine
import SwiftUI

@main
struct EMusicPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The UI lives in the status item managed by AppDelegate.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = PlayerController()
    private var statusItem: NSStatusItem?
    private var barHost: NSHostingView<AnyView>?
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let mode = Preview.mode {
            Preview.show(mode, player: player)
            return
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PlayerView(player: player))

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let host = NSHostingView(rootView: AnyView(StatusBarView(player: player) { [weak self] in
            self?.togglePopover()
        }))
        item.button?.addSubview(host)
        statusItem = item
        barHost = host
        resizeStatusItem()

        // Resize after every state change (title, time and buttons change the width).
        player.objectWillChange
            .merge(with: NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizeStatusItem() }
            .store(in: &cancellables)
    }

    private func resizeStatusItem() {
        guard let item = statusItem, let host = barHost, let button = item.button else { return }
        let size = host.fittingSize
        item.length = size.width
        host.frame = NSRect(x: 0, y: (button.bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            player.refresh()
            player.loadEqualizer()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// MARK: - Appearance options

enum Accent: String, CaseIterable, Identifiable {
    case standard, blue, purple, pink, red, orange, yellow, green, teal, graphite
    var id: String { rawValue }

    /// Colors offered for the accent (everything but "standard").
    static let palette = allCases.filter { $0 != .standard }

    var color: Color {
        switch self {
        case .standard: .primary
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .graphite: .gray
        }
    }

    /// Time labels: "standard" keeps the usual dim secondary color.
    var timeStyle: AnyShapeStyle {
        self == .standard ? AnyShapeStyle(.secondary) : AnyShapeStyle(color)
    }

    var label: String {
        switch self {
        case .standard: "Padrão"
        case .blue: "Azul"
        case .purple: "Roxo"
        case .pink: "Rosa"
        case .red: "Vermelho"
        case .orange: "Laranja"
        case .yellow: "Amarelo"
        case .green: "Verde"
        case .teal: "Turquesa"
        case .graphite: "Grafite"
        }
    }
}

enum ControlStyle: String, CaseIterable, Identifiable {
    case classic, filled, outline, soft, minimal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .classic: "Clássico"
        case .filled: "Cheio"
        case .outline: "Contorno"
        case .soft: "Suave"
        case .minimal: "Mínimo"
        }
    }
}

/// One playback control drawn in the chosen style and color.
struct ControlIcon: View {
    let symbol: String
    let style: ControlStyle
    let color: Color
    let diameter: CGFloat
    var prominent = false

    var body: some View {
        let glyph = Image(systemName: symbol).font(.system(size: diameter * 0.4, weight: .semibold))
        switch style {
        case .classic:
            if prominent {
                Image(systemName: symbol.replacingOccurrences(of: ".fill", with: ".circle.fill"))
                    .font(.system(size: diameter))
                    .foregroundStyle(color)
            } else {
                glyph.foregroundStyle(color).frame(width: diameter, height: diameter)
            }
        case .filled:
            glyph.foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(color))
        case .outline:
            glyph.foregroundStyle(color)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(color, lineWidth: 1.5))
        case .soft:
            glyph.foregroundStyle(color)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(color.opacity(0.18)))
        case .minimal:
            Image(systemName: symbol)
                .font(.system(size: diameter * (prominent ? 0.6 : 0.45)))
                .foregroundStyle(color)
                .frame(width: diameter, height: diameter)
        }
    }
}

// MARK: - Visualizer

/// The 10 standard equalizer bands (31 Hz – 16 kHz) of the live music, each with a
/// peak marker that holds the recent maximum and then falls. Without live audio they rest flat.
struct SpectrumBars: View {
    @ObservedObject var spectrum: AudioSpectrum
    let color: Color
    var spacingRatio: CGFloat = 0.3
    var peakThickness: CGFloat = 2
    var showsLabels = false
    @AppStorage("visualizerStyle") private var style = VisualizerStyle.modern

    var body: some View {
        let count = equalizerBands.count
        let levels = spectrum.levels.count == count ? spectrum.levels : []
        let peaks = spectrum.peaks.count == count ? spectrum.peaks : []
        switch style {
        case .modern: modern(levels: levels, peaks: peaks)
        case .retro: RetroSpectrum(levels: levels, peaks: peaks, isCompact: !showsLabels)
        }
    }

    private func modern(levels: [Float], peaks: [Float]) -> some View {
        let count = equalizerBands.count
        return VStack(spacing: 3) {
            GeometryReader { geo in
                let slot = geo.size.width / CGFloat(count)
                let barWidth = slot * (1 - spacingRatio)
                let floor: CGFloat = 0.1
                ZStack(alignment: .bottomLeading) {
                    ForEach(0..<count, id: \.self) { index in
                        let level = CGFloat(levels.isEmpty ? 0 : levels[index])
                        let x = slot * CGFloat(index) + (slot - barWidth) / 2
                        RoundedRectangle(cornerRadius: min(2, barWidth / 3))
                            .fill(color.opacity(levels.isEmpty ? 0.45 : 0.55 + 0.45 * Double(level)))
                            .frame(width: barWidth, height: max(2, geo.size.height * (floor + (1 - floor) * level)))
                            .offset(x: x)
                        if !peaks.isEmpty {
                            let peak = CGFloat(peaks[index])
                            let top = geo.size.height * (floor + (1 - floor) * peak)
                            Rectangle()
                                .fill(color)
                                .frame(width: barWidth, height: peakThickness)
                                .offset(x: x, y: -min(geo.size.height - peakThickness, top + peakThickness))
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            }
            if showsLabels {
                HStack(spacing: 0) {
                    ForEach(equalizerBandLabels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 8, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case modern, retro
    var id: String { rawValue }
    var label: String { self == .modern ? "Moderno" : "Retrô" }

    /// The equalizer's colors, reused by the menu bar title progress fill.
    func fill(accent: Color, direction: FillDirection) -> AnyShapeStyle {
        switch self {
        case .modern:
            AnyShapeStyle(accent)
        case .retro:
            AnyShapeStyle(LinearGradient(
                colors: [RetroSpectrum.color(at: 0), RetroSpectrum.color(at: 0.55), RetroSpectrum.color(at: 1)],
                startPoint: direction == .leftToRight ? .leading : .bottom,
                endPoint: direction == .leftToRight ? .trailing : .top
            ))
        }
    }
}

enum FillDirection: String, CaseIterable, Identifiable {
    case leftToRight, bottomToTop
    var id: String { rawValue }
    var label: String { self == .leftToRight ? "Esquerda → direita" : "Baixo → cima" }
}

/// Song title that doubles as a progress meter: the played part is painted with the
/// equalizer's color, the rest stays dim.
struct ProgressTitle: View {
    let text: String
    let progress: Double
    let fill: AnyShapeStyle
    var direction = FillDirection.leftToRight

    var body: some View {
        Text(text)
            .lineLimit(1)
            .foregroundStyle(.primary.opacity(0.45))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Text(text)
                        .lineLimit(1)
                        .foregroundStyle(fill)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                        .mask(alignment: direction == .leftToRight ? .leading : .bottom) {
                            switch direction {
                            case .leftToRight: Rectangle().frame(width: geo.size.width * progress)
                            case .bottomToTop: Rectangle().frame(height: geo.size.height * progress)
                            }
                        }
                }
            }
            // Position arrives once per second; slide between readings.
            .animation(.linear(duration: 1), value: progress)
            .help("\(Int((progress * 100).rounded()))% da música")
    }
}

/// Classic LED spectrum analyzer: segmented bars on black, green at the bottom fading
/// through yellow to red at the top, with a light peak segment above each bar.
struct RetroSpectrum: View {
    let levels: [Float]
    let peaks: [Float]
    /// Menu bar size: no panel, thinner segments, no labels.
    let isCompact: Bool

    private static let green = (r: 0.10, g: 0.85, b: 0.20)
    private static let yellow = (r: 0.95, g: 0.85, b: 0.10)
    private static let red = (r: 0.95, g: 0.18, b: 0.10)

    var body: some View {
        if isCompact {
            analyzer
        } else {
            VStack(spacing: 4) {
                analyzer
                HStack(spacing: 0) {
                    ForEach(equalizerBandLabels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.1, green: 0.85, blue: 0.2))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(6)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.gray.opacity(0.5), lineWidth: 1))
        }
    }

    private var analyzer: some View {
        Canvas { context, size in
            let count = equalizerBands.count
            let segment: CGFloat = isCompact ? 2 : 3
            let gap: CGFloat = 1
            let rows = max(1, Int((size.height + gap) / (segment + gap)))
            let slot = size.width / CGFloat(count)
            let barWidth = slot * (isCompact ? 0.75 : 0.8)

            for band in 0..<count {
                let x = slot * CGFloat(band) + (slot - barWidth) / 2
                let level = levels.isEmpty ? 0 : CGFloat(levels[band])
                let lit = levels.isEmpty ? 1 : max(1, Int((level * CGFloat(rows)).rounded()))
                for row in 0..<rows {
                    let y = size.height - CGFloat(row + 1) * (segment + gap) + gap
                    let rect = CGRect(x: x, y: y, width: barWidth, height: segment)
                    if row < lit {
                        context.fill(Path(rect), with: .color(Self.color(at: Double(row) / Double(max(1, rows - 1)))))
                    } else if !isCompact {
                        context.fill(Path(rect), with: .color(Color.white.opacity(0.06)))
                    }
                }
                if !peaks.isEmpty {
                    let peakRow = min(rows - 1, max(lit, Int((CGFloat(peaks[band]) * CGFloat(rows)).rounded())))
                    let y = size.height - CGFloat(peakRow + 1) * (segment + gap) + gap
                    context.fill(Path(CGRect(x: x, y: y, width: barWidth, height: segment)),
                                 with: .color(Color(white: 0.85)))
                }
            }
        }
    }

    /// Green → yellow → red as the segment rises.
    static func color(at fraction: Double) -> Color {
        let (from, to, t) = fraction < 0.55
            ? (green, yellow, fraction / 0.55)
            : (yellow, red, (fraction - 0.55) / 0.45)
        return Color(red: from.r + (to.r - from.r) * t,
                     green: from.g + (to.g - from.g) * t,
                     blue: from.b + (to.b - from.b) * t)
    }
}

func formatTime(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}

// MARK: - Menu bar

struct StatusBarView: View {
    @ObservedObject var player: PlayerController
    let onOpen: () -> Void
    @AppStorage("accent") private var accent = Accent.green
    @AppStorage("buttonColor") private var buttonColor = Accent.standard
    @AppStorage("barShowTitle") private var showTitle = true
    @AppStorage("barShowTime") private var showTime = true
    @AppStorage("barShowControls") private var showControls = true
    @AppStorage("barTitleProgress") private var titleShowsProgress = true
    @AppStorage("barTitleFill") private var fillDirection = FillDirection.leftToRight
    @AppStorage("timeColor") private var timeColor = Accent.standard
    @AppStorage("visualizerStyle") private var visualizerStyle = VisualizerStyle.modern

    private var progress: Double {
        guard player.state.duration > 0 else { return 0 }
        return min(1, max(0, player.state.position / player.state.duration))
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    SpectrumBars(spectrum: player.spectrum, color: accent.color, spacingRatio: 0.25, peakThickness: 1)
                        .frame(width: 40, height: 15)
                    if hasTrack, showTitle {
                        if titleShowsProgress {
                            ProgressTitle(
                                text: shortTitle, progress: progress,
                                fill: visualizerStyle.fill(accent: accent.color, direction: fillDirection),
                                direction: fillDirection
                            )
                        } else {
                            Text(shortTitle).lineLimit(1)
                        }
                    }
                    if hasTrack, showTime {
                        Text(timeLabel).monospacedDigit().foregroundStyle(timeColor.timeStyle)
                    }
                }
                .contentShape(Rectangle())
            }
            .help("Abrir o player")

            if player.isAppRunning, showControls {
                HStack(spacing: 2) {
                    Button(action: player.toggleShuffle) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(player.state.isShuffling ? accent.color : .secondary)
                            .frame(width: 18, height: 18)
                    }
                    .help(player.state.isShuffling ? "Desligar o modo aleatório" : "Ligar o modo aleatório")
                    Button(action: player.previous) { barIcon("backward.fill") }
                    Button(action: player.playPause) { barIcon(player.state.isPlaying ? "pause.fill" : "play.fill") }
                    Button(action: player.next) { barIcon("forward.fill") }
                }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .padding(.horizontal, 6)
        .frame(height: 22)
        .fixedSize()
    }

    private func barIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11))
            .foregroundStyle(buttonColor.color)
            .frame(width: 18, height: 18)
    }

    private var hasTrack: Bool { player.isAppRunning && !player.state.title.isEmpty }

    private var shortTitle: String {
        let title = player.state.title
        return title.count > 24 ? String(title.prefix(23)) + "…" : title
    }

    private var timeLabel: String {
        "\(formatTime(player.state.position)) / \(formatTime(player.state.duration))"
    }
}

// MARK: - Popover

struct PlayerView: View {
    @ObservedObject var player: PlayerController
    @AppStorage("accent") private var accent = Accent.green
    @AppStorage("buttonColor") private var buttonColor = Accent.standard
    @AppStorage("buttonStyle") private var buttonStyle = ControlStyle.classic
    @AppStorage("visualizerStyle") private var visualizerStyle = VisualizerStyle.modern
    @AppStorage("barTitleProgress") private var titleShowsProgress = true
    @AppStorage("barTitleFill") private var fillDirection = FillDirection.leftToRight
    @AppStorage("timeColor") private var timeColor = Accent.standard
    @AppStorage("barShowTitle") private var showTitle = true
    @AppStorage("barShowTime") private var showTime = true
    @AppStorage("barShowControls") private var showControls = true
    @State private var showSettings: Bool

    init(player: PlayerController, showSettings: Bool = false) {
        self.player = player
        _showSettings = State(initialValue: showSettings)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("", selection: $player.source) {
                    ForEach(PlayerSource.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button { showSettings.toggle() } label: {
                    Image(systemName: showSettings ? "paintpalette.fill" : "paintpalette")
                        .foregroundStyle(accent.color)
                }
                .buttonStyle(.borderless)
                .help("Cores, botões e barra de menus")
            }

            if showSettings { settings }

            if !player.isAppRunning {
                notRunning
            } else if player.state.title.isEmpty {
                Text("Nada tocando")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                controls
            } else {
                nowPlaying
                progress
                controls
                volume
                equalizer
            }

            if let error = player.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                Button("Abrir \(player.source.displayName)") { player.openApp() }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(14)
        .padding(.top, Preview.mode == nil ? 0 : 10)
        .frame(width: 300)
        .tint(accent.color)
        .onAppear {
            player.refresh()
            player.loadEqualizer()
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cor principal").font(.caption).foregroundStyle(.secondary)
            swatches(Accent.palette, selection: $accent)

            Text("Cor dos botões").font(.caption).foregroundStyle(.secondary)
            swatches(Accent.allCases, selection: $buttonColor)

            Text("Estilo dos botões").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(ControlStyle.allCases) { style in
                    VStack(spacing: 3) {
                        ControlIcon(symbol: "play.fill", style: style, color: buttonTint, diameter: 26, prominent: true)
                            .frame(width: 34, height: 30)
                        Text(style.label).font(.system(size: 9))
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(style == buttonStyle ? accent.color : .clear, lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { buttonStyle = style }
                }
            }

            Text("Estilo do equalizador").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $visualizerStyle) {
                ForEach(VisualizerStyle.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Barra de menus").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Toggle("Nome", isOn: $showTitle)
                Toggle("Tempo", isOn: $showTime)
                Toggle("Botões", isOn: $showControls)
            }
            Toggle("Nome mostra o tempo da música", isOn: $titleShowsProgress)
                .disabled(!showTitle)
            Picker("", selection: $fillDirection) {
                ForEach(FillDirection.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!showTitle || !titleShowsProgress)

            Text("Cor dos números de tempo").font(.caption).foregroundStyle(.secondary)
            swatches(Accent.allCases, selection: $timeColor)
        }
        .toggleStyle(.checkbox)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func swatches(_ options: [Accent], selection: Binding<Accent>) -> some View {
        HStack(spacing: 5) {
            ForEach(options) { option in
                Group {
                    if option == .standard {
                        Circle().fill(LinearGradient(colors: [.white, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        Circle().fill(option.color)
                    }
                }
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(.primary, lineWidth: option == selection.wrappedValue ? 2 : 0))
                .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
                .onTapGesture { selection.wrappedValue = option }
                .help(option.label)
            }
        }
    }

    /// "Standard" buttons follow the accent for the prominent styles so play stays visible.
    private var buttonTint: Color {
        buttonColor == .standard && buttonStyle != .minimal ? accent.color : buttonColor.color
    }

    // MARK: Player

    private var notRunning: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.house")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("\(player.source.displayName) não está aberto")
                .foregroundStyle(.secondary)
            Button("Abrir") { player.openApp() }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private var nowPlaying: some View {
        VStack(spacing: 8) {
            Group {
                if let art = player.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        accent.color.opacity(0.2)
                        Image(systemName: "music.note").font(.system(size: 48)).foregroundStyle(accent.color)
                    }
                }
            }
            .frame(width: 272, height: 272)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 2) {
                Text(player.state.title).font(.headline).lineLimit(1)
                Text(player.state.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if !player.state.album.isEmpty {
                    Text(player.state.album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
    }

    private var progress: some View {
        let duration = max(player.state.duration, 1)
        let current = player.scrubPosition ?? min(player.state.position, duration)
        return VStack(spacing: 2) {
            Slider(
                value: Binding(get: { current }, set: { [player] in player.scrubPosition = $0 }),
                in: 0...duration,
                onEditingChanged: { [player] editing in
                    if !editing { player.finishScrubbing() }
                }
            )
            .controlSize(.small)
            HStack {
                Text(formatTime(current))
                Spacer()
                Text("-" + formatTime(duration - current))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(timeColor.timeStyle)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button(action: player.toggleShuffle) {
                Image(systemName: "shuffle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(player.state.isShuffling ? accent.color : .secondary)
                    .frame(width: 28, height: 28)
                    .overlay(alignment: .bottom) {
                        Circle().fill(accent.color).frame(width: 4, height: 4)
                            .opacity(player.state.isShuffling ? 1 : 0)
                            .offset(y: 4)
                    }
            }
            .help(player.state.isShuffling ? "Modo aleatório ligado" : "Modo aleatório desligado")
            Button(action: player.previous) {
                ControlIcon(symbol: "backward.fill", style: buttonStyle, color: buttonColor.color, diameter: 36)
            }
            Button(action: player.playPause) {
                ControlIcon(
                    symbol: player.state.isPlaying ? "pause.fill" : "play.fill",
                    style: buttonStyle, color: buttonTint, diameter: 46, prominent: true
                )
            }
            Button(action: player.next) {
                ControlIcon(symbol: "forward.fill", style: buttonStyle, color: buttonColor.color, diameter: 36)
            }
            // Balances the shuffle button so play stays centered.
            Color.clear.frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private var volume: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { [player] in player.volumeDraft ?? player.state.volume },
                    set: { [player] in player.volumeDraft = $0; player.setVolume($0) }
                ),
                in: 0...100,
                onEditingChanged: { [player] editing in if !editing { player.volumeDraft = nil } }
            )
            .controlSize(.small)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
        }
    }

    private var equalizer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Equalizador").font(.caption.weight(.semibold))
            SpectrumBars(spectrum: player.spectrum, color: accent.color, showsLabels: true)
                .frame(height: 70)
            SpectrumNote(spectrum: player.spectrum, isPlaying: player.state.isPlaying)

            if player.equalizer.isAvailable {
                HStack {
                    Toggle("Ativo", isOn: Binding(
                        get: { player.equalizer.isEnabled },
                        set: { player.setEqualizerEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    Picker("", selection: Binding(
                        get: { player.equalizer.preset },
                        set: { player.setEqualizerPreset($0) }
                    )) {
                        ForEach(player.equalizer.presets, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(!player.equalizer.isEnabled)
                }
            } else if player.source == .spotify {
                Text("Para mudar o som, use Spotify › Ajustes › Reprodução › Equalizador.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Explains why the visualizer is flat while music plays.
struct SpectrumNote: View {
    @ObservedObject var spectrum: AudioSpectrum
    let isPlaying: Bool

    var body: some View {
        if isPlaying, let message {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var message: String? {
        if spectrum.isSilent {
            return "Sem áudio captado. Permita o eMusic Player em Ajustes do Sistema › Privacidade e Segurança › Gravação de Tela e Áudio do Sistema."
        }
        if spectrum.levels.isEmpty, let failure = spectrum.failure {
            return failure
        }
        return nil
    }
}
