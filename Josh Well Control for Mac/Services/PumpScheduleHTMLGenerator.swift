//
//  PumpScheduleHTMLGenerator.swift
//  Josh Well Control for Mac
//
//  Interactive HTML report generator for Pump Schedule simulation
//

import Foundation
import SwiftUI

/// Input data for generating a pump schedule HTML report
struct PumpScheduleReportData {
    let wellName: String
    let projectName: String
    let generatedDate: Date

    // Simulation parameters
    let bitMD: Double
    let controlMD: Double
    let pumpRate_m3permin: Double
    let mpdEnabled: Bool
    let targetEMD_kgm3: Double

    // Muds
    let activeMudName: String
    let activeMudDensity: Double

    // Stage data - snapshots at each progress point
    struct StageSnapshot {
        let stageName: String
        let stageIndex: Int
        let progress: Double  // 0.0 to 1.0
        let pumpedVolume_m3: Double
        let totalStageVolume_m3: Double
        let cumulativePumpedVolume_m3: Double

        // Hydraulics at this snapshot
        let ecd_kgm3: Double
        let bhp_kPa: Double
        let sbp_kPa: Double
        let tcp_kPa: Double
        let annulusFriction_kPa: Double
        let stringFriction_kPa: Double

        // Fluid positions (for visualization)
        struct FluidLayer {
            let topMD: Double
            let bottomMD: Double
            let mudName: String
            let density_kgm3: Double
            let colorHex: String
        }
        let stringLayers: [FluidLayer]
        let annulusLayers: [FluidLayer]
    }
    let snapshots: [StageSnapshot]

    // Stage definitions
    struct StageDef {
        let name: String
        let mudName: String
        let mudDensity: Double
        let volume_m3: Double
        let colorHex: String
    }
    let stages: [StageDef]

    // Geometry data
    let drillStringSections: [PDFSectionData]
    let annulusSections: [PDFSectionData]

    // Computed metrics
    var minECD: Double { snapshots.map { $0.ecd_kgm3 }.min() ?? 0 }
    var maxECD: Double { snapshots.map { $0.ecd_kgm3 }.max() ?? 0 }
    var maxBHP: Double { snapshots.map { $0.bhp_kPa }.max() ?? 0 }
    var maxTCP: Double { snapshots.map { $0.tcp_kPa }.max() ?? 0 }
    var totalPumpedVolume: Double { snapshots.last?.cumulativePumpedVolume_m3 ?? 0 }

    // Total geometry volumes
    var totalStringCapacity: Double { drillStringSections.reduce(0) { $0 + $1.totalVolume } }
    var totalStringDisplacement: Double {
        drillStringSections.reduce(0) { $0 + $1.displacement_m3_per_m * $1.length }
    }
    var totalAnnulusCapacity: Double { annulusSections.reduce(0) { $0 + $1.totalVolume } }
}

/// Cross-platform HTML generator for pump schedule reports
class PumpScheduleHTMLGenerator {
    static let shared = PumpScheduleHTMLGenerator()

    private init() {}

    func generateHTML(for data: PumpScheduleReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"
        let dateStr = dateFormatter.string(from: data.generatedDate)

        // Convert snapshots to JSON for JavaScript
        let snapshotsJSON = snapshotsToJSON(data.snapshots)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Pump Schedule Report - \(escapeHTML(data.wellName))</title>
            <style>
                \(generateCSS())
            </style>
        </head>
        <body>
            <header>
                <div class="header-content">
                    <h1>Pump Schedule Report</h1>
                    <span class="well-name">\(escapeHTML(data.wellName))</span>
                </div>
            </header>

            <main>
                <!-- Well Information -->
                <section class="card">
                    <h2>Well Information</h2>
                    <div class="info-grid">
                        <div class="info-item">
                            <span class="label">Well:</span>
                            <span class="value">\(escapeHTML(data.wellName))</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Project:</span>
                            <span class="value">\(escapeHTML(data.projectName))</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Date:</span>
                            <span class="value">\(dateStr)</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Active Mud:</span>
                            <span class="value">\(escapeHTML(data.activeMudName)) (\(String(format: "%.0f", data.activeMudDensity)) kg/m\u{00B3})</span>
                        </div>
                    </div>
                </section>

                <!-- Simulation Parameters -->
                <section class="card">
                    <h2>Simulation Parameters</h2>
                    <div class="params-grid">
                        <div class="param-item">
                            <span class="label">Bit MD:</span>
                            <span class="value">\(String(format: "%.0f m", data.bitMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Control MD:</span>
                            <span class="value">\(String(format: "%.0f m", data.controlMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Pump Rate:</span>
                            <span class="value">\(String(format: "%.2f m\u{00B3}/min", data.pumpRate_m3permin))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">MPD Enabled:</span>
                            <span class="value">\(data.mpdEnabled ? "Yes" : "No")</span>
                        </div>
                        \(data.mpdEnabled ? """
                        <div class="param-item">
                            <span class="label">Target EMD:</span>
                            <span class="value">\(String(format: "%.0f kg/m\u{00B3}", data.targetEMD_kgm3))</span>
                        </div>
                        """ : "")
                        <div class="param-item">
                            <span class="label">Total Stages:</span>
                            <span class="value">\(data.stages.count)</span>
                        </div>
                    </div>
                </section>

                <!-- Hydraulics Summary -->
                <section class="card">
                    <h2>Hydraulics Summary</h2>
                    <div class="metrics-grid">
                        <div class="metric-box">
                            <div class="metric-title">ECD Range</div>
                            <div class="metric-value">\(String(format: "%.0f - %.0f", data.minECD, data.maxECD))</div>
                            <div class="metric-unit">kg/m\u{00B3}</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Max BHP</div>
                            <div class="metric-value">\(String(format: "%.0f", data.maxBHP))</div>
                            <div class="metric-unit">kPa</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Max TCP</div>
                            <div class="metric-value">\(String(format: "%.0f", data.maxTCP))</div>
                            <div class="metric-unit">kPa</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Total Pumped</div>
                            <div class="metric-value">\(String(format: "%.1f", data.totalPumpedVolume))</div>
                            <div class="metric-unit">m\u{00B3}</div>
                        </div>
                    </div>
                </section>

                <!-- Final Spotted Fluids -->
                \(generateFinalSpottedFluidsSection(data))

                <!-- Interactive Wellbore Visualization -->
                <section class="card">
                    <h2>Interactive Well Snapshot</h2>
                    <div class="wellbore-controls">
                        <div class="slider-container">
                            <label for="progress-slider">Pump Progress:</label>
                            <input type="range" id="progress-slider" min="0" max="\(data.snapshots.count - 1)" value="0">
                            <span id="current-progress">--</span>
                        </div>
                        <div class="playback-controls">
                            <button id="play-btn" onclick="togglePlayback()">\u{25B6} Play</button>
                            <button onclick="resetPlayback()">\u{21BA} Reset</button>
                            <select id="speed-select">
                                <option value="500">Slow</option>
                                <option value="200" selected>Normal</option>
                                <option value="50">Fast</option>
                            </select>
                        </div>
                    </div>
                    <div class="wellbore-display">
                        <div class="well-columns-container">
                            <div class="well-column">
                                <div class="column-header">Annulus</div>
                                <canvas id="annulus-left" width="80" height="400"></canvas>
                            </div>
                            <div class="well-column string-column">
                                <div class="column-header">String</div>
                                <canvas id="string-canvas" width="80" height="400"></canvas>
                            </div>
                            <div class="well-column">
                                <div class="column-header">Annulus</div>
                                <canvas id="annulus-right" width="80" height="400"></canvas>
                            </div>
                        </div>
                    </div>
                    <div class="step-info" id="step-info">
                        <div class="info-row"><span>Stage:</span> <span id="info-stage">--</span></div>
                        <div class="info-row"><span>Progress:</span> <span id="info-progress">--</span></div>
                        <div class="info-row"><span>Pumped:</span> <span id="info-pumped">--</span></div>
                        <div class="info-row"><span>ECD:</span> <span id="info-ecd">--</span></div>
                        <div class="info-row"><span>BHP:</span> <span id="info-bhp">--</span></div>
                        <div class="info-row"><span>TCP:</span> <span id="info-tcp">--</span></div>
                    </div>
                </section>

                <!-- Charts -->
                <section class="card">
                    <h2>Hydraulics Charts</h2>
                    <p class="chart-hint">Use the slider above to see values at each point</p>
                    <div class="charts-grid">
                        <div class="chart-container" id="container-ecd">
                            <canvas id="chart-ecd" width="280" height="180"></canvas>
                            <div class="chart-tooltip" id="tooltip-ecd"></div>
                        </div>
                        <div class="chart-container" id="container-bhp">
                            <canvas id="chart-bhp" width="280" height="180"></canvas>
                            <div class="chart-tooltip" id="tooltip-bhp"></div>
                        </div>
                        <div class="chart-container" id="container-tcp">
                            <canvas id="chart-tcp" width="280" height="180"></canvas>
                            <div class="chart-tooltip" id="tooltip-tcp"></div>
                        </div>
                        <div class="chart-container" id="container-friction">
                            <canvas id="chart-friction" width="280" height="180"></canvas>
                            <div class="chart-tooltip" id="tooltip-friction"></div>
                        </div>
                    </div>
                </section>

                <!-- Pump Stages -->
                <section class="card">
                    <h2>Pump Stages</h2>
                    \(generateStagesTable(data.stages))
                </section>

                <!-- Geometry Tables -->
                <section class="card">
                    <h2>Well Geometry</h2>
                    <h3>Drill String</h3>
                    \(generateDrillStringTable(data.drillStringSections, totalCapacity: data.totalStringCapacity, totalDisplacement: data.totalStringDisplacement))

                    <h3>Annulus</h3>
                    \(generateAnnulusTable(data.annulusSections, totalCapacity: data.totalAnnulusCapacity))
                </section>

                <!-- Data Table -->
                <section class="card">
                    <h2>Step-by-Step Data</h2>
                    <div class="table-controls">
                        <input type="text" id="table-search" placeholder="Search..." onkeyup="filterTable()">
                        <button onclick="exportTableCSV()">Export CSV</button>
                    </div>
                    <div class="table-wrapper">
                        <table id="data-table">
                            <thead>
                                <tr>
                                    <th onclick="sortTable(0)">Stage \u{21C5}</th>
                                    <th onclick="sortTable(1)">Progress \u{21C5}</th>
                                    <th onclick="sortTable(2)">Pumped (m\u{00B3}) \u{21C5}</th>
                                    <th onclick="sortTable(3)">Cumulative (m\u{00B3}) \u{21C5}</th>
                                    <th onclick="sortTable(4)">ECD (kg/m\u{00B3}) \u{21C5}</th>
                                    <th onclick="sortTable(5)">BHP (kPa) \u{21C5}</th>
                                    <th onclick="sortTable(6)">SBP (kPa) \u{21C5}</th>
                                    <th onclick="sortTable(7)">TCP (kPa) \u{21C5}</th>
                                    <th onclick="sortTable(8)">Ann Friction (kPa) \u{21C5}</th>
                                    <th onclick="sortTable(9)">Str Friction (kPa) \u{21C5}</th>
                                </tr>
                            </thead>
                            <tbody>
                                \(generateTableRows(data.snapshots))
                            </tbody>
                        </table>
                    </div>
                </section>
            </main>

            <footer>
                <p>Generated by Josh Well Control \u{2022} \(dateStr)</p>
            </footer>

            <script>
                // Simulation data
                const snapshots = \(snapshotsJSON);
                const maxDepth = \(String(format: "%.1f", data.bitMD));

                // Playback state
                let isPlaying = false;
                let playbackInterval = null;
                let currentIndex = 0;

                \(generateJavaScript())
            </script>
        </body>
        </html>
        """
    }

    // MARK: - CSS Generation

    private func generateCSS() -> String {
        return """
        :root {
            --brand-color: #9c27b0;
            --safe-color: #4caf50;
            --warning-color: #ff9800;
            --danger-color: #f44336;
            --bg-color: #f5f5f5;
            --card-bg: #ffffff;
            --text-color: #333333;
            --text-light: #666666;
            --border-color: #e0e0e0;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg-color);
            color: var(--text-color);
            line-height: 1.5;
        }

        header {
            background: var(--brand-color);
            color: white;
            padding: 16px 24px;
            position: sticky;
            top: 0;
            z-index: 100;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        .header-content {
            max-width: 1200px;
            margin: 0 auto;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        header h1 {
            font-size: 1.5rem;
            font-weight: 600;
        }

        .well-name {
            opacity: 0.9;
            font-size: 0.9rem;
        }

        main {
            max-width: 1200px;
            margin: 0 auto;
            padding: 24px;
        }

        .card {
            background: var(--card-bg);
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }

        .card h2 {
            color: var(--brand-color);
            font-size: 1.1rem;
            margin-bottom: 16px;
            padding-bottom: 8px;
            border-bottom: 1px solid var(--border-color);
        }

        .card h3 {
            color: var(--text-color);
            font-size: 0.95rem;
            margin: 16px 0 12px 0;
        }

        .info-grid, .params-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 12px;
        }

        .info-item, .param-item {
            display: flex;
            gap: 8px;
        }

        .label {
            color: var(--text-light);
            font-size: 0.85rem;
        }

        .value {
            font-weight: 500;
        }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
            gap: 12px;
        }

        .metric-box {
            background: var(--bg-color);
            border-radius: 6px;
            padding: 12px;
            text-align: center;
        }

        .metric-title {
            font-size: 0.75rem;
            color: var(--text-light);
            margin-bottom: 4px;
        }

        .metric-value {
            font-size: 1.3rem;
            font-weight: 700;
            color: var(--brand-color);
        }

        .metric-unit {
            font-size: 0.7rem;
            color: var(--text-light);
        }

        /* Final Spotted Fluids */
        .fluids-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 24px;
        }

        @media (max-width: 768px) {
            .fluids-grid {
                grid-template-columns: 1fr;
            }
        }

        .fluids-column h3 {
            font-size: 0.8rem;
            color: var(--text-light);
            margin-bottom: 12px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .fluid-layer {
            display: flex;
            align-items: flex-start;
            padding: 10px 0;
            border-bottom: 1px solid var(--border-color);
        }

        .fluid-layer:last-child {
            border-bottom: none;
        }

        .fluid-swatch {
            width: 16px;
            height: 40px;
            border-radius: 3px;
            margin-right: 12px;
            flex-shrink: 0;
            border: 1px solid rgba(0,0,0,0.15);
        }

        .fluid-info {
            flex: 1;
            min-width: 0;
        }

        .fluid-name {
            font-weight: 600;
            font-size: 0.9rem;
            margin-bottom: 2px;
        }

        .fluid-details {
            font-size: 0.75rem;
            color: var(--text-light);
        }

        .fluid-metrics {
            text-align: right;
            flex-shrink: 0;
        }

        .fluid-volume {
            font-weight: 600;
            font-size: 0.95rem;
        }

        .fluid-capacity {
            font-size: 0.7rem;
            color: var(--text-light);
        }

        /* Wellbore Visualization */
        .wellbore-controls {
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 12px;
            margin-bottom: 16px;
            padding: 12px;
            background: var(--bg-color);
            border-radius: 6px;
        }

        .slider-container {
            display: flex;
            align-items: center;
            gap: 12px;
            flex: 1;
        }

        .slider-container input[type="range"] {
            flex: 1;
            min-width: 200px;
        }

        #current-progress {
            font-weight: 600;
            min-width: 120px;
        }

        .playback-controls {
            display: flex;
            gap: 8px;
        }

        .playback-controls button, .playback-controls select {
            padding: 6px 12px;
            border: 1px solid var(--border-color);
            border-radius: 4px;
            background: white;
            cursor: pointer;
            font-size: 0.85rem;
        }

        .playback-controls button:hover {
            background: var(--bg-color);
        }

        .wellbore-display {
            position: relative;
            padding: 20px;
            background: #1a1a1a;
            border-radius: 6px;
        }

        .well-columns-container {
            display: flex;
            justify-content: center;
            gap: 4px;
        }

        .well-column {
            display: flex;
            flex-direction: column;
            align-items: center;
        }

        .column-header {
            color: rgba(255,255,255,0.7);
            font-size: 0.75rem;
            margin-bottom: 8px;
        }

        .well-column canvas {
            border: 1px solid #333;
        }

        .step-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 8px;
            margin-top: 16px;
            padding: 12px;
            background: var(--bg-color);
            border-radius: 6px;
        }

        .info-row {
            display: flex;
            justify-content: space-between;
            font-size: 0.85rem;
        }

        .info-row span:first-child {
            color: var(--text-light);
        }

        .info-row span:last-child {
            font-weight: 600;
        }

        /* Charts */
        .charts-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 16px;
        }

        @media (max-width: 768px) {
            .charts-grid {
                grid-template-columns: 1fr;
            }
        }

        .chart-container {
            background: var(--bg-color);
            border-radius: 6px;
            padding: 12px;
            height: 250px;
            position: relative;
        }

        .chart-container canvas {
            width: 100% !important;
            height: 100% !important;
        }

        .chart-tooltip {
            position: absolute;
            background: rgba(0, 0, 0, 0.85);
            color: white;
            padding: 8px 12px;
            border-radius: 4px;
            font-size: 0.75rem;
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.15s;
            z-index: 100;
            white-space: nowrap;
        }

        .chart-tooltip.visible {
            opacity: 1;
        }

        .chart-hint {
            font-size: 0.75rem;
            color: var(--text-light);
            margin-bottom: 12px;
            font-style: italic;
        }

        /* Tables */
        .table-controls {
            display: flex;
            gap: 12px;
            margin-bottom: 12px;
        }

        .table-controls input {
            flex: 1;
            padding: 8px 12px;
            border: 1px solid var(--border-color);
            border-radius: 4px;
            font-size: 0.9rem;
        }

        .table-controls button {
            padding: 8px 16px;
            background: var(--brand-color);
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.85rem;
        }

        .table-wrapper {
            overflow-x: auto;
            max-height: 500px;
            overflow-y: auto;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.8rem;
        }

        thead {
            position: sticky;
            top: 0;
            z-index: 10;
        }

        th {
            background: var(--brand-color);
            color: white;
            padding: 10px 8px;
            text-align: right;
            cursor: pointer;
            white-space: nowrap;
        }

        th:first-child {
            text-align: left;
        }

        th:hover {
            background: #8e24aa;
        }

        td {
            padding: 8px;
            text-align: right;
            border-bottom: 1px solid var(--border-color);
        }

        td:first-child {
            text-align: left;
        }

        tr:nth-child(even) {
            background: var(--bg-color);
        }

        tr:hover {
            background: #f3e5f5;
        }

        tr.highlight {
            background: #e1bee7 !important;
        }

        /* Geometry Tables */
        .geometry-table {
            font-size: 0.8rem;
            margin-bottom: 12px;
        }

        .geometry-table th {
            font-size: 0.75rem;
            padding: 8px 6px;
        }

        .geometry-table td {
            padding: 6px;
        }

        .geometry-table td:first-child {
            text-align: left;
        }

        .total-row {
            background: #e0e0e0 !important;
            font-weight: 600;
        }

        /* Stages table */
        .stages-table .color-swatch {
            width: 20px;
            height: 20px;
            border-radius: 4px;
            display: inline-block;
            vertical-align: middle;
            margin-right: 8px;
            border: 1px solid #ccc;
        }

        footer {
            text-align: center;
            padding: 20px;
            color: var(--text-light);
            font-size: 0.8rem;
        }

        @media print {
            header {
                position: static;
            }
            .wellbore-controls, .playback-controls, .table-controls {
                display: none;
            }
            .card {
                break-inside: avoid;
            }
        }
        """
    }

    // MARK: - JavaScript Generation

    private func generateJavaScript() -> String {
        return """
        // Initialize on load
        document.addEventListener('DOMContentLoaded', function() {
            if (snapshots.length > 0) {
                initSlider();
                requestAnimationFrame(function() {
                    initCharts();
                    updateWellbore(0);
                    updateChartMarker(0);
                });
            }
        });

        // Slider functionality
        function initSlider() {
            const slider = document.getElementById('progress-slider');
            slider.addEventListener('input', function() {
                currentIndex = parseInt(this.value);
                updateWellbore(currentIndex);
                highlightTableRow(currentIndex);
            });
        }

        function updateWellbore(index) {
            if (index < 0 || index >= snapshots.length) return;
            const snap = snapshots[index];

            // Update info display
            document.getElementById('current-progress').textContent = snap.stageName + ' - ' + (snap.progress * 100).toFixed(0) + '%';
            document.getElementById('info-stage').textContent = snap.stageName;
            document.getElementById('info-progress').textContent = (snap.progress * 100).toFixed(0) + '%';
            document.getElementById('info-pumped').textContent = snap.cumulativePumped.toFixed(2) + ' m\\u00B3';
            document.getElementById('info-ecd').textContent = snap.ecd.toFixed(0) + ' kg/m\\u00B3';
            document.getElementById('info-bhp').textContent = snap.bhp.toFixed(0) + ' kPa';
            document.getElementById('info-tcp').textContent = snap.tcp.toFixed(0) + ' kPa';

            // Draw wellbore canvases
            drawWellboreColumn('annulus-left', snap.annulusLayers);
            drawWellboreColumn('string-canvas', snap.stringLayers);
            drawWellboreColumn('annulus-right', snap.annulusLayers);

            // Update chart marker
            updateChartMarker(index);
        }

        function drawWellboreColumn(canvasId, layers) {
            const canvas = document.getElementById(canvasId);
            if (!canvas) return;
            const ctx = canvas.getContext('2d');
            if (!ctx) return;
            const h = canvas.height;
            const w = canvas.width;

            // Clear and fill background
            ctx.fillStyle = '#2a2a2a';
            ctx.fillRect(0, 0, w, h);

            // Draw layers
            layers.forEach(layer => {
                const y1 = (layer.topMD / maxDepth) * h;
                const y2 = (layer.bottomMD / maxDepth) * h;
                const layerH = Math.max(1, y2 - y1);

                ctx.fillStyle = layer.color;
                ctx.fillRect(0, y1, w, layerH);
            });

            // Draw depth scale
            ctx.font = '9px -apple-system, sans-serif';
            ctx.fillStyle = 'rgba(255, 255, 255, 0.7)';
            ctx.textAlign = 'right';
            for (let i = 0; i <= 5; i++) {
                const depth = (i / 5) * maxDepth;
                const y = (i / 5) * h;
                ctx.fillText(depth.toFixed(0), w - 2, y + 10);
            }
        }

        // Playback controls
        function togglePlayback() {
            const btn = document.getElementById('play-btn');
            if (isPlaying) {
                clearInterval(playbackInterval);
                btn.textContent = '\\u25B6 Play';
                isPlaying = false;
            } else {
                const speed = parseInt(document.getElementById('speed-select').value);
                playbackInterval = setInterval(() => {
                    currentIndex++;
                    if (currentIndex >= snapshots.length) {
                        currentIndex = 0;
                    }
                    document.getElementById('progress-slider').value = currentIndex;
                    updateWellbore(currentIndex);
                    highlightTableRow(currentIndex);
                }, speed);
                btn.textContent = '\\u23F8 Pause';
                isPlaying = true;
            }
        }

        function resetPlayback() {
            if (isPlaying) togglePlayback();
            currentIndex = 0;
            document.getElementById('progress-slider').value = 0;
            updateWellbore(0);
            highlightTableRow(0);
        }

        // Charts
        let charts = {};

        function initCharts() {
            const cumVolumes = snapshots.map(s => s.cumulativePumped);
            const ecds = snapshots.map(s => s.ecd);
            const bhps = snapshots.map(s => s.bhp);
            const tcps = snapshots.map(s => s.tcp);
            const annFrictions = snapshots.map(s => s.annulusFriction);
            const strFrictions = snapshots.map(s => s.stringFriction);

            charts.ecd = createChart('chart-ecd', 'ECD vs Volume Pumped', cumVolumes, [
                { data: ecds, label: 'ECD (kg/m\\u00B3)', color: '#9c27b0' }
            ]);

            charts.bhp = createChart('chart-bhp', 'BHP vs Volume Pumped', cumVolumes, [
                { data: bhps, label: 'BHP (kPa)', color: '#2196f3' }
            ]);

            charts.tcp = createChart('chart-tcp', 'TCP vs Volume Pumped', cumVolumes, [
                { data: tcps, label: 'TCP (kPa)', color: '#ff9800' }
            ]);

            charts.friction = createChart('chart-friction', 'Friction vs Volume Pumped', cumVolumes, [
                { data: annFrictions, label: 'Annulus (kPa)', color: '#4caf50' },
                { data: strFrictions, label: 'String (kPa)', color: '#f44336' }
            ]);
        }

        function createChart(canvasId, title, xData, datasets) {
            const canvas = document.getElementById(canvasId);
            if (!canvas) return null;
            const ctx = canvas.getContext('2d');
            if (!ctx) return null;

            const tooltip = document.getElementById('tooltip-' + canvasId.replace('chart-', ''));

            const rect = canvas.parentElement ? canvas.parentElement.getBoundingClientRect() : { width: 280, height: 180 };
            if (rect.width > 50 && rect.height > 50) {
                canvas.width = rect.width - 24;
                canvas.height = rect.height - 24;
            }

            const w = canvas.width;
            const h = canvas.height;
            const margin = { top: 30, right: 20, bottom: 30, left: 50 };
            const plotW = w - margin.left - margin.right;
            const plotH = h - margin.top - margin.bottom;

            const xMin = Math.min(...xData);
            const xMax = Math.max(...xData);
            let yMin = Infinity, yMax = -Infinity;
            datasets.forEach(ds => {
                yMin = Math.min(yMin, ...ds.data);
                yMax = Math.max(yMax, ...ds.data);
            });
            const yPad = (yMax - yMin) * 0.1 || 1;
            yMin -= yPad;
            yMax += yPad;

            function draw(highlightIndex = -1) {
                ctx.clearRect(0, 0, w, h);

                // Background
                ctx.fillStyle = '#f5f5f5';
                ctx.fillRect(0, 0, w, h);

                // Title
                ctx.fillStyle = '#666';
                ctx.font = '12px -apple-system, sans-serif';
                ctx.textAlign = 'center';
                ctx.fillText(title, w / 2, 18);

                // Grid
                ctx.strokeStyle = '#ddd';
                ctx.lineWidth = 0.5;
                for (let i = 0; i <= 4; i++) {
                    const y = margin.top + (plotH * i / 4);
                    ctx.beginPath();
                    ctx.moveTo(margin.left, y);
                    ctx.lineTo(w - margin.right, y);
                    ctx.stroke();
                }

                // Axes
                ctx.strokeStyle = '#999';
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(margin.left, margin.top);
                ctx.lineTo(margin.left, h - margin.bottom);
                ctx.lineTo(w - margin.right, h - margin.bottom);
                ctx.stroke();

                // Y labels
                ctx.fillStyle = '#666';
                ctx.font = '9px -apple-system, sans-serif';
                ctx.textAlign = 'right';
                for (let i = 0; i <= 4; i++) {
                    const val = yMin + (yMax - yMin) * (1 - i / 4);
                    const y = margin.top + (plotH * i / 4);
                    ctx.fillText(val.toFixed(val >= 100 ? 0 : 1), margin.left - 5, y + 3);
                }

                // X labels
                ctx.textAlign = 'center';
                for (let i = 0; i <= 4; i++) {
                    const val = xMin + (xMax - xMin) * i / 4;
                    const x = margin.left + (plotW * i / 4);
                    ctx.fillText(val.toFixed(1), x, h - margin.bottom + 15);
                }

                // Data lines
                datasets.forEach(ds => {
                    ctx.strokeStyle = ds.color;
                    ctx.lineWidth = 1.5;
                    ctx.beginPath();
                    xData.forEach((x, i) => {
                        const px = margin.left + ((x - xMin) / (xMax - xMin || 1)) * plotW;
                        const py = margin.top + ((yMax - ds.data[i]) / (yMax - yMin || 1)) * plotH;
                        if (i === 0) ctx.moveTo(px, py);
                        else ctx.lineTo(px, py);
                    });
                    ctx.stroke();
                });

                // Highlight marker
                if (highlightIndex >= 0 && highlightIndex < xData.length) {
                    const x = xData[highlightIndex];
                    const px = margin.left + ((x - xMin) / (xMax - xMin || 1)) * plotW;
                    ctx.strokeStyle = '#f44336';
                    ctx.lineWidth = 1;
                    ctx.setLineDash([4, 4]);
                    ctx.beginPath();
                    ctx.moveTo(px, margin.top);
                    ctx.lineTo(px, h - margin.bottom);
                    ctx.stroke();
                    ctx.setLineDash([]);

                    datasets.forEach(ds => {
                        const py = margin.top + ((yMax - ds.data[highlightIndex]) / (yMax - yMin || 1)) * plotH;
                        ctx.fillStyle = ds.color;
                        ctx.beginPath();
                        ctx.arc(px, py, 4, 0, Math.PI * 2);
                        ctx.fill();
                    });
                }

                // Legend
                let legendX = margin.left;
                datasets.forEach(ds => {
                    ctx.fillStyle = ds.color;
                    ctx.fillRect(legendX, margin.top - 15, 12, 3);
                    ctx.fillStyle = '#666';
                    ctx.font = '8px -apple-system, sans-serif';
                    ctx.textAlign = 'left';
                    ctx.fillText(ds.label, legendX + 15, margin.top - 12);
                    legendX += ds.label.length * 5 + 30;
                });
            }

            function updateTooltip(idx) {
                if (!tooltip || idx < 0 || idx >= xData.length) {
                    if (tooltip) tooltip.classList.remove('visible');
                    return;
                }

                const x = xData[idx];
                let html = '<div style="font-weight:600;margin-bottom:4px;">Vol: ' + x.toFixed(2) + ' m\\u00B3</div>';
                datasets.forEach(ds => {
                    const val = ds.data[idx];
                    html += '<div style="color:' + ds.color + '">' + ds.label + ': ' + val.toFixed(val >= 100 ? 0 : 2) + '</div>';
                });
                tooltip.innerHTML = html;
                tooltip.style.right = '8px';
                tooltip.style.top = '8px';
                tooltip.style.left = 'auto';
                tooltip.classList.add('visible');
            }

            draw();
            return { draw, updateTooltip };
        }

        function updateChartMarker(index) {
            Object.values(charts).forEach(chart => {
                if (chart && chart.draw) {
                    chart.draw(index);
                    if (chart.updateTooltip) chart.updateTooltip(index);
                }
            });
        }

        // Table functionality
        function highlightTableRow(index) {
            const rows = document.querySelectorAll('#data-table tbody tr');
            rows.forEach((row, i) => {
                row.classList.toggle('highlight', i === index);
            });
        }

        let sortDirection = {};
        function sortTable(columnIndex) {
            const table = document.getElementById('data-table');
            const tbody = table.querySelector('tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));

            sortDirection[columnIndex] = !sortDirection[columnIndex];
            const dir = sortDirection[columnIndex] ? 1 : -1;

            rows.sort((a, b) => {
                const aVal = parseFloat(a.cells[columnIndex].textContent) || a.cells[columnIndex].textContent;
                const bVal = parseFloat(b.cells[columnIndex].textContent) || b.cells[columnIndex].textContent;
                if (typeof aVal === 'number' && typeof bVal === 'number') {
                    return (aVal - bVal) * dir;
                }
                return String(aVal).localeCompare(String(bVal)) * dir;
            });

            rows.forEach(row => tbody.appendChild(row));
        }

        function filterTable() {
            const filter = document.getElementById('table-search').value.toLowerCase();
            const rows = document.querySelectorAll('#data-table tbody tr');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(filter) ? '' : 'none';
            });
        }

        function exportTableCSV() {
            const table = document.getElementById('data-table');
            let csv = [];
            const headers = Array.from(table.querySelectorAll('th')).map(th => th.textContent.replace(' \\u21C5', ''));
            csv.push(headers.join(','));

            table.querySelectorAll('tbody tr').forEach(row => {
                const cols = Array.from(row.querySelectorAll('td')).map(td => td.textContent);
                csv.push(cols.join(','));
            });

            const blob = new Blob([csv.join('\\n')], { type: 'text/csv' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'pump_schedule_data.csv';
            a.click();
            URL.revokeObjectURL(url);
        }
        """
    }

    // MARK: - HTML Helpers

    private func escapeHTML(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func snapshotsToJSON(_ snapshots: [PumpScheduleReportData.StageSnapshot]) -> String {
        var json = "["
        for (i, snap) in snapshots.enumerated() {
            if i > 0 { json += "," }
            json += """
            {
                "stageName": "\(escapeHTML(snap.stageName))",
                "stageIndex": \(snap.stageIndex),
                "progress": \(snap.progress),
                "pumpedVolume": \(snap.pumpedVolume_m3),
                "cumulativePumped": \(snap.cumulativePumpedVolume_m3),
                "ecd": \(snap.ecd_kgm3),
                "bhp": \(snap.bhp_kPa),
                "sbp": \(snap.sbp_kPa),
                "tcp": \(snap.tcp_kPa),
                "annulusFriction": \(snap.annulusFriction_kPa),
                "stringFriction": \(snap.stringFriction_kPa),
                "stringLayers": \(layersToJSON(snap.stringLayers)),
                "annulusLayers": \(layersToJSON(snap.annulusLayers))
            }
            """
        }
        json += "]"
        return json
    }

    private func layersToJSON(_ layers: [PumpScheduleReportData.StageSnapshot.FluidLayer]) -> String {
        var json = "["
        for (i, layer) in layers.enumerated() {
            if i > 0 { json += "," }
            json += """
            {"topMD": \(layer.topMD), "bottomMD": \(layer.bottomMD), "mudName": "\(escapeHTML(layer.mudName))", "density": \(layer.density_kgm3), "color": "\(layer.colorHex)"}
            """
        }
        json += "]"
        return json
    }

    private func generateStagesTable(_ stages: [PumpScheduleReportData.StageDef]) -> String {
        var html = """
        <table class="geometry-table stages-table">
            <thead>
                <tr>
                    <th>#</th>
                    <th>Stage Name</th>
                    <th>Mud</th>
                    <th>Density (kg/m\u{00B3})</th>
                    <th>Volume (m\u{00B3})</th>
                </tr>
            </thead>
            <tbody>
        """

        var totalVolume: Double = 0
        for (i, stage) in stages.enumerated() {
            totalVolume += stage.volume_m3
            html += """
            <tr>
                <td>\(i + 1)</td>
                <td><span class="color-swatch" style="background-color: \(stage.colorHex);"></span>\(escapeHTML(stage.name))</td>
                <td>\(escapeHTML(stage.mudName))</td>
                <td>\(String(format: "%.0f", stage.mudDensity))</td>
                <td>\(String(format: "%.2f", stage.volume_m3))</td>
            </tr>
            """
        }

        html += """
            <tr class="total-row">
                <td colspan="4">TOTAL</td>
                <td>\(String(format: "%.2f", totalVolume))</td>
            </tr>
            </tbody>
        </table>
        """

        return html
    }

    private func generateTableRows(_ snapshots: [PumpScheduleReportData.StageSnapshot]) -> String {
        var html = ""
        for snap in snapshots {
            html += """
            <tr>
                <td>\(escapeHTML(snap.stageName))</td>
                <td>\(String(format: "%.0f%%", snap.progress * 100))</td>
                <td>\(String(format: "%.3f", snap.pumpedVolume_m3))</td>
                <td>\(String(format: "%.3f", snap.cumulativePumpedVolume_m3))</td>
                <td>\(String(format: "%.0f", snap.ecd_kgm3))</td>
                <td>\(String(format: "%.0f", snap.bhp_kPa))</td>
                <td>\(String(format: "%.0f", snap.sbp_kPa))</td>
                <td>\(String(format: "%.0f", snap.tcp_kPa))</td>
                <td>\(String(format: "%.1f", snap.annulusFriction_kPa))</td>
                <td>\(String(format: "%.1f", snap.stringFriction_kPa))</td>
            </tr>
            """
        }
        return html
    }

    private func generateFinalSpottedFluidsSection(_ data: PumpScheduleReportData) -> String {
        // Get the final snapshot layers
        guard let finalSnapshot = data.snapshots.last else {
            return ""
        }

        let stringLayers = finalSnapshot.stringLayers
        let annulusLayers = finalSnapshot.annulusLayers

        // Calculate total volumes for each side
        var totalStringVolume: Double = 0
        var totalAnnulusVolume: Double = 0

        func layerVolume(layer: PumpScheduleReportData.StageSnapshot.FluidLayer, sections: [PDFSectionData]) -> (volume: Double, avgCapacity: Double) {
            var vol: Double = 0
            var totalLen: Double = 0
            for section in sections {
                let overlapTop = max(layer.topMD, section.topMD)
                let overlapBot = min(layer.bottomMD, section.bottomMD)
                if overlapBot > overlapTop {
                    let len = overlapBot - overlapTop
                    vol += len * section.capacity_m3_per_m
                    totalLen += len
                }
            }
            let avgCap = totalLen > 0 ? vol / totalLen : 0
            return (vol, avgCap)
        }

        var stringHTML = ""
        for layer in stringLayers {
            let (vol, avgCap) = layerVolume(layer: layer, sections: data.drillStringSections)
            totalStringVolume += vol
            stringHTML += """
            <div class="fluid-layer">
                <div class="fluid-swatch" style="background-color: \(layer.colorHex);"></div>
                <div class="fluid-info">
                    <div class="fluid-name">\(escapeHTML(layer.mudName))</div>
                    <div class="fluid-details">\(String(format: "%.0f", layer.topMD))–\(String(format: "%.0f", layer.bottomMD)) m  •  ρ=\(String(format: "%.0f", layer.density_kgm3)) kg/m³</div>
                </div>
                <div class="fluid-metrics">
                    <div class="fluid-volume">\(String(format: "%.5f", vol)) m³</div>
                    <div class="fluid-capacity">\(String(format: "%.5f", avgCap)) m³/m</div>
                </div>
            </div>
            """
        }

        var annulusHTML = ""
        for layer in annulusLayers {
            let (vol, avgCap) = layerVolume(layer: layer, sections: data.annulusSections)
            totalAnnulusVolume += vol
            annulusHTML += """
            <div class="fluid-layer">
                <div class="fluid-swatch" style="background-color: \(layer.colorHex);"></div>
                <div class="fluid-info">
                    <div class="fluid-name">\(escapeHTML(layer.mudName))</div>
                    <div class="fluid-details">\(String(format: "%.0f", layer.topMD))–\(String(format: "%.0f", layer.bottomMD)) m  •  ρ=\(String(format: "%.0f", layer.density_kgm3)) kg/m³</div>
                </div>
                <div class="fluid-metrics">
                    <div class="fluid-volume">\(String(format: "%.5f", vol)) m³</div>
                    <div class="fluid-capacity">\(String(format: "%.5f", avgCap)) m³/m</div>
                </div>
            </div>
            """
        }

        return """
        <section class="card">
            <h2>Final Spotted Fluids</h2>
            <div class="fluids-grid">
                <div class="fluids-column">
                    <h3>String layers</h3>
                    \(stringHTML)
                    <div class="fluid-layer" style="background: var(--bg-color); border-radius: 4px; padding: 8px 0; margin-top: 8px;">
                        <div class="fluid-info">
                            <div class="fluid-name" style="color: var(--text-light);">Total String Volume</div>
                        </div>
                        <div class="fluid-metrics">
                            <div class="fluid-volume">\(String(format: "%.5f", totalStringVolume)) m³</div>
                        </div>
                    </div>
                </div>
                <div class="fluids-column">
                    <h3>Annulus layers</h3>
                    \(annulusHTML)
                    <div class="fluid-layer" style="background: var(--bg-color); border-radius: 4px; padding: 8px 0; margin-top: 8px;">
                        <div class="fluid-info">
                            <div class="fluid-name" style="color: var(--text-light);">Total Annulus Volume</div>
                        </div>
                        <div class="fluid-metrics">
                            <div class="fluid-volume">\(String(format: "%.5f", totalAnnulusVolume)) m³</div>
                        </div>
                    </div>
                </div>
            </div>
        </section>
        """
    }

    private func generateDrillStringTable(_ sections: [PDFSectionData], totalCapacity: Double, totalDisplacement: Double) -> String {
        guard !sections.isEmpty else {
            return "<p>No drill string sections defined</p>"
        }

        var html = """
        <table class="geometry-table">
            <thead>
                <tr>
                    <th>Section</th>
                    <th>Top (m)</th>
                    <th>Bot (m)</th>
                    <th>OD (mm)</th>
                    <th>ID (mm)</th>
                    <th>Cap (m\u{00B3}/m)</th>
                    <th>Disp (m\u{00B3}/m)</th>
                    <th>Vol (m\u{00B3})</th>
                </tr>
            </thead>
            <tbody>
        """

        for section in sections {
            html += """
            <tr>
                <td>\(escapeHTML(section.name))</td>
                <td>\(String(format: "%.0f", section.topMD))</td>
                <td>\(String(format: "%.0f", section.bottomMD))</td>
                <td>\(String(format: "%.1f", section.outerDiameter * 1000))</td>
                <td>\(String(format: "%.1f", section.innerDiameter * 1000))</td>
                <td>\(String(format: "%.4f", section.capacity_m3_per_m))</td>
                <td>\(String(format: "%.4f", section.displacement_m3_per_m))</td>
                <td>\(String(format: "%.2f", section.totalVolume))</td>
            </tr>
            """
        }

        html += """
            <tr class="total-row">
                <td>TOTAL</td>
                <td colspan="6"></td>
                <td>\(String(format: "%.2f", totalCapacity))</td>
            </tr>
            <tr class="total-row">
                <td>DISPLACEMENT</td>
                <td colspan="6"></td>
                <td>\(String(format: "%.2f", totalDisplacement))</td>
            </tr>
            </tbody>
        </table>
        """

        return html
    }

    private func generateAnnulusTable(_ sections: [PDFSectionData], totalCapacity: Double) -> String {
        guard !sections.isEmpty else {
            return "<p>No annulus sections defined</p>"
        }

        var html = """
        <table class="geometry-table">
            <thead>
                <tr>
                    <th>Section</th>
                    <th>Top (m)</th>
                    <th>Bot (m)</th>
                    <th>Hole ID (mm)</th>
                    <th>Pipe OD (mm)</th>
                    <th>Cap (m\u{00B3}/m)</th>
                    <th>Vol (m\u{00B3})</th>
                </tr>
            </thead>
            <tbody>
        """

        for section in sections {
            html += """
            <tr>
                <td>\(escapeHTML(section.name))</td>
                <td>\(String(format: "%.0f", section.topMD))</td>
                <td>\(String(format: "%.0f", section.bottomMD))</td>
                <td>\(String(format: "%.1f", section.innerDiameter * 1000))</td>
                <td>\(String(format: "%.1f", section.outerDiameter * 1000))</td>
                <td>\(String(format: "%.4f", section.capacity_m3_per_m))</td>
                <td>\(String(format: "%.2f", section.totalVolume))</td>
            </tr>
            """
        }

        html += """
            <tr class="total-row">
                <td>TOTAL</td>
                <td colspan="5"></td>
                <td>\(String(format: "%.2f", totalCapacity))</td>
            </tr>
            </tbody>
        </table>
        """

        return html
    }
}
