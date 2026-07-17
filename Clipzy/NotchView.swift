//
//  NotchView.swift
//  Clipzy
//
//  Created by 秋星桥 on 2024/7/7.
//

import SwiftUI


/// One continuous silhouette: concave top flares (NotchNook style) +
/// rounded bottom corners. Single fill — no masks, no blend modes,
/// so nothing can glitch into black boxes mid-animation.
struct NotchFlareShape: Shape {
    var fillet: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(fillet, bottomRadius) }
        set { fillet = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let f = min(fillet, rect.height / 2)
        let r = min(bottomRadius, rect.height / 2)
        p.move(to: .init(x: rect.minX, y: rect.minY))
        // left flare: concave quarter-arc from top edge into left side
        p.addArc(
            center: .init(x: rect.minX, y: rect.minY + f),
            radius: f,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        p.addLine(to: .init(x: rect.minX + f, y: rect.maxY - r))
        p.addArc(
            center: .init(x: rect.minX + f + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true
        )
        p.addLine(to: .init(x: rect.maxX - f - r, y: rect.maxY))
        p.addArc(
            center: .init(x: rect.maxX - f - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true
        )
        p.addLine(to: .init(x: rect.maxX - f, y: rect.minY + f))
        // right flare
        p.addArc(
            center: .init(x: rect.maxX, y: rect.minY + f),
            radius: f,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

struct NotchView: View {
    @StateObject var vm: NotchViewModel

    @State var dropTargeting: Bool = false

    var notchSize: CGSize {
        switch vm.status {
        case .closed:
            var ans = CGSize(
                width: vm.deviceNotchRect.width - 4,
                height: vm.deviceNotchRect.height - 4
            )
            if ans.width < 0 { ans.width = 0 }
            if ans.height < 0 { ans.height = 0 }
            return ans
        case .opened:
            return vm.notchOpenedSize
        case .popping:
            return .init(
                width: vm.deviceNotchRect.width,
                height: vm.deviceNotchRect.height + 4
            )
        }
    }

    var notchCornerRadius: CGFloat {
        switch vm.status {
        case .closed: 8
        case .opened: 40
        case .popping: 10
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            notch
                .zIndex(0)
                .disabled(true)
                .opacity(vm.notchVisible ? 1 : 0.3)
            Group {
                if vm.status == .opened {
                    VStack(spacing: vm.spacing) {
                        NotchHeaderView(vm: vm)
                        NotchContentView(vm: vm)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(vm.spacing)
                    .frame(maxWidth: vm.notchOpenedSize.width, maxHeight: vm.notchOpenedSize.height)
                    .zIndex(1)
                }
            }
            .transition(
                .scale.combined(
                    with: .opacity
                ).combined(
                    with: .offset(y: -vm.notchOpenedSize.height / 2)
                ).animation(vm.animation)
            )
        }
        .background(dragDetector)
        .animation(vm.animation, value: vm.status)
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var topFillet: CGFloat {
        switch vm.status {
        case .closed: 6
        case .opened: 28
        case .popping: 8
        }
    }

    var notch: some View {
        NotchFlareShape(fillet: topFillet, bottomRadius: notchCornerRadius)
            .fill(.black)
            .frame(
                width: notchSize.width + topFillet * 2,
                height: notchSize.height
            )
            .shadow(
                color: .black.opacity(([.opened, .popping].contains(vm.status)) ? 0.5 : 0),
                radius: 24,
                y: 8
            )
    }

    @ViewBuilder
    var dragDetector: some View {
        RoundedRectangle(cornerRadius: notchCornerRadius)
            .foregroundStyle(Color.black.opacity(0.001)) // fuck you apple and 0.001 is the smallest we can have
            .contentShape(Rectangle())
            .frame(width: notchSize.width + vm.dropDetectorRange, height: notchSize.height + vm.dropDetectorRange)
            .onDrop(of: [.data], isTargeted: $dropTargeting) { _ in true }
            .onChange(of: dropTargeting) { isTargeted in
                if isTargeted, vm.status == .closed {
                    // Open the notch when a file is dragged over it
                    vm.notchOpen(.drag)
                    vm.hapticSender.send()
                } else if !isTargeted {
                    // Close the notch when the dragged item leaves the area
                    let mouseLocation: NSPoint = NSEvent.mouseLocation
                    if !vm.notchOpenedRect.insetBy(dx: vm.inset, dy: vm.inset).contains(mouseLocation) {
                        vm.notchClose()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
