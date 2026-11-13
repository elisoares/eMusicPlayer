import SwiftUI

@main
struct MenuBarPlayerApp: App {
    @StateObject private var player = PlayerController()

    var body: some Scene {
        MenuBarExtra {
            PlayerView(player: player)
        } label: {
            MenuBarLabel(state: player.state, isRunning: player.isAppRunning)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let state: TrackState
    let isRunning: Bool

    var body: some View {
        if isRunning, state.isPlaying, !state.title.isEmpty {
            Image(systemName: "music.note")
            Text(shortTitle)
        } else {
            Image(systemName: "music.note")
        }
    }

    private var shortTitle: String {
        state.title.count > 28 ? String(state.title.prefix(27)) + "…" : state.title
    }
}

struct PlayerView: View {
    @ObservedObject var player: PlayerController
    @State private var scrubPosition: Double?
    @State private var volumeDraft: Double?

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $player.source) {
                ForEach(PlayerSource.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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
        .frame(width: 300)
        .onAppear { player.refresh() }
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
                        Color.secondary.opacity(0.15)
                        Image(systemName: "music.note").font(.system(size: 48)).foregroundStyle(.secondary)
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
                Text(format(current))
                Spacer()
                Text("-" + format(duration - current))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 32) {
            Button(action: player.previous) { Image(systemName: "backward.fill") }
            Button(action: player.playPause) {
                Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28))
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

    private func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
