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

// MARK: - Accent color

enum Accent: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal, graphite
    var id: String { rawValue }
    var color: Color {
        switch self {
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
}

// MARK: - Menu bar

struct StatusBarView: View {
    @ObservedObject var player: PlayerController
    let onOpen: () -> Void
    @AppStorage("accent") private var accent = Accent.green
    @AppStorage("barShowTitle") private var showTitle = true
    @AppStorage("barShowTime") private var showTime = true
    @AppStorage("barShowControls") private var showControls = true

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
                HStack(spacing: 5) {
                    EqualizerBars(isPlaying: player.state.isPlaying, color: accent.color, barCount: 4)
                        .frame(width: 14, height: 12)
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
                Button(action: player.previous) { Image(systemName: "backward.fill") }
                Button(action: player.playPause) {
                    Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(action: player.next) { Image(systemName: "forward.fill") }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .padding(.horizontal, 6)
        .frame(height: 22)
        .fixedSize()
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

/// Animated bars; they move while music plays and rest when it stops.
struct EqualizerBars: View {
    let isPlaying: Bool
    let color: Color
    var barCount = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: geo.size.width * 0.12) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let phase = Double(index) * 1.7
                        let level = isPlaying
                            ? 0.25 + 0.75 * abs(sin(t * (2.2 + Double(index) * 0.6) + phase))
                            : 0.2
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color)
                            .frame(height: geo.size.height * level)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

func formatTime(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}

// MARK: - Popover

struct PlayerView: View {
    @ObservedObject var player: PlayerController
    @AppStorage("accent") private var accent = Accent.green
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
                }
                .buttonStyle(.borderless)
                .help("Cores e barra de menus")
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

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cor").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Accent.allCases) { option in
                    Circle()
                        .fill(option.color)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: option == accent ? 2 : 0))
                        .onTapGesture { accent = option }
                        .help(option.rawValue)
                }
            }
            Text("Barra de menus").font(.caption).foregroundStyle(.secondary)
            Toggle("Nome da música", isOn: $showTitle)
            Toggle("Tempo", isOn: $showTime)
            Toggle("Botões", isOn: $showControls)
        }
        .toggleStyle(.checkbox)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

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
        HStack(spacing: 28) {
            Button(action: player.previous) { Image(systemName: "backward.fill") }
            Button(action: player.playPause) {
                Image(systemName: player.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(accent.color)
            }
            Button(action: player.next) { Image(systemName: "forward.fill") }
        }
        .font(.system(size: 20))
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
            HStack {
                Text("Equalizador").font(.caption.weight(.semibold))
                Spacer()
                EqualizerBars(isPlaying: player.state.isPlaying, color: accent.color, barCount: 12)
                    .frame(width: 90, height: 16)
            }
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
            } else {
                Text(player.source == .spotify
                     ? "O Spotify não deixa outros apps mudarem o equalizador. Use Spotify › Ajustes › Reprodução › Equalizador."
                     : "Abra o Apple Music para usar o equalizador.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
