//
//  AppDelegate.swift
//  Clipzy
//
//  Created by 秋星桥 on 2024/7/7.
//

import AppKit
import Cocoa
import LaunchAtLogin

class AppDelegate: NSObject, NSApplicationDelegate {
    var isFirstOpen = true
    var isLaunchedAtLogin = false
    var windowControllers: [NotchWindowController] = []

    var timer: Timer?

    func applicationDidFinishLaunching(_: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildApplicationWindows),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSApp.setActivationPolicy(.accessory)

        isLaunchedAtLogin = LaunchAtLogin.wasLaunchedAtLogin

        _ = EventMonitors.shared
        ClipboardCapture.startWatching()
        let timer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            self?.determineIfProcessIdentifierMatches()
            self?.makeKeyAndVisibleIfNeeded()
        }
        self.timer = timer

        rebuildApplicationWindows()
    }

    func applicationWillTerminate(_: Notification) {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try? FileManager.default.removeItem(at: pidFile)
    }

    @objc func rebuildApplicationWindows() {
        defer { isFirstOpen = false }
        windowControllers.forEach { $0.destroy() }
        // one notch per display: real notch on built-in, fake pill on externals
        windowControllers = NSScreen.screens.map { NotchWindowController(screen: $0) }
        if isFirstOpen, !isLaunchedAtLogin {
            windowControllers.first?.openAfterCreate = true
        }
    }

    func determineIfProcessIdentifierMatches() {
        let pid = String(NSRunningApplication.current.processIdentifier)
        let content = (try? String(contentsOf: pidFile)) ?? ""
        guard pid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else {
            NSApp.terminate(nil)
            return
        }
    }

    func makeKeyAndVisibleIfNeeded() {
        for controller in windowControllers {
            guard let window = controller.window,
                  let vm = controller.vm,
                  vm.status == .opened
            else { continue }
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        guard let vm = windowControllers.first?.vm else { return true }
        vm.notchOpen(.click)
        return true
    }
}
