//
//  NotchSettingsView.swift
//  Clipzy
//
//  Created by 曹丁杰 on 2024/7/29.
//

import LaunchAtLogin
import SwiftUI

struct NotchSettingsView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm: TrayDrop = .shared

    private let rowSpacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            HStack {
                Picker("Language: ", selection: $vm.selectedLanguage) {
                    ForEach(Language.allCases) { language in
                        Text(language.localized).tag(language)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: vm.selectedLanguage == .simplifiedChinese || vm.selectedLanguage == .traditionalChinese ? 220 : 160)

                Spacer(minLength: 12)
                LaunchAtLogin.Toggle {
                    Text(NSLocalizedString("Launch at Login", comment: ""))
                }

                Spacer(minLength: 12)
                Toggle("Haptic Feedback ", isOn: $vm.hapticFeedback)
            }

            Divider()

            HStack {
                Text("Open Notch By: ")
                Picker(String(), selection: $vm.openTrigger) {
                    ForEach(NotchViewModel.OpenTrigger.allCases) { trigger in
                        Text(trigger.localized).tag(trigger)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 100)

                Spacer(minLength: 24)

                Text("File Storage Time: ")
                Picker(String(), selection: $tvm.selectedFileStorageTime) {
                    ForEach(TrayDrop.FileStorageTime.allCases) { time in
                        Text(time.localized).tag(time)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 100)
                if tvm.selectedFileStorageTime == .custom {
                    TextField("Days", value: $tvm.customStorageTime, formatter: NumberFormatter())
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 50)
                        .padding(.leading, 10)
                    Picker("Time Unit", selection: $tvm.customStorageTimeUnit) {
                        ForEach(TrayDrop.CustomstorageTimeUnit.allCases) { unit in
                            Text(unit.localized).tag(unit)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 160)
                }
                Spacer(minLength: 0)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Toggle("Instant Capture Hotkey (⌘⇧C)", isOn: $vm.captureHotKeyEnabled)
                    Spacer(minLength: 24)
                    Button("Check for Updates…") {
                        SparkleUpdater.shared.checkForUpdates()
                    }
                }
                Text("Hotkey is off by default: Clipzy already captures every copy automatically. Turning it on claims ⌘⇧C system-wide, which conflicts with apps that use it themselves (e.g. Arc's \"copy current URL\").")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

#Preview {
    NotchSettingsView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}
