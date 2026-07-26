//
//  Ext+URL.swift
//  Clipzy
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import CryptoKit
import Foundation
import QuickLook

extension URL {
    /// SHA256 of the file's actual bytes — used to catch "this exact same
    /// image/text got copied twice" regardless of filename or timestamp.
    func contentDigest() -> String? {
        guard let data = try? Data(contentsOf: self) else { return nil }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    func snapshotPreview() -> NSImage {
        if let preview = QLThumbnailImageCreate(
            kCFAllocatorDefault,
            self as CFURL,
            CGSize(width: 128, height: 128),
            nil
        )?.takeRetainedValue() {
            return NSImage(cgImage: preview, size: .zero)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }
}
