import AppKit
import Combine
import SwiftUI

@main
struct MenuBarPlayerApp: App {
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

/// Bars showing the live spectrum of the music. Without live audio they rest flat.
struct SpectrumBars: View {
    @ObservedObject var spectrum: AudioSpectrum
    let color: Color
    var barCount = 6
    var spacingRatio: CGFloat = 0.25

    var body: some View {
        let levels = resampled(spectrum.levels)
        GeometryReader { geo in
            let spacing = geo.size.width / CGFloat(barCount) * spacingRatio
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let level = CGFloat(levels.isEmpty ? 0 : levels[index])
                    RoundedRectangle(cornerRadius: min(2, geo.size.width / CGFloat(barCount) / 3))
                        .fill(color.opacity(levels.isEmpty ? 0.45 : 0.55 + 0.45 * Double(level)))
                        .frame(height: max(2, geo.size.height * (0.12 + 0.88 * level)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// Averages the analyzer bands down (or repeats them up) to `barCount` bars.
    private func resampled(_ bands: [Float]) -> [Float] {
        guard !bands.isEmpty else { return [] }
        return (0..<barCount).map { bar in
            let start = bar * bands.count / barCount
            let end = max(start + 1, (bar + 1) * bands.count / barCount)
            let slice = bands[start..<min(end, bands.count)]
            return slice.reduce(0, +) / Float(slice.count)
        }
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

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    SpectrumBars(spectrum: player.spectrum, color: accent.color, barCount: 6)
                        .frame(width: 26, height: 14)
                    if hasTrack, showTitle {
                        Text(shortTitle).lineLimit(1)
                    }
                    if hasTrack, showTime {
                        Text(timeLabel).monospacedDigit().foregroundStyle(.secondary)
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
    @AppStorage("barShowTitle") private var showTitle = true
    @AppStorage("barShowTime") private var showTime = true
    @AppStorage("barShowControls") private var showControls = true
    @State private var scrubPosition: Double?
    @State private var volumeDraft: Double?
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

            Text("Barra de menus").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Toggle("Nome", isOn: $showTitle)
                Toggle("Tempo", isOn: $showTime)
                Toggle("Botões", isOn: $showControls)
            }
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
        let current = scrubPosition ?? min(player.state.position, duration)
        return VStack(spacing: 2) {
            Slider(
                value: Binding(get: { current }, set: { scrubPosition = $0 }),
                in: 0...duration,
                onEditingChanged: { editing in
                    if !editing, let target = scrubPosition {
                        player.seek(to: target)
                        scrubPosition = nil
                    }
                }
            )
            .controlSize(.small)
            HStack {
                Text(formatTime(current))
                Spacer()
                Text("-" + formatTime(duration - current))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
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
                    get: { volumeDraft ?? player.state.volume },
                    set: { volumeDraft = $0; player.setVolume($0) }
                ),
                in: 0...100,
                onEditingChanged: { if !$0 { volumeDraft = nil } }
            )
            .controlSize(.small)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
        }
    }

    private var equalizer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Equalizador").font(.caption.weight(.semibold))
            SpectrumBars(spectrum: player.spectrum, color: accent.color, barCount: spectrumBandCount, spacingRatio: 0.3)
                .frame(height: 44)
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
            return "Sem áudio captado. Permita o MenuBarPlayer em Ajustes do Sistema › Privacidade e Segurança › Gravação de Tela e Áudio do Sistema."
        }
        if spectrum.levels.isEmpty, let failure = spectrum.failure {
            return failure
        }
        return nil
    }
}
