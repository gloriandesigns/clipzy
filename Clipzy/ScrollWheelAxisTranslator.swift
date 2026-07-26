//
//  ScrollWheelAxisTranslator.swift
//  Clipzy
//
//  The tray's item row is a horizontal ScrollView, but almost everyone
//  reaches for the vertical scroll wheel out of habit — there's no visible
//  bar hinting "this one goes sideways." This finds the real AppKit
//  NSScrollView backing that SwiftUI ScrollView and re-routes vertical wheel
//  motion into horizontal scrolling: scroll down glides the row right,
//  scroll up glides it back left. Drop `.horizontalWheelScrolling()` onto
//  the content sitting *inside* a `ScrollView(.horizontal)`.
//

import AppKit
import SwiftUI

/// Invisible probe that finds its enclosing NSScrollView once it lands in a
/// window, then intercepts vertical scroll-wheel events over that scroll
/// view and re-fires them as horizontal ones.
private final class ScrollWheelProbe: NSView {
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        teardown()
        guard let window, let scrollView = enclosingScrollView else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak scrollView] event in
            guard let scrollView, event.window === window else { return event }

            // Only step in over this specific scroll view's visible bounds.
            let pointInScrollView = scrollView.convert(event.locationInWindow, from: nil)
            guard scrollView.bounds.contains(pointInScrollView) else { return event }

            // Trackpads already send real horizontal deltas on a two-finger
            // side swipe — only translate when the motion is predominantly
            // vertical (an actual mouse wheel, or a straight up/down swipe).
            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }

            guard
                let cgEvent = event.cgEvent?.copy()
            else { return event }

            let verticalDelta = cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let verticalPointDelta = cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)

            // Move the vertical motion onto the horizontal axis. (If this
            // ever feels backwards on real hardware, negate verticalDelta /
            // verticalPointDelta below to flip the direction.)
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: verticalDelta)
            cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: verticalPointDelta)
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0)
            cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)

            guard let translated = NSEvent(cgEvent: cgEvent) else { return event }
            scrollView.scrollWheel(with: translated)
            return nil // swallow the original vertical scroll
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { teardown() }
        super.viewWillMove(toWindow: newWindow)
    }

    deinit { teardown() }

    private func teardown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct ScrollWheelProbeRepresentable: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView { ScrollWheelProbe(frame: .zero) }
    func updateNSView(_: NSView, context _: Context) {}
}

extension View {
    /// Lets a vertical mouse-wheel (or straight up/down trackpad) scroll
    /// drive a horizontal ScrollView. Attach to the view *inside* the
    /// ScrollView, not the ScrollView itself, so the probe ends up inside
    /// its document view and can find it via `enclosingScrollView`.
    func horizontalWheelScrolling() -> some View {
        background(ScrollWheelProbeRepresentable())
    }
}
