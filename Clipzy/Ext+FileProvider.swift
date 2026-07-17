//
//  Ext+FileProvider.swift
//  Clipzy
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    private func duplicateToOurStorage(_ url: URL?) throws -> URL {
        guard let url else { throw NSError() }
        let temp = temporaryDirectory
            .appendingPathComponent("TemporaryDrop")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.createDirectory(
            at: temp.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: url, to: temp)
        return temp
    }

    private func tempFile(named name: String) -> URL {
        let dir = temporaryDirectory
            .appendingPathComponent("TemporaryDrop")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    func convertToFilePathThatIsWhatWeThinkItWillWorkWithClipzy() -> URL? {
        var url: URL?
        var remoteURL: URL?
        let sem = DispatchSemaphore(value: 0)
        _ = loadObject(ofClass: URL.self) { item, _ in
            if let item, item.isFileURL {
                url = try? self.duplicateToOurStorage(item)
            } else {
                remoteURL = item // browser drag (e.g. Pinterest) — https image URL
            }
            sem.signal()
        }
        sem.wait()
        if url == nil {
            loadInPlaceFileRepresentation(
                forTypeIdentifier: UTType.data.identifier
            ) { input, _, _ in
                defer { sem.signal() }
                url = try? self.duplicateToOurStorage(input)
            }
            sem.wait()
        }
        // browser image drags carry raw image data, not a file
        if url == nil {
            let imageType = registeredTypeIdentifiers
                .compactMap { UTType($0) }
                .first { $0.conforms(to: .image) }
            if let imageType {
                loadDataRepresentation(forTypeIdentifier: imageType.identifier) { data, _ in
                    defer { sem.signal() }
                    guard let data else { return }
                    let ext = imageType.preferredFilenameExtension ?? "png"
                    let target = self.tempFile(named: "Image \(UUID().uuidString.prefix(6)).\(ext)")
                    if (try? data.write(to: target)) != nil { url = target }
                }
                sem.wait()
            }
        }
        // last resort: download the remote URL
        if url == nil, let remoteURL {
            if let data = try? Data(contentsOf: remoteURL) {
                var name = remoteURL.lastPathComponent
                if (name as NSString).pathExtension.isEmpty { name += ".png" }
                let target = tempFile(named: name.isEmpty ? "Download.png" : name)
                if (try? data.write(to: target)) != nil { url = target }
            }
        }
        return url
    }
}

extension [NSItemProvider] {
    func interfaceConvert() -> [URL]? {
        let urls = compactMap { provider -> URL? in
            provider.convertToFilePathThatIsWhatWeThinkItWillWorkWithClipzy()
        }
        // browser drops bundle extra providers (html, text) that can't convert —
        // only error when NOTHING was usable
        guard !urls.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSAlert.popError(NSLocalizedString("One or more files failed to load", comment: ""))
            }
            return nil
        }
        return urls
    }
}
