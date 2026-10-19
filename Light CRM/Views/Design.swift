import SwiftUI
import CoreText

/// App-controlled surfaces are opaque in both appearances; no blur or shadows.
enum Design {
    static let radius: CGFloat = 8
    static let small: CGFloat = 4
    static let gap: CGFloat = 8
    static let inset: CGFloat = 16
    static let section: CGFloat = 24
    static let motion = 0.18
    static let title = typeface(30, weight: 750)
    static let heading = typeface(18, weight: 700)
    static let body = typeface(13, weight: 400)
    static let control = typeface(13, weight: 600)
    private static let fontRegistered: Bool = {
        guard let url = Bundle.main.url(forResource: "Outfit", withExtension: "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()
    static func typeface(_ size: CGFloat, weight: Double = 700) -> Font {
        guard fontRegistered else { return .system(size: size, weight: weight >= 600 ? .bold : .regular, design: .rounded) }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: "Outfit-Thin",
            kCTFontVariationAttribute: [NSNumber(value: 0x77676874): NSNumber(value: weight)]
        ] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
    static let background = adaptive(0xFFFFFF, 0x111827)
    static let foreground = adaptive(0x111827, 0xF3F4F6)
    static let muted = adaptive(0xF3F4F6, 0x1F2937)
    static let secondaryText = adaptive(0x4B5563, 0xB9C3D1)
    static let border = adaptive(0xE5E7EB, 0x4B5563)
    static let blue = adaptive(0x1D4ED8, 0x93B4FF)
    static let primaryFill = Color(hex: 0x1D4ED8)
    static let selection = adaptive(0xE8F0FF, 0x243B62)
    static let green = adaptive(0x047857, 0x6EE7B7)
    static let amber = adaptive(0x92400E, 0xFCD34D)
    static let red = adaptive(0xB91C1C, 0xFCA5A5)
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static func stageColor(_ stage: DealStage) -> Color {
        switch stage { case .won: green; case .lost: secondaryText; case .awaiting: amber; default: blue }
    }
}

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}

struct FlatButtonStyle: ButtonStyle {
    var primary = false
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        FlatButtonBody(configuration: configuration, primary: primary, destructive: destructive)
    }
    private struct FlatButtonBody: View {
        let configuration: Configuration
        let primary: Bool
        let destructive: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label.font(Design.control).padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(primary ? .white : destructive ? Design.red : Design.foreground)
                .background(primary ? (hovering ? Color(hex: 0x1E40AF) : Design.primaryFill) : hovering ? Design.selection : Design.muted, in: RoundedRectangle(cornerRadius: Design.radius))
                .overlay(RoundedRectangle(cornerRadius: Design.radius).strokeBorder(focused ? Design.foreground : configuration.isPressed ? Design.blue : .clear, lineWidth: 2))
                .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
                .onHover { hovering = $0 }
        }
    }
}

struct StageBadge: View {
    let stage: DealStage
    var body: some View {
        Label(stage.rawValue, systemImage: stage == .won ? "checkmark.circle.fill" : stage == .lost ? "xmark.circle" : "circle.fill")
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Design.stageColor(stage))
            .padding(.horizontal, 8).padding(.vertical, 5).background(Design.muted, in: Capsule())
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28, weight: .medium)).foregroundStyle(Design.blue)
                .frame(width: 64, height: 64).background(Design.selection, in: RoundedRectangle(cornerRadius: 8))
            Text(title).font(Design.heading)
            Text(detail).foregroundStyle(Design.secondaryText).multilineTextAlignment(.center).frame(maxWidth: 340)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DueLabel: View {
    let day: Day?
    var overdue = false
    var body: some View {
        Label(day?.label ?? "No date", systemImage: overdue ? "exclamationmark.circle" : "calendar")
            .foregroundStyle(overdue ? Design.red : Design.secondaryText)
            .font(.system(size: 12)).accessibilityLabel("\(overdue ? "Overdue, " : "")\(day?.label ?? "No due date")")
    }
}

struct Field: View {
    let label: String
    var placeholder = ""
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Design.control)
            TextField(placeholder, text: $text).textFieldStyle(.plain).padding(10)
                .background(Design.muted, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Design.blue : .clear, lineWidth: 2))
                .focused($focused).accessibilityLabel(label)
        }
    }
}

struct OptionalDayPicker: View {
    let title: String
    @Binding var day: Day?
    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(get: { day != nil }, set: { day = $0 ? Day() : nil }))
            Spacer()
            if day != nil {
                DatePicker(title, selection: Binding(get: { day?.date ?? .now }, set: { day = Day($0) }), displayedComponents: .date)
                    .labelsHidden().accessibilityLabel(title)
            } else { Text("Not scheduled").foregroundStyle(Design.secondaryText) }
        }.frame(minHeight: 30)
    }
}
