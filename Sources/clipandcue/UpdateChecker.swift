import Foundation
import AppKit

/// Polls the public GitHub Releases API for the newest tag and compares
/// it to the running version from `Info.plist`. Drives the
/// "Check for updates" button in Preferences.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State {
        case idle
        case checking
        case upToDate(current: String)
        case updateAvailable(latest: String, releaseURL: URL)
        case failed
    }

    @Published private(set) var state: State = .idle

    private let owner = "mrmichaelmoorecom-sys"
    private let repo = "clipandcue"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func check() async {
        state = .checking
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            state = .failed
            return
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let releaseURLString = json["html_url"] as? String,
                  let releaseURL = URL(string: releaseURLString) else {
                state = .failed
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if Self.isNewer(latest, than: currentVersion) {
                state = .updateAvailable(latest: latest, releaseURL: releaseURL)
            } else {
                state = .upToDate(current: currentVersion)
            }
        } catch {
            state = .failed
        }
    }

    /// Numeric semver-ish compare: splits on dots, pads with zeros, compares
    /// component-by-component. "0.2.7" > "0.2.6"; "0.3.0" > "0.2.9".
    static func isNewer(_ candidate: String, than baseline: String) -> Bool {
        let a = candidate.split(separator: ".").compactMap { Int($0) }
        let b = baseline.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv { return av > bv }
        }
        return false
    }
}
