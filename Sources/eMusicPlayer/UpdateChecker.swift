import AppKit
import SwiftUI

/// Checks the latest GitHub release of eMusic Player and offers its DMG.
/// Only the public releases API is called; nothing about the user is sent.
@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, download: URL)
        case failed(String)
    }

    static let shared = UpdateChecker()
    static let latestRelease = URL(string: "https://api.github.com/repos/elisoares/eMusicPlayer/releases/latest")!
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    @Published private(set) var status = Status.idle

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]
    }

    func check() {
        guard status != .checking else { return }
        status = .checking
        Task {
            do {
                var request = URLRequest(url: Self.latestRelease)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    status = .failed("O GitHub não respondeu. Tente mais tarde.")
                    return
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if Self.isNewer(latest, than: Self.currentVersion) {
                    let dmg = release.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url
                    status = .available(version: latest, download: dmg ?? release.html_url)
                } else {
                    status = .upToDate
                }
            } catch {
                status = .failed("Sem conexão com o GitHub.")
            }
        }
    }

    /// Numeric comparison of dotted versions ("1.10.0" > "1.9.2").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Footer button: check for an update, then offer the download.
struct UpdateButton: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        switch checker.status {
        case .idle:
            Button("Atualizações") { checker.check() }
                .help("Versão \(UpdateChecker.currentVersion). Verificar se há uma versão nova.")
        case .checking:
            Text("Verificando…").foregroundStyle(.secondary)
        case .upToDate:
            Button("Atualizado ✓") { checker.check() }
                .foregroundStyle(.secondary)
                .help("Você tem a versão mais nova (\(UpdateChecker.currentVersion)).")
        case let .available(version, download):
            Button("Baixar \(version)") { NSWorkspace.shared.open(download) }
                .fontWeight(.semibold)
                .help("Baixa o DMG da versão \(version). Abra e arraste para Aplicativos, substituindo o atual.")
        case let .failed(message):
            Button("Tentar de novo") { checker.check() }
                .foregroundStyle(.orange)
                .help(message)
        }
    }
}
