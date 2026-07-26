import Cocoa
import Combine
import Foundation
import OrderedCollections
import SwiftUI

class TrayDrop: ObservableObject {
    static let shared = TrayDrop()

    var cancellables = Set<AnyCancellable>()

    @Persist(key: "keepInterval", defaultValue: 3600 * 24)
    var keepInterval: TimeInterval

    /// item.id -> content hash, so two identical copies (same bytes,
    /// different UUID/timestamp — struct equality never matches on those)
    /// don't both end up in the tray. Populated once at launch from
    /// whatever's already persisted, then kept in sync on add/remove.
    private var digestByID: [DropItem.ID: String] = [:]

    private init() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var digests: [DropItem.ID: String] = [:]
            for item in self.items {
                if let digest = item.storageURL.contentDigest() {
                    digests[item.id] = digest
                }
            }
            DispatchQueue.main.async { self.digestByID = digests }
        }

        Publishers.CombineLatest3(
            $selectedFileStorageTime.removeDuplicates(),
            $customStorageTime.removeDuplicates(),
            $customStorageTimeUnit.removeDuplicates()
        )
        .map { selectedFileStorageTime, customStorageTime, customStorageTimeUnit in
            let customTime = switch customStorageTimeUnit {
            case .hours:
                TimeInterval(customStorageTime) * 60 * 60
            case .days:
                TimeInterval(customStorageTime) * 60 * 60 * 24
            case .weeks:
                TimeInterval(customStorageTime) * 60 * 60 * 24 * 7
            case .months:
                TimeInterval(customStorageTime) * 60 * 60 * 24 * 30
            case .years:
                TimeInterval(customStorageTime) * 60 * 60 * 24 * 365
            }
            let ans = selectedFileStorageTime.toTimeInterval(customTime: customTime)
            print("[*] using interval \(ans) to keep files")
            return ans
        }
        .receive(on: DispatchQueue.main)
        .sink { [weak self] output in
            self?.keepInterval = output
        }
        .store(in: &cancellables)
    }

    var isEmpty: Bool { items.isEmpty }

    @PublishedPersist(key: "TrayDropItems", defaultValue: .init())
    var items: OrderedSet<DropItem>

    @PublishedPersist(key: "selectedFileStorageTime", defaultValue: .never)
    var selectedFileStorageTime: FileStorageTime

    @Published var selection: Set<DropItem.ID> = []
    /// last item explicitly clicked (⌘-click or plain click) — anchors a
    /// following Shift-click into a range selection
    private var lastInteractedID: DropItem.ID?

    var selectedURLs: [URL] {
        items.filter { selection.contains($0.id) }.map(\.storageURL)
    }

    func toggleSelection(_ id: DropItem.ID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        lastInteractedID = id
    }

    /// Plain click copies rather than selects, so it never touched
    /// lastInteractedID — meaning "click item A, then Shift-click item C"
    /// (the gesture most people reach for first) had no anchor to range
    /// from. This lets a copy-click still count as the range's starting
    /// point without changing what a plain click actually does.
    func noteInteraction(_ id: DropItem.ID) {
        lastInteractedID = id
    }

    /// Shift-click: select everything between the last-interacted item and
    /// `id`, scoped to `groupItems` (the visible, expanded stack the click
    /// happened in) so range-select stays predictable across stacks.
    func selectRange(in groupItems: [DropItem], to id: DropItem.ID) {
        guard let anchor = lastInteractedID,
              let anchorIndex = groupItems.firstIndex(where: { $0.id == anchor }),
              let targetIndex = groupItems.firstIndex(where: { $0.id == id })
        else {
            toggleSelection(id)
            return
        }
        let range = anchorIndex <= targetIndex ? anchorIndex ... targetIndex : targetIndex ... anchorIndex
        for item in groupItems[range] { selection.insert(item.id) }
        lastInteractedID = id
    }

    /// transitions (dust vanish) only fire inside withAnimation
    private func animated(_ block: () -> Void) {
        withAnimation(.easeInOut(duration: 1.2)) { block() }
    }

    func deleteSelected() {
        animated {
            let ids = selection
            selection.removeAll()
            items.filter { ids.contains($0.id) }.forEach { delete(item: $0) }
        }
    }

    func delete(category: DropItem.Category) {
        animated {
            items.filter { $0.category == category }.forEach { delete(item: $0) }
        }
    }

    @PublishedPersist(key: "customStorageTime", defaultValue: 1)
    var customStorageTime: Int

    @PublishedPersist(key: "customStorageTimeUnit", defaultValue: .days)
    var customStorageTimeUnit: CustomstorageTimeUnit

    @Published var isLoading: Int = 0

    /// True if this exact content (by bytes, not filename) is already in
    /// the tray. Callers should skip creating a DropItem entirely when this
    /// is true, so no duplicate file ever gets copied into storage.
    func isDuplicate(of url: URL) -> Bool {
        guard let digest = url.contentDigest() else { return false }
        return digestByID.values.contains(digest)
    }

    /// Inserts a freshly-created item and remembers its content hash —
    /// the one path all new items (capture, drag-in) should go through so
    /// dedup stays in sync no matter where the item came from. Must be
    /// called on the main thread (touches @Published items/digestByID).
    func insert(_ item: DropItem, sourceURL: URL) {
        items.updateOrInsert(item, at: 0)
        guard let digest = sourceURL.contentDigest() else { return }
        digestByID[item.id] = digest
    }

    func load(_ providers: [NSItemProvider]) {
        assert(!Thread.isMainThread)
        DispatchQueue.main.asyncAndWait { isLoading += 1 }
        guard let urls = providers.interfaceConvert() else {
            DispatchQueue.main.asyncAndWait { isLoading -= 1 }
            return
        }
        let newURLs = urls.filter { !isDuplicate(of: $0) }
        do {
            let items = try newURLs.map { try DropItem(url: $0) }
            DispatchQueue.main.async {
                for (item, sourceURL) in zip(items, newURLs) {
                    self.insert(item, sourceURL: sourceURL)
                }
                self.isLoading -= 1
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading -= 1
                NSAlert.popError(error)
            }
        }
    }

    func cleanExpiredFiles() {
        var inEdit = items
        let shouldCleanItems = items.filter(\.shouldClean)
        for item in shouldCleanItems {
            inEdit.remove(item)
        }
        items = inEdit
    }

    func delete(_ item: DropItem.ID) {
        guard let item = items.first(where: { $0.id == item }) else { return }
        animated { delete(item: item) }
    }

    private func delete(item: DropItem) {
        var inEdit = items

        var url = item.storageURL
        try? FileManager.default.removeItem(at: url)

        do {
            // loops up to the main directory
            url = url.deletingLastPathComponent()
            while url.lastPathComponent != DropItem.mainDir, url != documentsDirectory {
                let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
                guard contents.isEmpty else { break }
                try FileManager.default.removeItem(at: url)
                url = url.deletingLastPathComponent()
            }
        } catch {}

        inEdit.remove(item)
        items = inEdit
        digestByID.removeValue(forKey: item.id)
    }

    func removeAll() {
        animated {
            selection.removeAll()
            items.forEach { delete(item: $0) }
        }
    }
}

extension TrayDrop {
    enum FileStorageTime: String, CaseIterable, Identifiable, Codable {
        case oneHour = "1 Hour"
        case oneDay = "1 Day"
        case twoDays = "2 Days"
        case threeDays = "3 Days"
        case oneWeek = "1 Week"
        case never = "Forever"
        case custom = "Custom"

        var id: String { rawValue }

        var localized: String {
            NSLocalizedString(rawValue, comment: "")
        }

        func toTimeInterval(customTime: TimeInterval) -> TimeInterval {
            switch self {
            case .oneHour:
                60 * 60
            case .oneDay:
                60 * 60 * 24
            case .twoDays:
                60 * 60 * 24 * 2
            case .threeDays:
                60 * 60 * 24 * 3
            case .oneWeek:
                60 * 60 * 24 * 7
            case .never:
                // not .infinity — JSON can't encode it, keepInterval silently stayed 1 day
                TimeInterval(60 * 60 * 24 * 365 * 100)
            case .custom:
                customTime
            }
        }
    }

    enum CustomstorageTimeUnit: String, CaseIterable, Identifiable, Codable {
        case hours = "Hours"
        case days = "Days"
        case weeks = "Weeks"
        case months = "Months"
        case years = "Years"

        var id: String { rawValue }

        var localized: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }
}
