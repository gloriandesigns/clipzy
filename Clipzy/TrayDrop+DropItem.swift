//
//  TrayDrop+DropItem.swift
//  TrayDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import CoreTransferable
import Foundation
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

extension TrayDrop {
    struct DropItem: Identifiable, Codable, Equatable, Hashable {
        let id: UUID

        let fileName: String
        let size: Int

        let copiedDate: Date
        let workspacePreviewImageData: Data

        init(url: URL) throws {
            assert(!Thread.isMainThread)

            id = UUID()
            fileName = url.lastPathComponent

            size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            copiedDate = Date()
            workspacePreviewImageData = url.snapshotPreview().pngRepresentation

            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: url, to: storageURL)
        }
    }
}

extension TrayDrop.DropItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        let exportingBehavior: @Sendable (TrayDrop.DropItem) async throws -> SentTransferredFile = { input in
            let tempDir = temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let newPath = tempDir.appendingPathComponent(input.fileName)
            try FileManager.default.copyItem(
                at: input.storageURL,
                to: newPath
            )
            return .init(newPath, allowAccessingOriginalFile: true)
        }
        let importingBehavior: @Sendable (ReceivedTransferredFile) async throws -> TrayDrop.DropItem = { _ in
            fatalError()
        }
        return FileRepresentation(
            contentType: .data,
            shouldAttemptToOpenInPlace: true,
            exporting: exportingBehavior,
            importing: importingBehavior
        )
    }
}

extension TrayDrop.DropItem {
    enum Category: String, CaseIterable, Identifiable, Codable {
        case images = "Images"
        case media = "Media"
        case documents = "Docs"
        case text = "Text"
        case other = "Other"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .images: "photo.on.rectangle.angled"
            case .media: "play.rectangle.fill"
            case .documents: "doc.richtext.fill"
            case .text: "text.alignleft"
            case .other: "shippingbox.fill"
            }
        }

        var tint: Color {
            switch self {
            case .images: .cyan
            case .media: .purple
            case .documents: .orange
            case .text: .green
            case .other: .gray
            }
        }
    }

    /// readable content for the hover preview (text files + weblocs)
    var previewText: String? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "webloc" {
            guard let data = try? Data(contentsOf: storageURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let url = (plist as? [String: String])?["URL"]
            else { return nil }
            return url
        }
        guard let type = UTType(filenameExtension: ext),
              type.conforms(to: .text) || type.conforms(to: .sourceCode),
              let text = try? String(contentsOf: storageURL, encoding: .utf8)
        else { return nil }
        return String(text.prefix(4000))
    }

    var category: Category {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "webloc" { return .text }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .audiovisualContent) { return .media }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .url) { return .text }
        if type.conforms(to: .pdf) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .compositeContent) { return .documents }
        return .other
    }
}

extension TrayDrop.DropItem {
    static let mainDir = "CopiedItems"

    var storageURL: URL {
        documentsDirectory
            .appendingPathComponent(Self.mainDir)
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent(fileName)
    }

    var workspacePreviewImage: NSImage {
        .init(data: workspacePreviewImageData) ?? .init()
    }

    var shouldClean: Bool {
        if !FileManager.default.fileExists(atPath: storageURL.path) { return true }
        let keepInterval = TrayDrop.shared.keepInterval
        guard keepInterval > 0 else { return true } // avoid non-reasonable value deleting user's files
        if Date().timeIntervalSince(copiedDate) > TrayDrop.shared.keepInterval { return true }
        return false
    }
}
