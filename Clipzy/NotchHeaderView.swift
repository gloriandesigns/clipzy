//
//  NotchHeaderView.swift
//  Clipzy
//

import AppKit
import ColorfulX
import SwiftUI

struct NotchHeaderView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared
    @ObservedObject var updateChecker = UpdateChecker.shared

    var body: some View {
        HStack {
            if vm.contentType == .settings {
                Text("Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") (Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))")
            } else {
                Image("ClipzyLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 22)
            }
            Spacer()
            if updateChecker.updateAvailable {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("A new version is here")
                }
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().foregroundStyle(Color.accentColor.opacity(0.15)))
                .onTapGesture { NSWorkspace.shared.open(updateChecker.releaseURL) }
                .padding(.trailing, 4)
            }
            if !tvm.isEmpty, vm.contentType == .normal {
                Image(systemName: "trash.fill")
                    .foregroundStyle(.red)
                    .onTapGesture { tvm.removeAll() }
                    .padding(.trailing, 4)
            }
            Image(systemName: "ellipsis")
        }
        .animation(vm.animation, value: vm.contentType)
        .animation(vm.animation, value: updateChecker.updateAvailable)
        .font(.system(.headline, design: .rounded))
    }
}

#Preview {
    NotchHeaderView(vm: .init())
}
