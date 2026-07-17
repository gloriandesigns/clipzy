//
//  EventMonitors.swift
//  Clipzy
//
//  Created by 秋星桥 on 2024/7/7.
//

import Cocoa
import Combine

class EventMonitors {
    static let shared = EventMonitors()

    private var mouseMoveEvent: EventMonitor!
    private var mouseDownEvent: EventMonitor!
    private var mouseDraggingFileEvent: EventMonitor!
    private var optionKeyPressEvent: EventMonitor!
    private var keyDownEvent: EventMonitor!

    let mouseLocation: CurrentValueSubject<NSPoint, Never> = .init(.zero)
    let mouseDown: PassthroughSubject<Void, Never> = .init()
    let mouseDownFlags: CurrentValueSubject<NSEvent.ModifierFlags, Never> = .init([])
    let mouseDraggingFile: PassthroughSubject<Void, Never> = .init()
    let optionKeyPress: CurrentValueSubject<Bool, Never> = .init(false)
    let commandKeyPress: CurrentValueSubject<Bool, Never> = .init(false)
    let keyDown: PassthroughSubject<NSEvent, Never> = .init()

    private init() {
        mouseMoveEvent = EventMonitor(mask: .mouseMoved) { [weak self] _ in
            guard let self else { return }
            let mouseLocation = NSEvent.mouseLocation
            self.mouseLocation.send(mouseLocation)
        }
        mouseMoveEvent.start()

        mouseDownEvent = EventMonitor(mask: .leftMouseDown) { [weak self] event in
            guard let self else { return }
            mouseDownFlags.send(event?.modifierFlags ?? [])
            mouseDown.send()
        }
        mouseDownEvent.start()

        mouseDraggingFileEvent = EventMonitor(mask: .leftMouseDragged) { [weak self] _ in
            guard let self else { return }
            mouseDraggingFile.send()
        }
        mouseDraggingFileEvent.start()

        keyDownEvent = EventMonitor(mask: .keyDown) { [weak self] event in
            guard let self, let event else { return }
            keyDown.send(event)
        }
        keyDownEvent.start()

        optionKeyPressEvent = EventMonitor(mask: .flagsChanged) { [weak self] event in
            guard let self else { return }
            optionKeyPress.send(event?.modifierFlags.contains(.option) == true)
            commandKeyPress.send(event?.modifierFlags.contains(.command) == true)
        }
        optionKeyPressEvent.start()
    }
}
