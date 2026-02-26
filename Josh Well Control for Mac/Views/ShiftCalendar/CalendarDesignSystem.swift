//
//  CalendarDesignSystem.swift
//  Josh Well Control for Mac
//
//  Centralized visual design for the shift calendar.
//

import SwiftUI

// MARK: - Shift Color Palette

enum ShiftColorPalette {
    static func color(for type: ShiftType) -> Color {
        switch type {
        case .day: return .blue
        case .night: return .purple
        case .off: return .gray
        }
    }

    static func gradient(for type: ShiftType) -> [Color] {
        switch type {
        case .day: return [.blue, .cyan]
        case .night: return [.purple, .indigo]
        case .off: return [.gray, .gray.opacity(0.7)]
        }
    }

    static func cellBackground(for type: ShiftType) -> Color {
        switch type {
        case .day: return .blue.opacity(0.08)
        case .night: return .purple.opacity(0.08)
        case .off: return .clear
        }
    }

    static func badgeColor(for type: ShiftType, confirmed: Bool = true) -> Color {
        let base = color(for: type)
        return confirmed ? base : base.opacity(0.4)
    }
}

// MARK: - Shift Badge

struct ShiftBadge: View {
    let shiftType: ShiftType
    let isConfirmed: Bool
    let compact: Bool

    init(_ type: ShiftType, confirmed: Bool = true, compact: Bool = false) {
        self.shiftType = type
        self.isConfirmed = confirmed
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: 3) {
            if !compact {
                Image(systemName: shiftType.icon)
                    .font(.system(size: 9))
            }
            Text(compact ? String(shiftType.displayName.prefix(1)) : shiftType.displayName)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(ShiftColorPalette.badgeColor(for: shiftType, confirmed: isConfirmed))
        .cornerRadius(compact ? 4 : 6)
    }
}

// MARK: - Calendar Card

struct CalendarCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(macOS)
            .background(.ultraThinMaterial)
            #else
            .background(Color(.systemBackground))
            #endif
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Shift Cell Background

struct ShiftCellBackground: View {
    let shiftType: ShiftType
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.2) : .clear, radius: 4, x: 0, y: 2)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return ShiftColorPalette.cellBackground(for: shiftType)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor
        }
        return .clear
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 0
    }
}

// MARK: - Confirmed/Predicted Indicator

struct ShiftConfirmationBar: View {
    let shiftType: ShiftType
    let isConfirmed: Bool

    var body: some View {
        let color = ShiftColorPalette.color(for: shiftType)

        if isConfirmed {
            Rectangle()
                .fill(color)
                .frame(height: 4)
        } else {
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(color.opacity(0.4))
                        .frame(width: 8, height: 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 4)
            .clipped()
        }
    }
}

// MARK: - Animation Constants

enum CalendarAnimation {
    static let cellSelection = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let monthTransition = Animation.easeInOut(duration: 0.25)
    static let viewModeSwitch = Animation.easeInOut(duration: 0.2)
}
