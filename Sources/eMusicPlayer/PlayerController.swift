import AppKit
import Foundation

/// The music app the menu bar player controls through AppleScript.
enum Spotify {
    static let name = "Spotify"
    static let bundleID = "com.spotify.client"
    /// Distributed notification Spotify posts when playback changes.
    static let changeNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")

    static var isRunning: Bool {
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
    var isShuffling = false
    /// Artwork URL; changes trigger an artwork reload.
    var artworkKey = ""
}

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var state = TrackState()
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isAppRunning = false
    @Published private(set) var lastError: String?
    /// Slider drafts live here, not in view @State: writing view @State from the slider's
    /// end-of-drag callback crashed the app (EXC_BAD_ACCESS in State.wrappedValue.setter).
    @Published var scrubPosition: Double?
    @Published var volumeDraft: Double?
    /// Live frequency bands; a separate object so its frequent updates redraw only the visualizers.
    let spectrum = AudioSpectrum()

    private var timer: Timer?
    private var loadedArtworkKey = ""
    private var observer: NSObjectProtocol?

    init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Spotify.changeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.2
        refresh()
    }

    // MARK: - Reading state

    func refresh() {
        let running = Spotify.isRunning
        if running != isAppRunning { isAppRunning = running }
        guard running else {
            if state != TrackState() { state = TrackState() }
            if artwork != nil { artwork = nil }
            loadedArtworkKey = ""
            spectrum.stop()
            return
        }
        guard let next = query() else { return }
        // Assign only real changes: every @Published write redraws the menu bar item.
        if next != state { state = next }
        spectrum.sync(isPlaying: next.isPlaying)
        if next.artworkKey != loadedArtworkKey {
            loadedArtworkKey = next.artworkKey
            loadArtwork(for: next)
        }
    }

    /// Runs every second, so it is compiled once instead of on every call.
    private let queryScript: NSAppleScript? = {
        let script = NSAppleScript(source: """
        tell application "Spotify"
            set s to player state as string
            if s is "stopped" then return {s}
            set t to current track
            return {s, name of t, artist of t, album of t, (duration of t) / 1000, player position, sound volume, artwork url of t, shuffling}
        end tell
        """)
        script?.compileAndReturnError(nil)
        return script
    }()

    private func query() -> TrackState? {
        guard let result = run(queryScript) else { return nil }

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
        track.isShuffling = result.atIndex(9)?.booleanValue ?? false
        return track
    }

    private func loadArtwork(for track: TrackState) {
        artwork = nil
        guard let url = URL(string: track.artworkKey) else { return }
        let key = track.artworkKey
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data),
                  self.loadedArtworkKey == key else { return }
            self.artwork = image
        }
    }

    // MARK: - Commands

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }
    func toggleShuffle() { command("set shuffling to not shuffling") }

    /// Applies the dragged position once, after the slider's tracking callback returns.
    func finishScrubbing() {
        guard let target = scrubPosition else { return }
        DispatchQueue.main.async { [weak self] in
            self?.seek(to: target)
            self?.scrubPosition = nil
        }
    }

    func seek(to seconds: Double) {
        command("set player position to \(Int(seconds))")
    }

    func setVolume(_ volume: Double) {
        command("set sound volume to \(Int(volume))")
    }

    func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Spotify.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func command(_ body: String) {
        guard Spotify.isRunning else { return }
        _ = run(NSAppleScript(source: "tell application \"\(Spotify.name)\" to \(body)"))
        refresh()
    }

    // MARK: - AppleScript

    @discardableResult
    private func run(_ script: NSAppleScript?) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        let message: String? = error.map { error in
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            return number == -1743
                ? "Permita o controle em Ajustes do Sistema › Privacidade e Segurança › Automação."
                : (error[NSAppleScript.errorMessage] as? String ?? "Erro de AppleScript \(number)")
        }
        if message != lastError { lastError = message }
        return error == nil ? result : nil
    }
}
