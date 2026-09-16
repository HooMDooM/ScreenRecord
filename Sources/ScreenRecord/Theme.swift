import SwiftUI
import AppKit

enum Theme {
    static let panelBackground = Color(red: 0.180, green: 0.169, blue: 0.196)
    static let fieldBackground = Color(red: 0.137, green: 0.129, blue: 0.153)
    static let rowBackground = Color(red: 0.220, green: 0.204, blue: 0.239)
    static let stroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.271, green: 0.855, blue: 0.541)
    static let recRed = Color(red: 0.925, green: 0.286, blue: 0.239)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.45)

    static let selectionGreen = NSColor(red: 0.271, green: 0.855, blue: 0.541, alpha: 1)
}

/// Small square checkbox in the accent color, used across the recording bar.
struct AccentToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Theme.accent, lineWidth: 1.5)
                .background(RoundedRectangle(cornerRadius: 3).fill(isOn ? Theme.accent : .clear))
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Color.black.opacity(0.8))
                    }
                }
                .frame(width: 14, height: 14)
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Dark rounded container that mimics the popup fields in the reference design.
struct DarkField<Content: View>: View {
    var content: () -> Content
    var body: some View {
        content()
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.fieldBackground))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.stroke))
    }
}

/// Hosting view whose buttons react to the very first click even when the
/// window is not key yet (plain NSHostingView swallows that click).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed ? Color.white.opacity(0.12) : .clear)
            )
            .contentShape(Rectangle())
    }
}
