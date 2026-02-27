//
//  EquipmentTimelineView.swift
//  Josh Well Control for Mac
//
//  Gantt-style timeline showing rental periods per equipment.
//  Adapted from LookAheadGanttView patterns.
//  Bars are resizable — drag left edge to adjust start date, right edge to adjust end date.
//

import SwiftUI

#if os(macOS)
import AppKit

// MARK: - Layout Constants

private enum TimelineLayout {
    static let labelColumnWidth: CGFloat = 220
    static let rowHeight: CGFloat = 44
    static let rowSpacing: CGFloat = 4
    static let rowPitch: CGFloat = 48  // rowHeight + rowSpacing
    static let headerHeight: CGFloat = 44
    static let defaultPixelsPerDay: CGFloat = 20
    static let minPixelsPerDay: CGFloat = 5
    static let maxPixelsPerDay: CGFloat = 80
    static let barCornerRadius: CGFloat = 4
    static let barVerticalInset: CGFloat = 4
    static let handleWidth: CGFloat = 12
    static let handlePillWidth: CGFloat = 3
    static let minBarDays: Int = 1
}

// MARK: - Main View

struct EquipmentTimelineView: View {
    let equipment: [RentalEquipment]
    @Binding var selectedID: RentalEquipment.ID?
    var onDateChange: ((RentalItem, Date?, Date?) -> Void)?

    @State private var pixelsPerDay: CGFloat = TimelineLayout.defaultPixelsPerDay
    @State private var labelScrollView: NSScrollView?
    @State private var timelineScrollView: NSScrollView?

    // Date range
    private var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        var earliest = Date.now
        var latest = Date.now

        for eq in equipment {
            for rental in eq.sortedRentals {
                if let start = rental.startDate {
                    earliest = min(earliest, start)
                }
                if let end = rental.endDate {
                    latest = max(latest, end)
                } else if rental.startDate != nil {
                    latest = max(latest, Date.now)
                }
            }
        }

        // Add padding
        earliest = calendar.date(byAdding: .day, value: -7, to: earliest) ?? earliest
        latest = calendar.date(byAdding: .day, value: 14, to: latest) ?? latest

        return (earliest, latest)
    }

    private var totalDays: Int {
        let range = dateRange
        return max(1, Calendar.current.dateComponents([.day], from: range.start, to: range.end).day ?? 1)
    }

    private var totalTimelineWidth: CGFloat {
        CGFloat(totalDays) * pixelsPerDay
    }

    var body: some View {
        VStack(spacing: 0) {
            zoomToolbar
            Divider()

            HStack(spacing: 0) {
                // Label column
                VStack(spacing: 0) {
                    Color.clear.frame(height: TimelineLayout.headerHeight)
                    Divider()

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(equipment) { eq in
                                equipmentLabel(eq)
                                    .frame(height: TimelineLayout.rowPitch)
                                    .background(selectedID == eq.id ? Color.accentColor.opacity(0.12) : .clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedID = eq.id
                                    }
                            }
                        }
                        .background(
                            ScrollViewFinder { scrollView in
                                labelScrollView = scrollView
                            }
                        )
                    }
                }
                .frame(width: TimelineLayout.labelColumnWidth)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Timeline area
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        timelineHeader
                            .frame(height: TimelineLayout.headerHeight)

                        Divider()

                        ZStack(alignment: .topLeading) {
                            gridBackground
                            rowHighlight
                            rentalBars
                            nowIndicator
                        }
                        .frame(
                            width: totalTimelineWidth,
                            height: CGFloat(equipment.count) * TimelineLayout.rowPitch
                        )
                    }
                    .background(
                        ScrollViewFinder { scrollView in
                            timelineScrollView = scrollView
                            syncVerticalScroll()
                        }
                    )
                }
            }
        }
    }

    // MARK: - Zoom Toolbar

    private var zoomToolbar: some View {
        HStack {
            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    pixelsPerDay = max(TimelineLayout.minPixelsPerDay, pixelsPerDay / 1.5)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Text("\(Int(pixelsPerDay))px/day")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    pixelsPerDay = min(TimelineLayout.maxPixelsPerDay, pixelsPerDay * 1.5)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    pixelsPerDay = TimelineLayout.defaultPixelsPerDay
                }
            } label: {
                Text("Reset")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Equipment Label

    private func equipmentLabel(_ eq: RentalEquipment) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(eq.locationStatus.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(eq.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let category = eq.category {
                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Timeline Header

    private var timelineHeader: some View {
        Canvas { context, size in
            let range = dateRange
            let calendar = Calendar.current

            let dayInterval: Int
            if pixelsPerDay >= 40 {
                dayInterval = 1
            } else if pixelsPerDay >= 15 {
                dayInterval = 7
            } else {
                dayInterval = 14
            }

            var currentDate = range.start
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"

            while currentDate <= range.end {
                let days = calendar.dateComponents([.day], from: range.start, to: currentDate).day ?? 0
                let x = CGFloat(days) * pixelsPerDay

                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: size.height - 8))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(.secondary.opacity(0.5)),
                    lineWidth: 1
                )

                let text = Text(formatter.string(from: currentDate))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: x + 4, y: size.height - 16),
                    anchor: .leading
                )

                currentDate = calendar.date(byAdding: .day, value: dayInterval, to: currentDate) ?? range.end
            }
        }
    }

    // MARK: - Grid Background

    private var gridBackground: some View {
        Canvas { context, size in
            let range = dateRange
            let calendar = Calendar.current

            var currentDate = range.start
            while currentDate <= range.end {
                let days = calendar.dateComponents([.day], from: range.start, to: currentDate).day ?? 0
                let x = CGFloat(days) * pixelsPerDay
                let isMonday = calendar.component(.weekday, from: currentDate) == 2
                let opacity: Double = isMonday ? 0.15 : 0.06

                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(.secondary.opacity(opacity)),
                    lineWidth: isMonday ? 1 : 0.5
                )

                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? range.end.addingTimeInterval(1)
            }

            for i in 0...equipment.count {
                let y = CGFloat(i) * TimelineLayout.rowPitch
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    },
                    with: .color(.secondary.opacity(0.08)),
                    lineWidth: 0.5
                )
            }
        }
    }

    // MARK: - Row Highlight (selected equipment)

    private var rowHighlight: some View {
        ForEach(Array(equipment.enumerated()), id: \.element.id) { rowIndex, eq in
            if eq.id == selectedID {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: totalTimelineWidth, height: TimelineLayout.rowPitch)
                    .offset(y: CGFloat(rowIndex) * TimelineLayout.rowPitch)
            }
        }
    }

    // MARK: - Rental Bars

    private var rentalBars: some View {
        ForEach(Array(equipment.enumerated()), id: \.element.id) { rowIndex, eq in
            ForEach(eq.sortedRentals) { rental in
                if rental.startDate != nil {
                    RentalBar(
                        rental: rental,
                        rowIndex: rowIndex,
                        timelineStart: dateRange.start,
                        pixelsPerDay: pixelsPerDay,
                        isRowSelected: eq.id == selectedID,
                        onSelect: {
                            selectedID = eq.id
                        },
                        onDateChange: onDateChange
                    )
                }
            }
        }
    }

    // MARK: - Now Indicator

    private var nowIndicator: some View {
        let range = dateRange
        let calendar = Calendar.current
        let daysFromStart = CGFloat(calendar.dateComponents([.day], from: range.start, to: Date.now).day ?? 0)
        let x = daysFromStart * pixelsPerDay

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.red)
                .frame(width: 1.5)
                .frame(maxHeight: .infinity)

            Path { path in
                path.move(to: CGPoint(x: -5, y: 0))
                path.addLine(to: CGPoint(x: 5, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 6))
                path.closeSubpath()
            }
            .fill(Color.red)
        }
        .offset(x: x)
    }

    // MARK: - Scroll Sync

    private func syncVerticalScroll() {
        guard let timeline = timelineScrollView,
              let labels = labelScrollView else { return }

        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: timeline.contentView,
            queue: .main
        ) { _ in
            let timelineY = timeline.contentView.bounds.origin.y
            if labels.contentView.bounds.origin.y != timelineY {
                labels.contentView.scroll(to: NSPoint(x: 0, y: timelineY))
                labels.reflectScrolledClipView(labels.contentView)
            }
        }
        timeline.contentView.postsBoundsChangedNotifications = true
    }
}

// MARK: - Rental Bar (Interactive)

/// A single rental period bar with drag handles on both edges to adjust start/end dates.
private struct RentalBar: View {
    let rental: RentalItem
    let rowIndex: Int
    let timelineStart: Date
    let pixelsPerDay: CGFloat
    var isRowSelected: Bool = false
    var onSelect: (() -> Void)?
    var onDateChange: ((RentalItem, Date?, Date?) -> Void)?

    @State private var isDraggingLeft = false
    @State private var isDraggingRight = false
    @State private var leftDragDelta: CGFloat = 0
    @State private var rightDragDelta: CGFloat = 0
    @State private var isHovering = false

    private let calendar = Calendar.current

    private var startDate: Date { rental.startDate ?? .now }
    private var endDate: Date { rental.endDate ?? .now }

    // Base positions (before drag)
    private var baseStartDays: CGFloat {
        CGFloat(calendar.dateComponents([.day], from: timelineStart, to: startDate).day ?? 0)
    }
    private var baseDurationDays: CGFloat {
        max(1, CGFloat(calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1))
    }

    // Snapped delta in whole days
    private var leftDeltaDays: Int {
        Int((leftDragDelta / pixelsPerDay).rounded())
    }
    private var rightDeltaDays: Int {
        Int((rightDragDelta / pixelsPerDay).rounded())
    }

    // Display values during drag
    private var displayStartDays: CGFloat {
        if isDraggingLeft {
            // Clamp so bar stays at least 1 day wide
            let maxShift = Int(baseDurationDays) - TimelineLayout.minBarDays
            let clamped = min(leftDeltaDays, maxShift)
            return baseStartDays + CGFloat(clamped)
        }
        return baseStartDays
    }

    private var displayDurationDays: CGFloat {
        if isDraggingLeft {
            let maxShift = Int(baseDurationDays) - TimelineLayout.minBarDays
            let clamped = min(leftDeltaDays, maxShift)
            return max(CGFloat(TimelineLayout.minBarDays), baseDurationDays - CGFloat(clamped))
        }
        if isDraggingRight {
            let newDuration = baseDurationDays + CGFloat(rightDeltaDays)
            return max(CGFloat(TimelineLayout.minBarDays), newDuration)
        }
        return baseDurationDays
    }

    private var displayX: CGFloat { displayStartDays * pixelsPerDay }
    private var displayWidth: CGFloat { displayDurationDays * pixelsPerDay }
    private var barHeight: CGFloat { TimelineLayout.rowHeight - TimelineLayout.barVerticalInset * 2 }
    private var offsetY: CGFloat { CGFloat(rowIndex) * TimelineLayout.rowPitch + TimelineLayout.barVerticalInset }

    // Label shown during drag
    private var dragLabel: String {
        let days = Int(displayDurationDays)
        let newStart = calendar.date(byAdding: .day, value: Int(displayStartDays - baseStartDays), to: startDate) ?? startDate
        let newEnd = calendar.date(byAdding: .day, value: days, to: newStart) ?? endDate
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: newStart)) – \(fmt.string(from: newEnd)) (\(days)d)"
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Main bar body
            RoundedRectangle(cornerRadius: TimelineLayout.barCornerRadius)
                .fill(barGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: TimelineLayout.barCornerRadius)
                        .strokeBorder(
                            (isDraggingLeft || isDraggingRight) ? Color.white.opacity(0.5) : .clear,
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 3 : 1, y: 1)

            // Bar content text
            if isDraggingLeft || isDraggingRight {
                // Show date range during drag
                Text(dragLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, TimelineLayout.handleWidth + 2)
            } else if displayWidth > 60 {
                Text(rental.well?.name ?? rental.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, TimelineLayout.handleWidth + 2)
            }

            // Left resize handle
            HStack {
                leftHandle
                Spacer(minLength: 0)
            }

            // Right resize handle
            HStack {
                Spacer(minLength: 0)
                rightHandle
            }
        }
        .frame(width: max(4, displayWidth), height: barHeight)
        .overlay(
            RoundedRectangle(cornerRadius: TimelineLayout.barCornerRadius)
                .strokeBorder(isRowSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .offset(x: displayX, y: offsetY)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onSelect?()
        }
        .help("\(rental.well?.name ?? "Unknown") – \(rental.totalDays) days\nDrag edges to adjust dates")
    }

    // MARK: - Left Handle (adjusts start date)

    private var leftHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: TimelineLayout.handleWidth)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(isDraggingLeft ? 0.8 : (isHovering ? 0.5 : 0)))
                    .frame(width: TimelineLayout.handlePillWidth, height: 18)
                    .padding(.leading, 3)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        isDraggingLeft = true
                        leftDragDelta = value.translation.width
                    }
                    .onEnded { _ in
                        commitLeftDrag()
                        isDraggingLeft = false
                        leftDragDelta = 0
                    }
            )
    }

    // MARK: - Right Handle (adjusts end date)

    private var rightHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: TimelineLayout.handleWidth)
            .overlay(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(isDraggingRight ? 0.8 : (isHovering ? 0.5 : 0)))
                    .frame(width: TimelineLayout.handlePillWidth, height: 18)
                    .padding(.trailing, 3)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        isDraggingRight = true
                        rightDragDelta = value.translation.width
                    }
                    .onEnded { _ in
                        commitRightDrag()
                        isDraggingRight = false
                        rightDragDelta = 0
                    }
            )
    }

    // MARK: - Commit Changes

    private func commitLeftDrag() {
        let maxShift = Int(baseDurationDays) - TimelineLayout.minBarDays
        let daysDelta = min(leftDeltaDays, maxShift)
        guard daysDelta != 0 else { return }

        let newStart = calendar.date(byAdding: .day, value: daysDelta, to: startDate) ?? startDate
        onDateChange?(rental, newStart, rental.endDate)
    }

    private func commitRightDrag() {
        let newDuration = max(TimelineLayout.minBarDays, Int(baseDurationDays) + rightDeltaDays)
        guard newDuration != Int(baseDurationDays) else { return }

        let newEnd = calendar.date(byAdding: .day, value: newDuration, to: startDate) ?? endDate
        onDateChange?(rental, rental.startDate, newEnd)
    }

    // MARK: - Styling

    private var barGradient: LinearGradient {
        let base = RentalStatusPalette.color(for: rental.status)
        return LinearGradient(
            colors: [base, base.opacity(0.75)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - ScrollViewFinder

/// NSViewRepresentable to get a reference to the underlying NSScrollView.
private struct ScrollViewFinder: NSViewRepresentable {
    let onFind: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                onFind(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
