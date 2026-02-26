//
//  LookAheadGanttView.swift
//  Josh Well Control for Mac
//
//  Asana-style Gantt timeline view for look ahead tasks.
//

import SwiftUI
import SwiftData

// MARK: - Layout Constants

private enum GanttLayout {
    static let labelColumnWidth: CGFloat = 220
    static let rowHeight: CGFloat = 44
    static let rowSpacing: CGFloat = 4
    static let rowPitch: CGFloat = rowHeight + rowSpacing  // 48
    static let headerHeight: CGFloat = 44
    static let handleWidth: CGFloat = 24
    static let handlePillWidth: CGFloat = 3
    static let minBarWidthForText: CGFloat = 80
    static let minZoom: CGFloat = 15
    static let maxZoom: CGFloat = 240
    static let defaultZoom: CGFloat = 60
}

// MARK: - Main Gantt View

struct LookAheadGanttView: View {
    let schedule: LookAheadSchedule
    @Bindable var viewModel: LookAheadViewModel
    var onEditTask: (LookAheadTask) -> Void
    var onStartTask: (LookAheadTask) -> Void
    var onCompleteTask: (LookAheadTask) -> Void
    var onDelayTask: (LookAheadTask) -> Void
    var onDeleteTask: (LookAheadTask) -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var pixelsPerHour: CGFloat = GanttLayout.defaultZoom
    @State private var timelineScrollView: NSScrollView?
    @State private var labelScrollView: NSScrollView?
    @State private var scrollObserver: NSObjectProtocol?

    private var tasks: [LookAheadTask] { schedule.sortedTasks }

    private var timelineStart: Date { schedule.startDate }

    private var timelineEnd: Date {
        // Extend past the last task by at least 2 hours for breathing room
        let lastEnd = schedule.calculatedEndDate
        return lastEnd.addingTimeInterval(2 * 3600)
    }

    private var totalTimelineWidth: CGFloat {
        let hours = timelineEnd.timeIntervalSince(timelineStart) / 3600
        return CGFloat(hours) * pixelsPerHour
    }

    var body: some View {
        VStack(spacing: 0) {
            // Zoom toolbar
            ganttToolbar

            if tasks.isEmpty {
                ganttEmptyState
            } else {
                ganttContent
            }
        }
    }

    // MARK: - Zoom Toolbar

    private var ganttToolbar: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    pixelsPerHour = max(GanttLayout.minZoom, pixelsPerHour / 1.5)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(pixelsPerHour <= GanttLayout.minZoom)

            Text("\(Int(pixelsPerHour)) px/hr")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    pixelsPerHour = min(GanttLayout.maxZoom, pixelsPerHour * 1.5)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(pixelsPerHour >= GanttLayout.maxZoom)

            Divider().frame(height: 16)

            Button {
                scrollToNow()
            } label: {
                Label("Now", systemImage: "clock")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(schedule.totalDurationFormatted)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Main Content

    private var ganttContent: some View {
        HStack(alignment: .top, spacing: 0) {
            // Fixed label column — scrolls vertically only
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header spacer
                    Color.clear.frame(height: GanttLayout.headerHeight)
                    // Task labels
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        GanttTaskLabel(
                            task: task,
                            index: index,
                            isSelected: viewModel.selectedTask?.id == task.id
                        )
                        .frame(height: GanttLayout.rowHeight)
                        .padding(.vertical, GanttLayout.rowSpacing / 2)
                        .onTapGesture {
                            viewModel.selectedTask = task
                            scrollToTask(task)
                        }
                    }
                }
                .background(ScrollViewFinder(key: "labels", scrollView: $labelScrollView))
            }
            .frame(width: GanttLayout.labelColumnWidth)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Timeline — scrolls both directions
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Grid background
                    GanttGridBackground(
                        timelineStart: timelineStart,
                        timelineEnd: timelineEnd,
                        pixelsPerHour: pixelsPerHour,
                        rowCount: tasks.count,
                        totalWidth: totalTimelineWidth
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        // Time header
                        GanttTimelineHeader(
                            timelineStart: timelineStart,
                            timelineEnd: timelineEnd,
                            pixelsPerHour: pixelsPerHour
                        )
                        .frame(height: GanttLayout.headerHeight)

                        // Task bars
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            GanttTaskBar(
                                task: task,
                                timelineStart: timelineStart,
                                pixelsPerHour: pixelsPerHour,
                                isSelected: viewModel.selectedTask?.id == task.id,
                                onSelect: {
                                    viewModel.selectedTask = task
                                },
                                onEdit: { onEditTask(task) },
                                onResize: { newDuration in
                                    viewModel.updateDuration(task, newDuration: newDuration, context: modelContext)
                                },
                                onStart: { onStartTask(task) },
                                onComplete: { onCompleteTask(task) },
                                onDelay: { onDelayTask(task) },
                                onDelete: { onDeleteTask(task) }
                            )
                            .frame(height: GanttLayout.rowHeight)
                            .padding(.vertical, GanttLayout.rowSpacing / 2)
                        }
                    }

                    // Now line
                    GanttNowIndicator(
                        timelineStart: timelineStart,
                        pixelsPerHour: pixelsPerHour,
                        totalHeight: GanttLayout.headerHeight + CGFloat(tasks.count) * GanttLayout.rowPitch
                    )
                }
                .frame(width: totalTimelineWidth)
                .background(ScrollViewFinder(key: "timeline", scrollView: $timelineScrollView))
            }
            .onChange(of: timelineScrollView) {
                syncVerticalScroll()
            }
        }
    }

    // MARK: - Empty State

    private var ganttEmptyState: some View {
        ContentUnavailableView {
            Label("No Tasks", systemImage: "calendar.badge.plus")
        } description: {
            Text("Add tasks to the schedule to see them in the timeline.")
        }
    }

    // MARK: - Helpers

    private func xPosition(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(timelineStart) / 3600) * pixelsPerHour
    }

    private func scrollToTask(_ task: LookAheadTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let targetX = xPosition(for: task.startTime) - 20
        let targetY = GanttLayout.headerHeight + CGFloat(index) * GanttLayout.rowPitch - 20
        scrollTo(x: targetX, y: targetY)
    }

    private func scrollToNow() {
        let now = Date.now
        if let currentTask = tasks.first(where: { $0.startTime <= now && $0.endTime > now })
            ?? tasks.first(where: { $0.startTime > now }) {
            scrollToTask(currentTask)
        } else {
            let targetX = xPosition(for: now) - 20
            scrollTo(x: targetX, y: nil)
        }
    }

    private func scrollTo(x: CGFloat?, y: CGFloat?) {
        guard let scrollView = timelineScrollView,
              let docView = scrollView.documentView else { return }

        let currentOrigin = scrollView.contentView.bounds.origin
        let maxX = max(0, docView.frame.width - scrollView.contentSize.width)
        let maxY = max(0, docView.frame.height - scrollView.contentSize.height)

        let newX = x != nil ? max(0, min(x!, maxX)) : currentOrigin.x
        let newY = y != nil ? max(0, min(y!, maxY)) : currentOrigin.y

        // Animate with a smooth spring-like curve scaled to distance
        let dx = abs(newX - currentOrigin.x)
        let dy = abs(newY - currentOrigin.y)
        let distance = sqrt(dx * dx + dy * dy)
        let duration = min(0.8, max(0.25, Double(distance) / 1500))

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
            context.allowsImplicitAnimation = true
            scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: newX, y: newY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    /// Sync vertical scroll of timeline → label column
    private func syncVerticalScroll() {
        guard let timeline = timelineScrollView, let labels = labelScrollView else { return }
        // Remove old observer
        if let obs = scrollObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        // Observe timeline vertical scroll and mirror to labels
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: timeline.contentView,
            queue: .main
        ) { _ in
            let timelineY = timeline.contentView.bounds.origin.y
            let labelOrigin = labels.contentView.bounds.origin
            if abs(labelOrigin.y - timelineY) > 0.5 {
                labels.contentView.setBoundsOrigin(NSPoint(x: labelOrigin.x, y: timelineY))
            }
        }
        timeline.contentView.postsBoundsChangedNotifications = true
    }
}

// MARK: - NSScrollView Finder

private struct ScrollViewFinder: NSViewRepresentable {
    let key: String
    @Binding var scrollView: NSScrollView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        DispatchQueue.main.async {
            self.scrollView = findScrollView(in: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func findScrollView(in view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let v = current {
            if let sv = v as? NSScrollView {
                return sv
            }
            current = v.superview
        }
        return nil
    }
}

// MARK: - Task Label Column

private struct GanttTaskLabel: View {
    let task: LookAheadTask
    let index: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Sequence number
            Text("\(index + 1).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let jc = task.jobCode {
                        Text(jc.code)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(3)
                    }
                    Text(task.estimatedDurationFormatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }

    private var statusColor: Color {
        switch task.status {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .delayed: return .red
        case .cancelled: return .gray
        }
    }
}

// MARK: - Timeline Header

private struct GanttTimelineHeader: View {
    let timelineStart: Date
    let timelineEnd: Date
    let pixelsPerHour: CGFloat

    private var labelInterval: Int {
        // Adaptive: show fewer labels at low zoom
        if pixelsPerHour >= 120 { return 1 }
        if pixelsPerHour >= 60 { return 2 }
        if pixelsPerHour >= 30 { return 3 }
        return 6
    }

    private var hourMarks: [(date: Date, label: String, isDay: Bool)] {
        var marks: [(Date, String, Bool)] = []
        let calendar = Calendar.current
        var current = calendar.startOfDay(for: timelineStart)

        // Start from the beginning of the day
        while current < timelineEnd {
            let hour = calendar.component(.hour, from: current)
            let isDay = hour == 0

            if isDay || hour % labelInterval == 0 {
                let formatter = DateFormatter()
                if isDay {
                    formatter.dateFormat = "EEE d MMM"
                } else {
                    formatter.dateFormat = "HH:mm"
                }
                marks.append((current, formatter.string(from: current), isDay))
            }
            current = calendar.date(byAdding: .hour, value: 1, to: current) ?? current.addingTimeInterval(3600)
        }
        return marks
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor))

            // Hour labels
            ForEach(Array(hourMarks.enumerated()), id: \.offset) { _, mark in
                let x = xPosition(for: mark.date)
                VStack(spacing: 2) {
                    Spacer()
                    Text(mark.label)
                        .font(mark.isDay ? .caption.weight(.semibold) : .caption2)
                        .foregroundStyle(mark.isDay ? .primary : .secondary)
                    // Tick mark
                    Rectangle()
                        .fill(mark.isDay ? Color.primary.opacity(0.4) : Color.secondary.opacity(0.3))
                        .frame(width: mark.isDay ? 2 : 1, height: mark.isDay ? 8 : 5)
                }
                .position(x: x, y: GanttLayout.headerHeight / 2)
            }

            // Bottom border
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }
        }
    }

    private func xPosition(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(timelineStart) / 3600) * pixelsPerHour
    }
}

// MARK: - Grid Background

private struct GanttGridBackground: View {
    let timelineStart: Date
    let timelineEnd: Date
    let pixelsPerHour: CGFloat
    let rowCount: Int
    let totalWidth: CGFloat

    private var totalHeight: CGFloat {
        GanttLayout.headerHeight + CGFloat(rowCount) * GanttLayout.rowPitch
    }

    var body: some View {
        Canvas { context, size in
            let calendar = Calendar.current
            var current = calendar.startOfDay(for: timelineStart)

            while current < timelineEnd {
                let hour = calendar.component(.hour, from: current)
                let x = CGFloat(current.timeIntervalSince(timelineStart) / 3600) * pixelsPerHour

                if hour == 0 {
                    // Day separator — thicker
                    let path = Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    context.stroke(path, with: .color(.secondary.opacity(0.3)), lineWidth: 1.5)
                } else {
                    // Hour line — thin
                    let path = Path { p in
                        p.move(to: CGPoint(x: x, y: GanttLayout.headerHeight))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    context.stroke(path, with: .color(.secondary.opacity(0.1)), lineWidth: 0.5)
                }

                current = calendar.date(byAdding: .hour, value: 1, to: current) ?? current.addingTimeInterval(3600)
            }

            // Alternating row backgrounds
            for i in 0..<rowCount {
                let y = GanttLayout.headerHeight + CGFloat(i) * GanttLayout.rowPitch
                if i % 2 == 1 {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: GanttLayout.rowHeight)
                    context.fill(Path(rect), with: .color(.secondary.opacity(0.04)))
                }
            }
        }
        .frame(width: totalWidth, height: totalHeight)
        .allowsHitTesting(false)
    }
}

// MARK: - Now Indicator

private struct GanttNowIndicator: View {
    let timelineStart: Date
    let pixelsPerHour: CGFloat
    let totalHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let x = CGFloat(now.timeIntervalSince(timelineStart) / 3600) * pixelsPerHour

            if x > 0 {
                ZStack(alignment: .top) {
                    // Line
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2, height: totalHeight)

                    // Triangle marker
                    Triangle()
                        .fill(Color.red)
                        .frame(width: 10, height: 8)
                }
                .offset(x: x - 1)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

// MARK: - Task Bar

private struct GanttTaskBar: View {
    let task: LookAheadTask
    let timelineStart: Date
    let pixelsPerHour: CGFloat
    let isSelected: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onResize: (Double) -> Void
    var onStart: () -> Void
    var onComplete: () -> Void
    var onDelay: () -> Void
    var onDelete: () -> Void

    @State private var isDraggingHandle = false
    @State private var dragWidthDelta: CGFloat = 0
    @State private var isHovering = false
    @State private var isHoveringHandle = false

    private var barX: CGFloat {
        CGFloat(task.startTime.timeIntervalSince(timelineStart) / 3600) * pixelsPerHour
    }

    private var barWidth: CGFloat {
        CGFloat(task.estimatedDuration_min / 60.0) * pixelsPerHour
    }

    private var displayWidth: CGFloat {
        if isDraggingHandle {
            let snappedMinutes = snapToQuarterHour(
                task.estimatedDuration_min + Double(dragWidthDelta / pixelsPerHour) * 60
            )
            return CGFloat(snappedMinutes / 60.0) * pixelsPerHour
        }
        return barWidth
    }

    private var snappedDurationDuringDrag: Double {
        snapToQuarterHour(
            task.estimatedDuration_min + Double(dragWidthDelta / pixelsPerHour) * 60
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: barX, height: 1)
            barShape
            Spacer(minLength: 0)
        }
    }

    private var barShape: some View {
        ZStack(alignment: .leading) {
            // Main bar body
            RoundedRectangle(cornerRadius: 6)
                .fill(barGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isSelected ? Color.white.opacity(0.5) : Color.clear,
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 3 : 1, y: 1)

            // Bar content text
            if displayWidth > GanttLayout.minBarWidthForText {
                HStack {
                    Text(task.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isDraggingHandle {
                        Text(formatDuration(snappedDurationDuringDrag))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.9))
                    } else {
                        Text(task.estimatedDurationFormatted)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 8)
            }

            // Resize handle on right edge
            HStack {
                Spacer()
                resizeHandle
            }
        }
        .frame(width: max(displayWidth, 4), height: GanttLayout.rowHeight)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            onEdit()
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            Divider()
            if task.status == .scheduled {
                Button { onStart() } label: {
                    Label("Start Task", systemImage: "play.fill")
                }
            }
            if task.status == .inProgress || task.status == .scheduled {
                Button { onComplete() } label: {
                    Label("Complete", systemImage: "checkmark.circle")
                }
            }
            if task.status != .delayed && task.status != .cancelled {
                Button { onDelay() } label: {
                    Label("Mark Delayed", systemImage: "exclamationmark.triangle")
                }
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .help("\(task.name)\n\(task.timeRangeFormatted)\n\(task.estimatedDurationFormatted)")
    }

    // MARK: - Resize Handle

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: GanttLayout.handleWidth)
            .overlay(alignment: .trailing) {
                // Visual pill indicator
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(isDraggingHandle ? 0.8 : (isHoveringHandle ? 0.6 : 0.4)))
                    .frame(width: GanttLayout.handlePillWidth, height: 20)
                    .padding(.trailing, 4)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHoveringHandle = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        isDraggingHandle = true
                        dragWidthDelta = value.translation.width
                    }
                    .onEnded { value in
                        let rawMinutes = task.estimatedDuration_min + Double(value.translation.width / pixelsPerHour) * 60
                        let snapped = snapToQuarterHour(rawMinutes)
                        isDraggingHandle = false
                        dragWidthDelta = 0
                        onResize(snapped)
                    }
            )
    }

    // MARK: - Styling

    private var barGradient: LinearGradient {
        let baseColor = statusColor
        return LinearGradient(
            colors: [baseColor, baseColor.opacity(0.8)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var statusColor: Color {
        switch task.status {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .delayed: return .red
        case .cancelled: return .gray
        }
    }

    // MARK: - Helpers

    private func snapToQuarterHour(_ rawMinutes: Double) -> Double {
        max(15, (rawMinutes / 15.0).rounded() * 15.0)
    }

    private func formatDuration(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

