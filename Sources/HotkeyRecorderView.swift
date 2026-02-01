import AppKit
import HotKey
import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @Binding var isRecording: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(keyCode: $keyCode, modifiers: $modifiers, isRecording: $isRecording)
    }

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = { [weak coordinator = context.coordinator] newKeyCode, newModifiers in
            coordinator?.update(keyCode: Int(newKeyCode), modifiers: Int(newModifiers))
        }
        view.onRecordingEnded = { [weak coordinator = context.coordinator] in
            coordinator?.setRecording(false)
        }
        view.setKeyCombo(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.setKeyCombo(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        if isRecording {
            nsView.beginRecording()
        } else {
            nsView.endRecording()
        }
    }

    final class Coordinator {
        private var keyCode: Binding<Int>
        private var modifiers: Binding<Int>
        private var isRecording: Binding<Bool>

        init(keyCode: Binding<Int>, modifiers: Binding<Int>, isRecording: Binding<Bool>) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.isRecording = isRecording
        }

        func update(keyCode: Int, modifiers: Int) {
            self.keyCode.wrappedValue = keyCode
            self.modifiers.wrappedValue = modifiers
        }

        func setRecording(_ value: Bool) {
            isRecording.wrappedValue = value
        }
    }
}

final class RecorderView: NSView {
    var onChange: ((UInt32, UInt32) -> Void)?
    var onRecordingEnded: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var keyCode: UInt32 = 0
    private var modifiers: UInt32 = 0
    private(set) var isRecording = false {
        didSet {
            updateLabel()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.clear.cgColor

        // Inner backing for the recorder
        let bgLayer = CALayer()
        bgLayer.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
        bgLayer.cornerRadius = 8
        bgLayer.borderWidth = 1
        bgLayer.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        bgLayer.frame = bounds
        bgLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(bgLayer)

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 8, dy: 4)
    }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hotkeyFlags = flags.intersection([.command, .option, .control, .shift])

        guard !hotkeyFlags.isEmpty else {
            NSSound.beep()
            return
        }

        let newKeyCode = UInt32(event.keyCode)
        let newModifiers = hotkeyFlags.carbonFlags

        keyCode = newKeyCode
        modifiers = newModifiers
        onChange?(newKeyCode, newModifiers)
        endRecording()
        onRecordingEnded?()
    }

    override func flagsChanged(with event: NSEvent) {
        if isRecording {
            updateLabel(previewFlags: event.modifierFlags)
        }
    }

    func setKeyCombo(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        updateLabel()
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        window?.makeFirstResponder(self)
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
    }

    private func updateLabel(previewFlags: NSEvent.ModifierFlags? = nil) {
        if isRecording {
            if let previewFlags {
                let display = KeyCombo(
                    carbonKeyCode: keyCode,
                    carbonModifiers: previewFlags.intersection(.deviceIndependentFlagsMask)
                        .carbonFlags
                ).description
                label.stringValue =
                    display.isEmpty ? "Type shortcut..." : "Type shortcut... \(display)"
            } else {
                label.stringValue = "Type shortcut..."
            }
        } else {
            let display = KeyCombo(carbonKeyCode: keyCode, carbonModifiers: modifiers).description
            label.stringValue = display.isEmpty ? "Click to set shortcut" : display
        }
    }
}
