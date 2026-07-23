//
//  TrayDrop+View.swift
//  Clipzy
//
//  Grouped-by-type tray. Double-click a stack to spread it open, click items
//  to select, drag any selected item to drag the whole selection.
//

import Pow
import SwiftUI

struct TrayView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

    @State private var targeting = false
    @State private var expandedCategories: Set<TrayDrop.DropItem.Category> = []
    @Namespace private var trayNamespace

    var groups: [(category: TrayDrop.DropItem.Category, items: [TrayDrop.DropItem])] {
        TrayDrop.DropItem.Category.allCases.compactMap { category in
            let items = Array(tvm.items.filter { $0.category == category })
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        panel
            .onDrop(of: [.data], isTargeted: $targeting) { providers in
                DispatchQueue.global().async { tvm.load(providers) }
                return true
            }
    }

    var panel: some View {
        ZStack {
            loading
            // the "bin lid": dashed border tilts open while a drag hovers
            RoundedRectangle(cornerRadius: vm.cornerRadius)
                .strokeBorder(style: StrokeStyle(lineWidth: 4, dash: [10]))
                .foregroundStyle(targeting ? Color.accentColor.opacity(0.9) : .white.opacity(0.1))
                .rotation3DEffect(
                    .degrees(targeting ? -14 : 0),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .bottom,
                    perspective: 0.5
                )
                .shadow(color: targeting ? Color.accentColor.opacity(0.5) : .clear, radius: 12)
            content
                // content used to shrink-wrap to its own compact height,
                // leaving loading/border (which match content's size) way
                // smaller than the space the notch actually granted them.
                // Filling here + centering makes stacks sit centered in
                // the full box instead of floating with slack above.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // panel itself must claim all available space too, or the ZStack
        // still shrink-wraps around its tallest child regardless of what
        // content above asks for
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, vm.spacing)
        .padding(.top, vm.spacing)
        .padding(.bottom, vm.spacing * 1.1)
        .onHover { inside in
            if !inside { expandedCategories.removeAll() }
        }
            .animation(vm.animation, value: tvm.items)
            .animation(vm.animation, value: tvm.isLoading)
            .animation(vm.animation, value: expandedCategories)
            .animation(vm.animation, value: targeting)
            .overlay(alignment: .bottomTrailing) {
                if !tvm.selection.isEmpty {
                    selectionBadge
                        .padding(8)
                }
            }
    }

    var loading: some View {
        RoundedRectangle(cornerRadius: vm.cornerRadius)
            .foregroundStyle(.white.opacity(0.1))
            .conditionalEffect(
                .repeat(
                    .glow(color: .blue, radius: 50),
                    every: 1.5
                ),
                condition: tvm.isLoading > 0
            )
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 8) {
                    Image("ClipzyLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 34)
                    Text("Copy anything anywhere, or drag it here — it lands in this tray")
                        .multilineTextAlignment(.center)
                        .font(.system(.headline, design: .rounded))
                    Text("click = copy · 2×click stack = open · ⌘-click = select · ⌫ = delete")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .center, spacing: vm.spacing) {
                        ForEach(groups, id: \.category) { group in
                            CategoryGroupView(
                                category: group.category,
                                items: group.items,
                                expanded: expandedCategories.contains(group.category),
                                namespace: trayNamespace,
                                vm: vm,
                                tvm: tvm
                            ) {
                                if expandedCategories.contains(group.category) {
                                    expandedCategories.remove(group.category)
                                } else {
                                    expandedCategories.insert(group.category)
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .movingParts.boing.combined(with: .opacity),
                                removal: .clipzyBlurOut
                            ))
                        }
                    }
                    .padding(vm.spacing)
                }
                .padding(-vm.spacing)
                .scrollIndicators(.never)
            }
        }
    }

    var selectionBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw.fill")
            Text("\(tvm.selection.count) selected — drag any, ⌫ deletes")
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .onTapGesture { tvm.selection.removeAll() }
        }
        .font(.system(.footnote, design: .rounded).weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().foregroundStyle(Color.accentColor.opacity(0.5)))
    }
}

struct CategoryGroupView: View {
    let category: TrayDrop.DropItem.Category
    let items: [TrayDrop.DropItem]
    let expanded: Bool
    let namespace: Namespace.ID
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var tvm: TrayDrop
    let toggleExpand: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if expanded {
                HStack(spacing: vm.spacing / 2) {
                    ForEach(items) { item in
                        DropItemView(item: item, vm: vm, tvm: tvm)
                            .matchedGeometryEffect(id: item.id, in: namespace)
                    }
                }
            } else {
                ZStack {
                    ForEach(Array(items.prefix(4).enumerated().reversed()), id: \.element.id) { index, item in
                        Image(nsImage: item.workspacePreviewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .foregroundStyle(.white.opacity(0.06))
                            )
                            .rotationEffect(.degrees(Double(index) * 6 - 6))
                            .offset(x: CGFloat(index) * 5, y: CGFloat(index) * -2)
                            .matchedGeometryEffect(id: item.id, in: namespace)
                            // collapsed-stack thumbnails need their own dust,
                            // else deletes here vanish instantly
                            .transition(.clipzyBlurOut)
                    }
                }
                .frame(height: 56)
                .contentShape(Rectangle())
                // click = copy whole stack, 2×click = spread open, drag = drag all
                .overlay {
                    MultiDragView(
                        urls: items.map(\.storageURL),
                        onTap: { ClipzyCopy.copy(items) },
                        onDoubleTap: toggleExpand
                    )
                    .accessibilityHidden(true)
                }
            }
            label
        }
        .contentShape(Rectangle())
    }

    var label: some View {
        HStack(spacing: 4) {
            Image(systemName: category.symbol)
                .foregroundStyle(category.tint)
            Text(category.rawValue)
            Text("\(items.count)")
                .padding(.horizontal, 5)
                .background(Capsule().foregroundStyle(category.tint.opacity(0.3)))
            Image(systemName: "trash.fill")
                .foregroundStyle(.red.opacity(0.85))
                .onTapGesture { tvm.delete(category: category) }
        }
        .font(.system(.footnote, design: .rounded).weight(.semibold))
        .onTapGesture(count: 2) { toggleExpand() }
    }
}

#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 550, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}
