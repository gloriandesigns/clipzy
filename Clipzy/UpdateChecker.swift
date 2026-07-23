//
//  UpdateChecker.swift
//  Clipzy
//
//  Checks GitHub Releases for a newer tag than the running build and
//  surfaces "A new version is here" in the header when one exists.
//

import Combine
import Foundation

final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var updateAvailable: Bool = false
    @Published private(set) var latestVersion: String?
    private(set) var releaseURL: URL = productPage.appendingPathComponent("releases/latest")

    private let apiURL = URL(string: "https://api.github.com/repos/gloriandesigns/clipzy/releases/latest")!
    private var timer: Timer?

    private init() {}

    func startPeriodicCheck(interval: TimeInterval = 6 * 60 * 60) {
        check()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func check() {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self, error == nil, let data else { return }
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = json["tag_name"] as? String
            else { return }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let htmlURL = (json["html_url"] as? String).flatMap(URL.init(string:))

            DispatchQueue.main.async {
                if Self.isNewer(tag: tag, than: currentVersion) {
                    self.latestVersion = tag
                    self.releaseURL = htmlURL ?? self.releaseURL
                    self.updateAvailable = true
                } else {
                    self.updateAvailable = false
                }
            }
        }.resume()
    }

    /// Compares GitHub tag (e.g. "v1.2.0") against the running CFBundleShortVersionString (e.g. "1.1.0").
    static func isNewer(tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".")
                .map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let a = parts(tag)
        let b = parts(current)
        let count = max(a.count, b.count)
        for i in 0 ..< count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
