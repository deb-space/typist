// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import SwiftUI

/// A titled group of rows on a card.
struct CardSection<Content: View>: View {
    @Environment(\.palette) private var palette
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
            }
            VStack(spacing: 0) { content }
                .padding(.horizontal, 20)
                .card()
        }
    }
}

/// A setting: title and explanation on the left, its control on the right.
struct CardRow<Trailing: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String?
    let divider: Bool
    @ViewBuilder let trailing: Trailing

    init(_ title: String, _ subtitle: String? = nil, divider: Bool = true, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.divider = divider
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if divider { palette.border.frame(height: 1) }
        }
    }
}

extension View {
    func card(radius: CGFloat = 12) -> some View {
        modifier(CardBackground(radius: radius))
    }
}

private struct CardBackground: ViewModifier {
    @Environment(\.palette) private var palette
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(palette.border))
    }
}

// MARK: - Buttons

struct ThemedButtonStyle: ButtonStyle {
    enum Kind { case secondary, primary, destructive, quiet }
    var kind: Kind = .secondary
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        ThemedButton(configuration: configuration, kind: kind, small: small)
    }

    private struct ThemedButton: View {
        @Environment(\.palette) private var palette
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let kind: Kind
        let small: Bool

        var body: some View {
            configuration.label
                .font(.system(size: small ? 12 : 13, weight: kind == .primary ? .semibold : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, small ? 10 : 12)
                .frame(height: small ? 28 : 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(background))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(border))
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
                .contentShape(Rectangle())
        }

        private var foreground: Color {
            switch kind {
            case .primary: palette.onAccent
            case .destructive: palette.danger
            case .quiet: palette.secondaryText
            case .secondary: palette.text
            }
        }

        private var background: Color {
            switch kind {
            case .primary: palette.accent
            case .secondary: palette.control
            case .destructive, .quiet: .clear
            }
        }

        private var border: Color {
            switch kind {
            case .secondary: palette.controlBorder
            case .destructive: palette.danger.opacity(0.4)
            case .primary, .quiet: .clear
            }
        }
    }
}

extension ButtonStyle where Self == ThemedButtonStyle {
    static var themed: ThemedButtonStyle { ThemedButtonStyle() }
    static var themedPrimary: ThemedButtonStyle { ThemedButtonStyle(kind: .primary) }
    static var themedDestructive: ThemedButtonStyle { ThemedButtonStyle(kind: .destructive) }
    static var themedQuiet: ThemedButtonStyle { ThemedButtonStyle(kind: .quiet) }
    static var themedSmall: ThemedButtonStyle { ThemedButtonStyle(small: true) }
}

// MARK: - Inputs

/// A text field drawn in the theme's input colors.
struct ThemedField: View {
    @Environment(\.palette) private var palette
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(palette.input))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.inputBorder))
    }
}

/// A pop-up menu drawn as a themed control.
struct ThemedMenu<Value: Hashable>: View {
    @Environment(\.palette) private var palette
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    let label: String

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button(option.title) { selection = option.value }
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.value == selection }?.title ?? "")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 13))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(palette.control))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.controlBorder))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
    }
}

/// Two or more choices side by side, like the mockup's segmented control.
struct ThemedSegments<Value: Hashable>: View {
    @Environment(\.palette) private var palette
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button(option.title) { selection = option.value }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? palette.text : palette.secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(selected ? palette.control : .clear))
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.input))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.inputBorder))
    }
}

struct ThemedToggle: View {
    @Environment(\.palette) private var palette
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(palette.accent)
    }
}

// MARK: - Small pieces

/// A key drawn like a keycap.
struct Keycap: View {
    @Environment(\.palette) private var palette
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.keycapText)
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(palette.keycap))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.keycapShadow.opacity(0.5)))
            .background(RoundedRectangle(cornerRadius: 6).fill(palette.keycapShadow).offset(y: 2))
            .accessibilityLabel(label)
    }
}

/// A small status label.
struct Chip: View {
    @Environment(\.palette) private var palette
    let text: String
    var highlighted = false

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(highlighted ? palette.accentText : palette.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(highlighted ? palette.accent.opacity(0.16) : palette.control))
    }
}
