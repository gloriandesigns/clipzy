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

    private init() {
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

    var selectedURLs: [URL] {
        items.filter { selection.contains($0.id) }.map(\.storageURL)
    }

    func toggleSelection(_ id: DropItem.ID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
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

    func load(_ providers: [NSItemProvider]) {
        assert(!Thread.isMainThread)
        DispatchQueue.main.asyncAndWait { isLoading += 1 }
        guard let urls = providers.interfaceConvert() else {
            DispatchQueue.main.asyncAndWait { isLoading -= 1 }
            return
        }
        do {
            let items = try urls.map { try DropItem(url: $0) }
            DispatchQueue.main.async {
                items.forEach { self.items.updateOrInsert($0, at: 0) }
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
