//
//  NotchHeaderView.swift
//  Clipzy
//

import ColorfulX
import SwiftUI

struct NotchHeaderView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

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
            if !tvm.isEmpty, vm.contentType == .normal {
                Image(systemName: "trash.fill")
                    .foregroundStyle(.red)
                    .onTapGesture { tvm.removeAll() }
                    .padding(.trailing, 4)
            }
            Image(systemName: "ellipsis")
        }
        .animation(vm.animation, value: vm.contentType)
        .font(.system(.headline, design: .rounded))
    }
}

#Preview {
    NotchHeaderView(vm: .init())
}
