import AppKit
import SwiftUI

/// `eMusicPlayer --preview panel|bar` opens the panel or the menu bar strip in a normal
/// window and prints its window id, so `screencapture -l <id>` can take README screenshots.
enum Preview {
    enum Mode: String { case panel, settings, bar }

    static var mode: Mode? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--preview"), index + 1 < args.count else { return nil }
        return Mode(rawValue: args[index + 1])
    }

    private static var window: NSWindow?

    @MainActor
    static func show(_ mode: Mode, player: PlayerController) {
        let root: AnyView = switch mode {
        case .panel: AnyView(PlayerView(player: player))
        case .settings: AnyView(PlayerView(player: player, showSettings: true))
        case .bar: AnyView(StatusBarView(player: player) {}.padding(4).background(.bar))
        }
        let host = NSHostingView(rootView: root)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = host
        window.titlebarAppearsTransparent = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.accessory)
        self.window = window
        print("WINDOW \(window.windowNumber)")
        fflush(stdout)
    }
}
