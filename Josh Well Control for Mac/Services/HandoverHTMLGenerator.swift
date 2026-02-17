//
//  HandoverHTMLGenerator.swift
//  Josh Well Control for Mac
//
//  HTML report generator for Handover reports
//

import Foundation

/// Input data for generating a handover HTML report
struct HandoverReportData {
    let reportTitle: String
    let startDate: Date
    let endDate: Date
    let generatedDate: Date
    let shiftTypeFilter: String? // "Day", "Night", or nil for all

    struct TaskItem {
        let title: String
        let description: String
        let priority: String
        let status: String
        let dueDate: Date?
        let createdAt: Date
        let isOverdue: Bool
        let author: String
    }

    struct NoteItem {
        let title: String
        let content: String
        let category: String
        let priority: String
        let author: String
        let createdAt: Date
        let isPinned: Bool
    }

    struct WellGroup {
        let wellName: String
        let tasks: [TaskItem]
        let notes: [NoteItem]
    }

    struct PadGroup {
        let padName: String
        let padTasks: [TaskItem]
        let padNotes: [NoteItem]
        let wells: [WellGroup]
    }

    let padGroups: [PadGroup]

    var totalTasks: Int {
        var count = 0
        for group in padGroups {
            count += group.padTasks.count
            for well in group.wells { count += well.tasks.count }
        }
        return count
    }

    var totalNotes: Int {
        var count = 0
        for group in padGroups {
            count += group.padNotes.count
            for well in group.wells { count += well.notes.count }
        }
        return count
    }

    var overdueTasks: Int {
        var count = 0
        for group in padGroups {
            count += group.padTasks.filter { $0.isOverdue }.count
            for well in group.wells { count += well.tasks.filter { $0.isOverdue }.count }
        }
        return count
    }

    var completedTasks: Int {
        var count = 0
        for group in padGroups {
            count += group.padTasks.filter { $0.status == "Completed" }.count
            for well in group.wells { count += well.tasks.filter { $0.status == "Completed" }.count }
        }
        return count
    }
}

/// Cross-platform HTML generator for handover reports
class HandoverHTMLGenerator {
    static let shared = HandoverHTMLGenerator()
    private init() {}

    func generateHTML(for data: HandoverReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        let startStr = dateFormatter.string(from: data.startDate)
        let endStr = dateFormatter.string(from: data.endDate)

        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"
        let generatedStr = dateFormatter.string(from: data.generatedDate)

        let shiftLabel = data.shiftTypeFilter.map { " (\($0) Shift)" } ?? ""

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(data.reportTitle))</title>
            <style>
            \(generateCSS())
            </style>
        </head>
        <body>
            <header>
                <h1>Handover Report\(escapeHTML(shiftLabel))</h1>
                <p class="date-range">\(escapeHTML(startStr)) — \(escapeHTML(endStr))</p>
                <p class="generated">Generated \(escapeHTML(generatedStr))</p>
            </header>

            <main>
        """

        // Summary cards
        html += """
                <section class="card summary-section">
                    <h2>Summary</h2>
                    <div class="metrics-grid">
                        <div class="metric-box">
                            <div class="metric-value">\(data.totalTasks)</div>
                            <div class="metric-title">Total Tasks</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-value">\(data.totalNotes)</div>
                            <div class="metric-title">Total Notes</div>
                        </div>
                        <div class="metric-box metric-warning">
                            <div class="metric-value">\(data.overdueTasks)</div>
                            <div class="metric-title">Overdue</div>
                        </div>
                        <div class="metric-box metric-success">
                            <div class="metric-value">\(data.completedTasks)</div>
                            <div class="metric-title">Completed</div>
                        </div>
                    </div>
                </section>
        """

        // Pad groups
        for padGroup in data.padGroups {
            html += """
                    <section class="card pad-section">
                        <div class="pad-header">
                            <h2>Pad: \(escapeHTML(padGroup.padName))</h2>
                        </div>
            """

            // Pad-level tasks
            if !padGroup.padTasks.isEmpty {
                html += renderTasksSection(padGroup.padTasks, title: "Pad Tasks", indent: false)
            }

            // Pad-level notes
            if !padGroup.padNotes.isEmpty {
                html += renderNotesSection(padGroup.padNotes, title: "Pad Notes", indent: false)
            }

            // Wells within pad
            for well in padGroup.wells {
                html += """
                            <div class="well-section">
                                <h3>\(escapeHTML(well.wellName))</h3>
                """

                if !well.tasks.isEmpty {
                    html += renderTasksSection(well.tasks, title: "Tasks", indent: true)
                }

                if !well.notes.isEmpty {
                    html += renderNotesSection(well.notes, title: "Notes", indent: true)
                }

                if well.tasks.isEmpty && well.notes.isEmpty {
                    html += """
                                    <p class="empty-message">No tasks or notes for this period</p>
                    """
                }

                html += """
                            </div>
                """
            }

            html += """
                    </section>
            """
        }

        html += """
            </main>

            <footer>
                <p>Generated by Josh Well Control</p>
            </footer>
        </body>
        </html>
        """

        return html
    }

    // MARK: - Section Renderers

    private func renderTasksSection(_ tasks: [HandoverReportData.TaskItem], title: String, indent: Bool) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"

        var html = """
                        <div class="tasks-section\(indent ? " indented" : "")">
                            <h4 class="section-label tasks-label">\(escapeHTML(title)) (\(tasks.count))</h4>
        """

        for task in tasks {
            let priorityClass = "priority-\(task.priority.lowercased())"
            let statusClass = task.status == "Completed" ? "status-completed" : (task.isOverdue ? "status-overdue" : "status-active")
            let statusLabel = task.status == "Completed" ? "DONE" : (task.isOverdue ? "OVERDUE" : task.status)

            html += """
                            <div class="task-item \(statusClass)">
                                <div class="task-header">
                                    <span class="priority-dot \(priorityClass)"></span>
                                    <span class="task-title\(task.status == "Completed" ? " completed" : "")">\(escapeHTML(task.title))</span>
                                    <span class="status-badge \(statusClass)">\(escapeHTML(statusLabel))</span>
                                </div>
            """

            if !task.description.isEmpty {
                html += """
                                <div class="task-description">\(escapeHTML(task.description))</div>
                """
            }

            var meta: [String] = []
            meta.append(dateFormatter.string(from: task.createdAt))
            if let due = task.dueDate {
                let dueClass = task.isOverdue ? " class=\"overdue\"" : ""
                meta.append("<span\(dueClass)>Due: \(escapeHTML(dateFormatter.string(from: due)))</span>")
            }
            if !task.author.isEmpty {
                meta.append("By: \(escapeHTML(task.author))")
            }
            meta.append("<span class=\"\(priorityClass)\">\(escapeHTML(task.priority))</span>")

            html += """
                                <div class="task-meta">\(meta.joined(separator: " &middot; "))</div>
                            </div>
            """
        }

        html += """
                        </div>
        """

        return html
    }

    private func renderNotesSection(_ notes: [HandoverReportData.NoteItem], title: String, indent: Bool) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"

        var html = """
                        <div class="notes-section\(indent ? " indented" : "")">
                            <h4 class="section-label notes-label">\(escapeHTML(title)) (\(notes.count))</h4>
        """

        for note in notes {
            let categoryClass = "category-\(note.category.lowercased())"
            let priorityClass = "priority-\(note.priority.lowercased())"
            let pinIcon = note.isPinned ? "<span class=\"pin-icon\" title=\"Pinned\">&#128204;</span> " : ""

            html += """
                            <div class="note-item">
                                <div class="note-header">
                                    \(pinIcon)<span class="priority-dot \(priorityClass)"></span>
                                    <span class="note-title">\(escapeHTML(note.title))</span>
                                    <span class="category-badge \(categoryClass)">\(escapeHTML(note.category))</span>
                                </div>
            """

            if !note.content.isEmpty {
                html += """
                                <div class="note-content">\(renderNoteContent(note.content))</div>
                """
            }

            var meta: [String] = []
            meta.append(dateFormatter.string(from: note.createdAt))
            if !note.author.isEmpty {
                meta.append("By: \(escapeHTML(note.author))")
            }
            meta.append("<span class=\"\(priorityClass)\">\(escapeHTML(note.priority))</span>")

            html += """
                                <div class="note-meta">\(meta.joined(separator: " &middot; "))</div>
                            </div>
            """
        }

        html += """
                        </div>
        """

        return html
    }

    // MARK: - Note Content Parser (Markdown Lists)

    private func renderNoteContent(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var html = ""
        var inUL = false
        var inOL = false

        for line in lines {
            if line.hasPrefix("- ") {
                if inOL { html += "</ol>"; inOL = false }
                if !inUL { html += "<ul>"; inUL = true }
                html += "<li>\(escapeHTML(String(line.dropFirst(2))))</li>"
            } else if line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                if inUL { html += "</ul>"; inUL = false }
                if !inOL { html += "<ol>"; inOL = true }
                let text = line.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                html += "<li>\(escapeHTML(text))</li>"
            } else {
                if inUL { html += "</ul>"; inUL = false }
                if inOL { html += "</ol>"; inOL = false }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    html += "<p>\(escapeHTML(line))</p>"
                }
            }
        }

        if inUL { html += "</ul>" }
        if inOL { html += "</ol>" }

        return html
    }

    // MARK: - CSS

    private func generateCSS() -> String {
        return """
        :root {
            --brand-color: #2196f3;
            --brand-light: #e3f2fd;
            --safe-color: #4caf50;
            --warning-color: #ff9800;
            --danger-color: #f44336;
            --bg-color: #f5f5f5;
            --card-bg: #ffffff;
            --text-color: #333333;
            --text-light: #666666;
            --text-muted: #999999;
            --border-color: #e0e0e0;
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg-color);
            color: var(--text-color);
            line-height: 1.6;
        }

        header {
            background: var(--brand-color);
            color: white;
            padding: 24px 32px;
            position: sticky;
            top: 0;
            z-index: 100;
        }

        header h1 {
            font-size: 24px;
            font-weight: 700;
            margin-bottom: 4px;
        }

        header .date-range {
            font-size: 16px;
            opacity: 0.9;
        }

        header .generated {
            font-size: 12px;
            opacity: 0.7;
        }

        main {
            max-width: 960px;
            margin: 24px auto;
            padding: 0 16px;
        }

        .card {
            background: var(--card-bg);
            border-radius: 8px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            padding: 20px;
            margin-bottom: 20px;
        }

        .card h2 {
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 16px;
            color: var(--text-color);
        }

        /* Summary Metrics */
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
            gap: 12px;
        }

        .metric-box {
            background: var(--brand-light);
            border-radius: 8px;
            padding: 16px;
            text-align: center;
        }

        .metric-box .metric-value {
            font-size: 28px;
            font-weight: 700;
            color: var(--brand-color);
        }

        .metric-box .metric-title {
            font-size: 12px;
            color: var(--text-light);
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-top: 4px;
        }

        .metric-warning {
            background: #fff3e0;
        }
        .metric-warning .metric-value {
            color: var(--warning-color);
        }

        .metric-success {
            background: #e8f5e9;
        }
        .metric-success .metric-value {
            color: var(--safe-color);
        }

        /* Pad & Well Sections */
        .pad-header {
            background: #e8eaf6;
            margin: -20px -20px 16px -20px;
            padding: 12px 20px;
            border-radius: 8px 8px 0 0;
        }

        .pad-header h2 {
            margin-bottom: 0;
            color: #3f51b5;
        }

        .well-section {
            border-left: 3px solid var(--brand-color);
            padding-left: 16px;
            margin: 16px 0;
        }

        .well-section h3 {
            font-size: 15px;
            font-weight: 600;
            margin-bottom: 12px;
            color: var(--brand-color);
        }

        .indented {
            margin-left: 8px;
        }

        /* Section Labels */
        .section-label {
            font-size: 13px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 8px;
        }

        .tasks-label { color: #1565c0; }
        .notes-label { color: #2e7d32; }

        /* Task Items */
        .task-item {
            border: 1px solid var(--border-color);
            border-radius: 6px;
            padding: 10px 12px;
            margin-bottom: 8px;
            transition: background 0.15s;
        }

        .task-item:hover {
            background: #fafafa;
        }

        .task-header {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 4px;
        }

        .task-title {
            font-weight: 600;
            font-size: 14px;
            flex: 1;
        }

        .task-title.completed {
            text-decoration: line-through;
            opacity: 0.6;
        }

        .task-description {
            font-size: 13px;
            color: var(--text-light);
            margin: 4px 0 4px 18px;
        }

        .task-meta {
            font-size: 11px;
            color: var(--text-muted);
            margin-left: 18px;
        }

        /* Note Items */
        .note-item {
            border: 1px solid var(--border-color);
            border-radius: 6px;
            padding: 10px 12px;
            margin-bottom: 8px;
        }

        .note-item:hover {
            background: #fafafa;
        }

        .note-header {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 4px;
        }

        .note-title {
            font-weight: 600;
            font-size: 14px;
            flex: 1;
        }

        .note-content {
            font-size: 13px;
            color: var(--text-light);
            margin: 4px 0 4px 18px;
        }

        .note-content p { margin-bottom: 4px; }
        .note-content ul, .note-content ol {
            margin: 4px 0 4px 20px;
        }
        .note-content li { margin-bottom: 2px; }

        .note-meta {
            font-size: 11px;
            color: var(--text-muted);
            margin-left: 18px;
        }

        .pin-icon {
            font-size: 14px;
        }

        /* Priority Dots */
        .priority-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            display: inline-block;
            flex-shrink: 0;
        }

        .priority-critical { color: #f44336; }
        .priority-critical.priority-dot { background: #f44336; }
        .priority-high { color: #ff9800; }
        .priority-high.priority-dot { background: #ff9800; }
        .priority-medium { color: #ffc107; }
        .priority-medium.priority-dot { background: #ffc107; }
        .priority-low { color: #4caf50; }
        .priority-low.priority-dot { background: #4caf50; }

        /* Category Badges */
        .category-badge {
            font-size: 11px;
            padding: 2px 8px;
            border-radius: 4px;
            font-weight: 500;
            flex-shrink: 0;
        }

        .category-safety { background: #ffebee; color: #c62828; }
        .category-operations { background: #e3f2fd; color: #1565c0; }
        .category-equipment { background: #fff3e0; color: #e65100; }
        .category-personnel { background: #f3e5f5; color: #6a1b9a; }
        .category-handover { background: #e8f5e9; color: #2e7d32; }
        .category-general { background: #f5f5f5; color: #616161; }

        /* Status Badges */
        .status-badge {
            font-size: 10px;
            padding: 2px 6px;
            border-radius: 3px;
            font-weight: 600;
            text-transform: uppercase;
            flex-shrink: 0;
        }

        .status-completed .status-badge { background: #e8f5e9; color: #2e7d32; }
        .status-overdue .status-badge { background: #ffebee; color: #c62828; }
        .status-active .status-badge { background: #e3f2fd; color: #1565c0; }

        .overdue { color: #c62828; font-weight: 600; }

        .empty-message {
            color: var(--text-muted);
            font-style: italic;
            font-size: 13px;
            padding: 8px 0;
        }

        /* Footer */
        footer {
            text-align: center;
            padding: 24px;
            color: var(--text-muted);
            font-size: 12px;
        }

        /* Print Styles */
        @media print {
            header {
                position: static;
                background: white;
                color: var(--text-color);
                border-bottom: 2px solid var(--brand-color);
            }

            body { background: white; }

            .card {
                box-shadow: none;
                border: 1px solid var(--border-color);
                break-inside: avoid;
                page-break-inside: avoid;
            }

            .task-item, .note-item {
                break-inside: avoid;
                page-break-inside: avoid;
            }

            .pad-header {
                background: #f5f5f5 !important;
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }

            .metric-box, .category-badge, .status-badge, .priority-dot {
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
        }
        """
    }

    // MARK: - Helpers

    private func escapeHTML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
