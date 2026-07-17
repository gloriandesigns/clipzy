//
//  TrayDrop+DropItemView.swift
//  Clipzy
//
//  Click = toggle selection, ⌥-click = delete, drag = move file out.
//  Dragging a selected item drags the WHOLE selection.
//  Removal disperses into dust (Pow vanish) — the Thanos snap.
//

import Foundation
import Pow
import SwiftUI
import UniformTypeIdentifiers

struct DropItemView: View {
    let item: TrayDrop.DropItem
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

    @State var hover = false
    @State var copied = false

    var selected: Bool { tvm.selection.contains(item.id) }

    var body: some View {
        VStack {
            Image(nsImage: item.workspacePreviewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 64)
            Text(item.fileName)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .font(.system(.footnote, design: .rounded))
                .frame(maxWidth: 64)
        }
        .contentShape(Rectangle())
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .foregroundStyle(selected ? Color.accentColor.opacity(0.25) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .transition(.asymmetric(
            insertion: .movingParts.boing.combined(with: .opacity),
            removal: .clipzyBlurOut
        ))
        .onHover { inside in
            hover = inside
            if inside {
                if let text = item.previewText {
                    TextPreviewPanel.shared.show(content: .text(text))
                } else {
                    // full-res for images, file-icon snapshot for everything else
                    let image = NSImage(contentsOf: item.storageURL) ?? item.workspacePreviewImage
                    TextPreviewPanel.shared.show(content: .image(image, name: item.fileName))
                }
            } else {
                TextPreviewPanel.shared.hide()
            }
        }
        .scaleEffect(hover ? 1.05 : 1.0)
        .animation(vm.animation, value: hover)
        .animation(vm.animation, value: selected)
        .modifier(ItemInteraction(item: item, selected: selected, tvm: tvm, vm: vm) {
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { copied = false }
        })
        .conditionalEffect(.repeat(.glow(color: .green, radius: 24), every: 0.4), condition: copied)
        .overlay {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.red)
                .background(Color.white.clipShape(Circle()).padding(1))
                .frame(width: vm.spacing, height: vm.spacing)
                .opacity(vm.optionKeyPressed ? 1 : 0)
                .scaleEffect(vm.optionKeyPressed ? 1 : 0.5)
                .animation(vm.animation, value: vm.optionKeyPressed)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: vm.spacing / 2, y: -vm.spacing / 2)
                .onTapGesture { tvm.delete(item.id) }
        }
    }
}

/// Selected: AppKit layer drags the whole selection, tap deselects.
/// Unselected: click = copy to clipboard, ⌘-click = select, ⌥-click = delete,
/// drag = move this single item out.
private struct ItemInteraction: ViewModifier {
    let item: TrayDrop.DropItem
    let selected: Bool
    let tvm: TrayDrop
    let vm: NotchViewModel
    let onCopied: () -> Void

    func body(content: Content) -> some View {
        if selected {
            content.overlay {
                MultiDragView(
                    urls: tvm.selectedURLs,
                    onTap: { tvm.toggleSelection(item.id) }
                )
                .accessibilityHidden(true)
            }
        } else {
            content
                .onDrag { NSItemProvider(contentsOf: item.storageURL) ?? NSItemProvider() }
                .onTapGesture {
                    let flags = EventMonitors.shared.mouseDownFlags.value.union(NSEvent.modifierFlags)
                    if flags.contains(.option) {
                        tvm.delete(item.id)
                    } else if flags.contains(.command) {
                        tvm.toggleSelection(item.id)
                    } else {
                        ClipzyCopy.copy([item])
                        onCopied()
                    }
                }
        }
    }
}
