import AppKit
import Foundation

/// Music apps the menu bar player can control through AppleScript.
enum PlayerSource: String, CaseIterable, Identifiable {
    case spotify = "Spotify"
    case music = "Music"

    var id: String { rawValue }
    var displayName: String { self == .music ? "Apple Music" : "Spotify" }
    var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }

    /// Distributed notification each app posts when playback changes.
    var changeNotification: String {
        self == .music ? "com.apple.Music.playerInfo" : "com.spotify.client.PlaybackStateChanged"
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

struct TrackState: Equatable {
    var isPlaying = false
    var title = ""
    var artist = ""
    var album = ""
    var duration: Double = 0
    var position: Double = 0
    var volume: Double = 50
    /// Spotify artwork URL or Apple Music persistent ID; changes trigger an artwork reload.
    var artworkKey = ""
}

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var state = TrackState()
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isAppRunning = false
    @Published private(set) var lastError: String?
    @Published var source: PlayerSource {
        didSet {
            UserDefaults.standard.set(source.rawValue, forKey: "source")
            artwork = nil
            loadedArtworkKey = ""
            refresh()
        }
    }

    private var timer: Timer?
    private var loadedArtworkKey = ""
    private var observers: [NSObjectProtocol] = []

    init() {
        let saved = UserDefaults.standard.string(forKey: "source").flatMap(PlayerSource.init(rawValue:))
        source = saved ?? (PlayerSource.spotify.isRunning ? .spotify : .music)

        let center = DistributedNotificationCenter.default()
        for candidate in PlayerSource.allCases {
            let token = center.addObserver(
                forName: Notification.Name(candidate.changeNotification), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleExternalChange(from: candidate) }
            }
            observers.append(token)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Follow whichever app just started playing so the menu shows what is audible.
    private func handleExternalChange(from changed: PlayerSource) {
        if changed != source, changed.isRunning, query(changed)?.isPlaying == true {
            source = changed
        } else {
            refresh()
        }
    }

    // MARK: - Reading state

    func refresh() {
        isAppRunning = source.isRunning
        guard isAppRunning else {
            state = TrackState()
            artwork = nil
            loadedArtworkKey = ""
            return
        }
        guard let next = query(source) else { return }
        state = next
        if next.artworkKey != loadedArtworkKey {
            loadedArtworkKey = next.artworkKey
            loadArtwork(for: next)
        }
    }

    private func query(_ app: PlayerSource) -> TrackState? {
        let script: String
        switch app {
        case .spotify:
            script = """
            tell application "Spotify"
                set s to player state as string
                if s is "stopped" then return {s}
                set t to current track
                return {s, name of t, artist of t, album of t, (duration of t) / 1000, player position, sound volume, artwork url of t}
            end tell
            """
        case .music:
            script = """
            tell application "Music"
                set s to player state as string
                if s is "stopped" then return {s}
                set t to current track
                return {s, name of t, artist of t, album of t, duration of t, player position, sound volume, persistent ID of t}
            end tell
            """
        }
        guard let result = run(script) else { return nil }

        var track = TrackState()
        track.isPlaying = result.atIndex(1)?.stringValue == "playing"
        guard result.numberOfItems >= 8 else { return track }
        track.title = result.atIndex(2)?.stringValue ?? ""
        track.artist = result.atIndex(3)?.stringValue ?? ""
        track.album = result.atIndex(4)?.stringValue ?? ""
        track.duration = result.atIndex(5)?.doubleValue ?? 0
        track.position = result.atIndex(6)?.doubleValue ?? 0
        track.volume = Double(result.atIndex(7)?.int32Value ?? 50)
        track.artworkKey = result.atIndex(8)?.stringValue ?? ""
        return track
    }

    private func loadArtwork(for track: TrackState) {
        artwork = nil
        guard !track.artworkKey.isEmpty else { return }
        switch source {
        case .spotify:
            guard let url = URL(string: track.artworkKey) else { return }
            let key = track.artworkKey
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = NSImage(data: data),
                      self.loadedArtworkKey == key else { return }
                self.artwork = image
            }
        case .music:
            let data = run("tell application \"Music\" to get raw data of artwork 1 of current track", reportErrors: false)?.data
            artwork = data.flatMap(NSImage.init(data:))
        }
    }

    // MARK: - Commands

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func seek(to seconds: Double) {
        command("set player position to \(Int(seconds))")
    }

    func setVolume(_ volume: Double) {
        command("set sound volume to \(Int(volume))")
    }

    func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func command(_ body: String) {
        guard source.isRunning else { return }
        _ = run("tell application \"\(source.rawValue)\" to \(body)")
        refresh()
    }

    // MARK: - AppleScript

    @discardableResult
    private func run(_ source: String, reportErrors: Bool = true) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, reportErrors {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            lastError = number == -1743
                ? "Permita o controle em Ajustes do Sistema › Privacidade e Segurança › Automação."
                : (error[NSAppleScript.errorMessage] as? String ?? "Erro de AppleScript \(number)")
            return nil
        }
        if reportErrors { lastError = nil }
        return result
    }
}
