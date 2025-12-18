//
//  TripSimulationHTMLGenerator.swift
//  Josh Well Control for Mac
//
//  Interactive HTML report generator for Trip Simulation
//

import Foundation

/// Cross-platform HTML generator for trip simulation reports
class TripSimulationHTMLGenerator {
    static let shared = TripSimulationHTMLGenerator()

    private init() {}

    func generateHTML(for data: TripSimulationReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"
        let dateStr = dateFormatter.string(from: data.generatedDate)

        let direction = data.startMD > data.endMD ? "POOH (Pull Out Of Hole)" : "RIH (Run In Hole)"

        // Convert steps to JSON for JavaScript
        let stepsJSON = stepsToJSON(data.steps)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Trip Simulation Report - \(escapeHTML(data.wellName))</title>
            <style>
                \(generateCSS())
            </style>
        </head>
        <body>
            <header>
                <div class="header-content">
                    <h1>Trip Simulation Report</h1>
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
                            <span class="label">Trip:</span>
                            <span class="value">\(direction)</span>
                        </div>
                    </div>
                </section>

                <!-- Simulation Parameters -->
                <section class="card">
                    <h2>Simulation Parameters</h2>
                    <div class="params-grid">
                        <div class="param-item">
                            <span class="label">Start MD:</span>
                            <span class="value">\(String(format: "%.0f m", data.startMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">End MD:</span>
                            <span class="value">\(String(format: "%.0f m", data.endMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Control MD:</span>
                            <span class="value">\(String(format: "%.0f m", data.controlMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Step Size:</span>
                            <span class="value">\(String(format: "%.0f m", data.stepSize))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Base Mud:</span>
                            <span class="value">\(String(format: "%.0f kg/m³", data.baseMudDensity))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Backfill:</span>
                            <span class="value">\(String(format: "%.0f kg/m³", data.backfillDensity))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Target ESD:</span>
                            <span class="value">\(String(format: "%.0f kg/m³", data.targetESD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Crack Float:</span>
                            <span class="value">\(String(format: "%.0f kPa", data.crackFloat))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Initial SABP:</span>
                            <span class="value">\(String(format: "%.0f kPa", data.initialSABP))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Trip Speed:</span>
                            <span class="value">\(String(format: "%.1f m/min", data.tripSpeed))</span>
                        </div>
                    </div>
                </section>

                <!-- Safety Summary -->
                <section class="card">
                    <h2>Safety Summary</h2>
                    <div class="metrics-grid">
                        <div class="metric-box">
                            <div class="metric-title">ESD Range</div>
                            <div class="metric-value">\(String(format: "%.0f - %.0f", data.minESD, data.maxESD))</div>
                            <div class="metric-unit">kg/m³</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Max Static SABP</div>
                            <div class="metric-value">\(String(format: "%.0f", data.maxStaticSABP))</div>
                            <div class="metric-unit">kPa</div>
                        </div>
                        <div class="metric-box \(data.maxDynamicSABP > 50 ? "warning" : "")">
                            <div class="metric-title">Max Dynamic SABP</div>
                            <div class="metric-value">\(String(format: "%.0f", data.maxDynamicSABP))</div>
                            <div class="metric-unit">kPa</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Total Backfill</div>
                            <div class="metric-value">\(String(format: "%.1f", data.totalBackfill))</div>
                            <div class="metric-unit">m³</div>
                        </div>
                    </div>
                    <div class="metrics-grid secondary">
                        <div class="metric-box small">
                            <div class="metric-title">Initial Pit Gain</div>
                            <div class="metric-value">\(String(format: "%.2f m³", data.totalPitGain))</div>
                        </div>
                        <div class="metric-box small \(data.netTankChange < 0 ? "danger" : "")">
                            <div class="metric-title">Net Tank Change</div>
                            <div class="metric-value">\(String(format: "%+.1f m³", data.netTankChange))</div>
                        </div>
                        <div class="metric-box small">
                            <div class="metric-title">Number of Steps</div>
                            <div class="metric-value">\(data.steps.count)</div>
                        </div>
                    </div>
                </section>

                <!-- Interactive Wellbore Visualization -->
                <section class="card">
                    <h2>Interactive Well Snapshot</h2>
                    <div class="wellbore-controls">
                        <div class="slider-container">
                            <label for="depth-slider">Trip Progress:</label>
                            <input type="range" id="depth-slider" min="0" max="\(data.steps.count - 1)" value="0">
                            <span id="current-depth">--</span>
                        </div>
                        <div class="playback-controls">
                            <button id="play-btn" onclick="togglePlayback()">▶ Play</button>
                            <button onclick="resetPlayback()">⟲ Reset</button>
                            <select id="speed-select">
                                <option value="500">Slow</option>
                                <option value="200" selected>Normal</option>
                                <option value="50">Fast</option>
                            </select>
                        </div>
                    </div>
                    <div class="wellbore-display">
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
                        <div class="depth-scale" id="depth-scale"></div>
                    </div>
                    <div class="step-info" id="step-info">
                        <div class="info-row"><span>Bit MD:</span> <span id="info-md">--</span></div>
                        <div class="info-row"><span>ESD @ TD:</span> <span id="info-esd">--</span></div>
                        <div class="info-row"><span>Static SABP:</span> <span id="info-sabp">--</span></div>
                        <div class="info-row"><span>Float State:</span> <span id="info-float">--</span></div>
                        <div class="info-row"><span>Step Backfill:</span> <span id="info-backfill">--</span></div>
                    </div>
                </section>

                <!-- Charts -->
                <section class="card">
                    <h2>Trip Profile Charts</h2>
                    <div class="charts-grid">
                        <div class="chart-container">
                            <canvas id="chart-esd"></canvas>
                        </div>
                        <div class="chart-container">
                            <canvas id="chart-sabp"></canvas>
                        </div>
                        <div class="chart-container">
                            <canvas id="chart-tank"></canvas>
                        </div>
                        <div class="chart-container">
                            <canvas id="chart-backfill"></canvas>
                        </div>
                    </div>
                </section>

                <!-- Geometry Tables -->
                <section class="card">
                    <h2>Well Geometry</h2>
                    <h3>Drill String</h3>
                    \(generateDrillStringTable(data.drillStringSections, totalCapacity: data.totalStringCapacity))

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
                                    <th onclick="sortTable(0)">MD (m) ⇅</th>
                                    <th onclick="sortTable(1)">TVD (m) ⇅</th>
                                    <th onclick="sortTable(2)">Static SABP ⇅</th>
                                    <th onclick="sortTable(3)">Dynamic SABP ⇅</th>
                                    <th onclick="sortTable(4)">ESD (kg/m³) ⇅</th>
                                    <th onclick="sortTable(5)">DP Wet (m³) ⇅</th>
                                    <th onclick="sortTable(6)">DP Dry (m³) ⇅</th>
                                    <th onclick="sortTable(7)">Actual (m³) ⇅</th>
                                    <th onclick="sortTable(8)">Tank Δ (m³) ⇅</th>
                                    <th onclick="sortTable(9)">Float ⇅</th>
                                </tr>
                            </thead>
                            <tbody>
                                \(generateTableRows(data.steps))
                            </tbody>
                        </table>
                    </div>
                    <div class="table-legend">
                        Units: MD/TVD (m), SABP (kPa), ESD (kg/m³), Fill volumes (m³), Tank Δ (m³ cumulative)
                    </div>
                </section>
            </main>

            <footer>
                <p>Generated by Josh Well Control • \(dateStr)</p>
            </footer>

            <script>
                // Simulation data
                const steps = \(stepsJSON);
                const maxDepth = \(String(format: "%.1f", max(data.startMD, data.steps.map { $0.bitMD_m }.max() ?? 0)));

                // Playback state
                let isPlaying = false;
                let playbackInterval = null;
                let currentStepIndex = 0;

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
            --brand-color: #52a5bf;
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
            margin-bottom: 12px;
        }

        .metrics-grid.secondary {
            grid-template-columns: repeat(3, 1fr);
        }

        .metric-box {
            background: var(--bg-color);
            border-radius: 6px;
            padding: 12px;
            text-align: center;
        }

        .metric-box.small {
            padding: 10px;
        }

        .metric-box.warning .metric-value {
            color: var(--warning-color);
        }

        .metric-box.danger .metric-value {
            color: var(--danger-color);
        }

        .metric-title {
            font-size: 0.75rem;
            color: var(--text-light);
            margin-bottom: 4px;
        }

        .metric-value {
            font-size: 1.3rem;
            font-weight: 700;
            color: var(--safe-color);
        }

        .metric-box.small .metric-value {
            font-size: 1.1rem;
        }

        .metric-unit {
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

        #current-depth {
            font-weight: 600;
            min-width: 80px;
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
            display: flex;
            justify-content: center;
            gap: 4px;
            padding: 20px;
            background: #1a1a1a;
            border-radius: 6px;
            position: relative;
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
            background: #2a2a2a;
        }

        .depth-scale {
            position: absolute;
            right: 20px;
            top: 50px;
            bottom: 30px;
            width: 50px;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
            color: rgba(255,255,255,0.6);
            font-size: 0.7rem;
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
        }

        .chart-container canvas {
            width: 100% !important;
            height: 100% !important;
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
            user-select: none;
        }

        th:hover {
            background: #4795ab;
        }

        td {
            padding: 8px;
            text-align: right;
            border-bottom: 1px solid var(--border-color);
        }

        tr:nth-child(even) {
            background: var(--bg-color);
        }

        tr:hover {
            background: #e3f2fd;
        }

        tr.highlight {
            background: #bbdefb !important;
        }

        .table-legend {
            margin-top: 8px;
            font-size: 0.7rem;
            color: var(--text-light);
        }

        .volume-summary {
            margin-top: 16px;
            padding: 12px;
            background: var(--bg-color);
            border-radius: 6px;
            max-width: 300px;
        }

        .volume-summary h4 {
            font-size: 0.9rem;
            color: var(--brand-color);
            margin-bottom: 8px;
        }

        .summary-row {
            display: flex;
            justify-content: space-between;
            font-size: 0.85rem;
            padding: 4px 0;
        }

        .summary-row.total {
            border-top: 1px solid var(--border-color);
            margin-top: 4px;
            padding-top: 8px;
            font-weight: 600;
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
            initSlider();
            initCharts();
            updateWellbore(0);
            buildDepthScale();
        });

        // Slider functionality
        function initSlider() {
            const slider = document.getElementById('depth-slider');
            slider.addEventListener('input', function() {
                currentStepIndex = parseInt(this.value);
                updateWellbore(currentStepIndex);
                highlightTableRow(currentStepIndex);
            });
        }

        function updateWellbore(index) {
            if (index < 0 || index >= steps.length) return;
            const step = steps[index];

            // Update info display
            document.getElementById('current-depth').textContent = step.bitMD.toFixed(0) + ' m';
            document.getElementById('info-md').textContent = step.bitMD.toFixed(0) + ' m';
            document.getElementById('info-esd').textContent = step.esd.toFixed(0) + ' kg/m³';
            document.getElementById('info-sabp').textContent = step.sabpStatic.toFixed(0) + ' kPa';
            document.getElementById('info-float').textContent = step.floatState;
            document.getElementById('info-backfill').textContent = step.stepBackfill.toFixed(3) + ' m³';

            // Draw wellbore canvases
            drawWellboreColumn('annulus-left', step.layersAnnulus, step.bitMD, 'annulus');
            drawWellboreColumn('string-canvas', step.layersString, step.bitMD, 'string');
            drawWellboreColumn('annulus-right', step.layersAnnulus, step.bitMD, 'annulus');

            // Draw pocket on all canvases below bit
            drawPocket('annulus-left', step.layersPocket, step.bitMD);
            drawPocket('string-canvas', step.layersPocket, step.bitMD);
            drawPocket('annulus-right', step.layersPocket, step.bitMD);

            // Update chart marker if charts exist
            updateChartMarker(index);
        }

        function drawWellboreColumn(canvasId, layers, bitMD, type) {
            const canvas = document.getElementById(canvasId);
            const ctx = canvas.getContext('2d');
            const h = canvas.height;
            const w = canvas.width;

            // Clear
            ctx.fillStyle = '#2a2a2a';
            ctx.fillRect(0, 0, w, h);

            // Draw layers
            layers.forEach(layer => {
                if (layer.bottomMD > bitMD) return;
                const y1 = (layer.topMD / maxDepth) * h;
                const y2 = (layer.bottomMD / maxDepth) * h;
                const layerH = Math.max(1, y2 - y1);

                ctx.fillStyle = layer.color || densityToColor(layer.rho);
                ctx.fillRect(0, y1, w, layerH);
            });

            // Draw bit line
            const bitY = (bitMD / maxDepth) * h;
            ctx.fillStyle = '#e05040';
            ctx.fillRect(0, bitY - 1, w, 2);
        }

        function drawPocket(canvasId, layers, bitMD) {
            const canvas = document.getElementById(canvasId);
            const ctx = canvas.getContext('2d');
            const h = canvas.height;
            const w = canvas.width;

            layers.forEach(layer => {
                const y1 = (layer.topMD / maxDepth) * h;
                const y2 = (layer.bottomMD / maxDepth) * h;
                const layerH = Math.max(1, y2 - y1);

                ctx.fillStyle = layer.color || densityToColor(layer.rho);
                ctx.fillRect(0, y1, w, layerH);
            });
        }

        function densityToColor(rho) {
            // Map density to grayscale (lighter = lighter mud)
            const t = Math.min(Math.max((rho - 800) / 1200, 0), 1);
            const v = Math.round(80 + 150 * (1 - t));
            return `rgb(${v}, ${v}, ${v})`;
        }

        function buildDepthScale() {
            const scale = document.getElementById('depth-scale');
            scale.innerHTML = '';
            for (let i = 0; i <= 5; i++) {
                const d = document.createElement('div');
                d.textContent = (maxDepth * i / 5).toFixed(0) + 'm';
                scale.appendChild(d);
            }
        }

        // Playback controls
        function togglePlayback() {
            const btn = document.getElementById('play-btn');
            if (isPlaying) {
                clearInterval(playbackInterval);
                btn.textContent = '▶ Play';
                isPlaying = false;
            } else {
                const speed = parseInt(document.getElementById('speed-select').value);
                playbackInterval = setInterval(() => {
                    currentStepIndex++;
                    if (currentStepIndex >= steps.length) {
                        currentStepIndex = 0;
                    }
                    document.getElementById('depth-slider').value = currentStepIndex;
                    updateWellbore(currentStepIndex);
                    highlightTableRow(currentStepIndex);
                }, speed);
                btn.textContent = '⏸ Pause';
                isPlaying = true;
            }
        }

        function resetPlayback() {
            if (isPlaying) togglePlayback();
            currentStepIndex = 0;
            document.getElementById('depth-slider').value = 0;
            updateWellbore(0);
            highlightTableRow(0);
        }

        // Charts
        let charts = {};

        function initCharts() {
            const depths = steps.map(s => s.bitMD);
            const esds = steps.map(s => s.esd);
            const sabpStatic = steps.map(s => s.sabpStatic);
            const sabpDynamic = steps.map(s => s.sabpDynamic);
            const tankDeltas = steps.map(s => s.tankDelta);
            const backfills = steps.map(s => s.cumBackfill);

            charts.esd = createChart('chart-esd', 'ESD vs Depth', depths, [
                { data: esds, label: 'ESD (kg/m³)', color: '#2196f3' }
            ]);

            charts.sabp = createChart('chart-sabp', 'SABP vs Depth', depths, [
                { data: sabpStatic, label: 'Static', color: '#4caf50' },
                { data: sabpDynamic, label: 'Dynamic', color: '#ff9800' }
            ]);

            charts.tank = createChart('chart-tank', 'Tank Volume Change', depths, [
                { data: tankDeltas, label: 'Tank Δ (m³)', color: '#9c27b0' }
            ]);

            charts.backfill = createChart('chart-backfill', 'Cumulative Backfill', depths, [
                { data: backfills, label: 'Backfill (m³)', color: '#009688' }
            ]);
        }

        function createChart(canvasId, title, xData, datasets) {
            const canvas = document.getElementById(canvasId);
            const ctx = canvas.getContext('2d');
            const rect = canvas.parentElement.getBoundingClientRect();
            canvas.width = rect.width - 24;
            canvas.height = rect.height - 24;

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

                // X labels (inverted for depth)
                ctx.textAlign = 'center';
                for (let i = 0; i <= 4; i++) {
                    const val = xMax - (xMax - xMin) * i / 4;
                    const x = margin.left + (plotW * i / 4);
                    ctx.fillText(val.toFixed(0), x, h - margin.bottom + 15);
                }

                // Data lines
                datasets.forEach(ds => {
                    ctx.strokeStyle = ds.color;
                    ctx.lineWidth = 1.5;
                    ctx.beginPath();
                    xData.forEach((x, i) => {
                        const px = margin.left + ((xMax - x) / (xMax - xMin)) * plotW;
                        const py = margin.top + ((yMax - ds.data[i]) / (yMax - yMin)) * plotH;
                        if (i === 0) ctx.moveTo(px, py);
                        else ctx.lineTo(px, py);
                    });
                    ctx.stroke();
                });

                // Highlight marker
                if (highlightIndex >= 0 && highlightIndex < xData.length) {
                    const x = xData[highlightIndex];
                    const px = margin.left + ((xMax - x) / (xMax - xMin)) * plotW;
                    ctx.strokeStyle = '#f44336';
                    ctx.lineWidth = 1;
                    ctx.setLineDash([4, 4]);
                    ctx.beginPath();
                    ctx.moveTo(px, margin.top);
                    ctx.lineTo(px, h - margin.bottom);
                    ctx.stroke();
                    ctx.setLineDash([]);
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

            draw();
            return { draw };
        }

        function updateChartMarker(index) {
            Object.values(charts).forEach(chart => {
                if (chart && chart.draw) chart.draw(index);
            });
        }

        // Table functionality
        function highlightTableRow(index) {
            const rows = document.querySelectorAll('#data-table tbody tr');
            rows.forEach((row, i) => {
                row.classList.toggle('highlight', i === index);
            });
            // Note: Auto-scroll removed to prevent screen jumping
        }

        let sortDirection = {};
        function sortTable(columnIndex) {
            const table = document.getElementById('data-table');
            const tbody = table.querySelector('tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));

            sortDirection[columnIndex] = !sortDirection[columnIndex];
            const dir = sortDirection[columnIndex] ? 1 : -1;

            rows.sort((a, b) => {
                const aVal = parseFloat(a.cells[columnIndex].textContent) || 0;
                const bVal = parseFloat(b.cells[columnIndex].textContent) || 0;
                return (aVal - bVal) * dir;
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
            const headers = Array.from(table.querySelectorAll('th')).map(th => th.textContent.replace(' ⇅', ''));
            csv.push(headers.join(','));

            table.querySelectorAll('tbody tr').forEach(row => {
                const cols = Array.from(row.querySelectorAll('td')).map(td => td.textContent);
                csv.push(cols.join(','));
            });

            const blob = new Blob([csv.join('\\n')], { type: 'text/csv' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'trip_simulation_data.csv';
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

    private func stepsToJSON(_ steps: [NumericalTripModel.TripStep]) -> String {
        var json = "["
        for (i, step) in steps.enumerated() {
            if i > 0 { json += "," }
            json += """
            {
                "bitMD": \(step.bitMD_m),
                "bitTVD": \(step.bitTVD_m),
                "esd": \(step.ESDatTD_kgpm3),
                "sabpStatic": \(step.SABP_kPa),
                "sabpDynamic": \(step.SABP_Dynamic_kPa),
                "tankDelta": \(step.cumulativeSurfaceTankDelta_m3),
                "cumBackfill": \(step.cumulativeBackfill_m3),
                "stepBackfill": \(step.stepBackfill_m3),
                "floatState": "\(step.floatState)",
                "layersAnnulus": \(layersToJSON(step.layersAnnulus)),
                "layersString": \(layersToJSON(step.layersString)),
                "layersPocket": \(layersToJSON(step.layersPocket))
            }
            """
        }
        json += "]"
        return json
    }

    private func layersToJSON(_ layers: [NumericalTripModel.LayerRow]) -> String {
        var json = "["
        for (i, layer) in layers.enumerated() {
            if i > 0 { json += "," }
            let colorStr: String
            if let c = layer.color {
                colorStr = "\"rgba(\(Int(c.r * 255)), \(Int(c.g * 255)), \(Int(c.b * 255)), \(c.a))\""
            } else {
                colorStr = "null"
            }
            json += """
            {"topMD": \(layer.topMD), "bottomMD": \(layer.bottomMD), "rho": \(layer.rho_kgpm3), "color": \(colorStr)}
            """
        }
        json += "]"
        return json
    }

    private func generateTableRows(_ steps: [NumericalTripModel.TripStep]) -> String {
        var html = ""
        for step in steps {
            html += """
            <tr>
                <td>\(String(format: "%.0f", step.bitMD_m))</td>
                <td>\(String(format: "%.0f", step.bitTVD_m))</td>
                <td>\(String(format: "%.0f", step.SABP_kPa))</td>
                <td>\(String(format: "%.0f", step.SABP_Dynamic_kPa))</td>
                <td>\(String(format: "%.0f", step.ESDatTD_kgpm3))</td>
                <td>\(String(format: "%.3f", step.expectedFillIfClosed_m3))</td>
                <td>\(String(format: "%.3f", step.expectedFillIfOpen_m3))</td>
                <td>\(String(format: "%.3f", step.stepBackfill_m3))</td>
                <td>\(String(format: "%+.2f", step.cumulativeSurfaceTankDelta_m3))</td>
                <td>\(step.floatState)</td>
            </tr>
            """
        }
        return html
    }

    private func generateDrillStringTable(_ sections: [PDFSectionData], totalCapacity: Double) -> String {
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
                    <th>Cap (m³/m)</th>
                    <th>Disp (m³/m)</th>
                    <th>Vol (m³)</th>
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
                    <th>Cap (m³/m)</th>
                    <th>Vol (m³)</th>
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
