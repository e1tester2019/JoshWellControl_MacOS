//
//  TorqueDragHTMLGenerator.swift
//  Josh Well Control for Mac
//
//  Interactive HTML report generator for Torque & Drag analysis
//

import Foundation

/// Report data for Torque & Drag analysis
struct TorqueDragReportData {
    let wellName: String
    let projectName: String
    let generatedDate: Date
    // Well info
    let wellTD_m: Double
    let shoeMD_m: Double
    // Friction factors
    let casedFF: Double
    let openHoleFF: Double
    let blockWeight_kN: Double
    // Drill string summary
    let drillStringSections: [(name: String, od_m: Double, id_m: Double, topMD: Double, bottomMD: Double, weight_kgm: Double)]
    // Hole sections
    let holeSections: [(name: String, diameter_m: Double, topMD: Double, bottomMD: Double, isCased: Bool)]
    // Mud properties
    let mudDensity_kgpm3: Double
    // Results at TD
    let pickupHookLoad_kN: Double
    let slackOffHookLoad_kN: Double
    let rotatingHookLoad_kN: Double
    let freeHangingWeight_kN: Double
    let surfaceTorque_kNm: Double
    let pickupStretch_m: Double
    let slackOffStretch_m: Double
    let bucklingOnsetMD: Double?
    let bucklingType: String?
    let neutralPointMD: Double?
    let stringWeightInAir_kN: Double
    let stringBuoyedWeight_kN: Double
    // Per-segment data for charts
    let segments: [TorqueDragEngine.SegmentResult]
    let pickupSegments: [TorqueDragEngine.SegmentResult]
    let slackOffSegments: [TorqueDragEngine.SegmentResult]
    // Sensitivity analysis
    let sensitivityResults: [TorqueDragEngine.SensitivityResult]
}

/// Cross-platform HTML generator for Torque & Drag reports
class TorqueDragHTMLGenerator {
    static let shared = TorqueDragHTMLGenerator()

    private init() {}

    func generateHTML(for data: TorqueDragReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"
        let dateStr = dateFormatter.string(from: data.generatedDate)

        let segmentsJSON = segmentsToJSON(data.segments, label: "rotating")
        let pickupJSON = segmentsToJSON(data.pickupSegments, label: "pickup")
        let slackOffJSON = segmentsToJSON(data.slackOffSegments, label: "slackoff")
        let sensitivityJSON = sensitivityToJSON(data.sensitivityResults)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Torque & Drag Report - \(escapeHTML(data.wellName))</title>
            <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
            <style>
                \(generateCSS())
            </style>
        </head>
        <body>
            <header>
                <div class="header-content">
                    <h1>Torque & Drag Report</h1>
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
                            <span class="label">Total Depth:</span>
                            <span class="value">\(f0(data.wellTD_m)) m</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Shoe Depth:</span>
                            <span class="value">\(f0(data.shoeMD_m)) m</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Mud Density:</span>
                            <span class="value">\(f0(data.mudDensity_kgpm3)) kg/m\u{00B3}</span>
                        </div>
                    </div>
                </section>

                <!-- Friction Factors -->
                <section class="card">
                    <h2>Friction Factors</h2>
                    <div class="params-grid">
                        <div class="param-item">
                            <span class="label">Cased Hole:</span>
                            <span class="value">\(f2(data.casedFF))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Open Hole:</span>
                            <span class="value">\(f2(data.openHoleFF))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Block Weight:</span>
                            <span class="value">\(f1(data.blockWeight_kN)) kN</span>
                        </div>
                    </div>
                </section>

                <!-- T&D Results Summary -->
                <section class="card">
                    <h2>Torque & Drag Results at TD</h2>
                    <div class="metrics-grid">
                        <div class="metric-box">
                            <div class="metric-title">Pickup (Trip Out)</div>
                            <div class="metric-value">\(f1(data.pickupHookLoad_kN))</div>
                            <div class="metric-unit">kN (\(f0(data.pickupHookLoad_kN * 100)) daN)</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Slack-off (Trip In)</div>
                            <div class="metric-value">\(f1(data.slackOffHookLoad_kN))</div>
                            <div class="metric-unit">kN (\(f0(data.slackOffHookLoad_kN * 100)) daN)</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Rotating Off-Bottom</div>
                            <div class="metric-value">\(f1(data.rotatingHookLoad_kN))</div>
                            <div class="metric-unit">kN (\(f0(data.rotatingHookLoad_kN * 100)) daN)</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Free Hanging</div>
                            <div class="metric-value">\(f1(data.freeHangingWeight_kN))</div>
                            <div class="metric-unit">kN (\(f0(data.freeHangingWeight_kN * 100)) daN)</div>
                        </div>
                    </div>
                    <div class="metrics-grid secondary">
                        <div class="metric-box small">
                            <div class="metric-title">Surface Torque</div>
                            <div class="metric-value">\(f2(data.surfaceTorque_kNm))</div>
                            <div class="metric-unit">kNm</div>
                        </div>
                        <div class="metric-box small">
                            <div class="metric-title">Pickup Stretch</div>
                            <div class="metric-value">\(f2(data.pickupStretch_m))</div>
                            <div class="metric-unit">m</div>
                        </div>
                        <div class="metric-box small">
                            <div class="metric-title">Slack-off Stretch</div>
                            <div class="metric-value">\(f2(data.slackOffStretch_m))</div>
                            <div class="metric-unit">m</div>
                        </div>
                    </div>
                    <div class="metrics-grid secondary">
                        <div class="metric-box small">
                            <div class="metric-title">String Weight (Air)</div>
                            <div class="metric-value">\(f1(data.stringWeightInAir_kN))</div>
                            <div class="metric-unit">kN</div>
                        </div>
                        <div class="metric-box small">
                            <div class="metric-title">String Buoyed Weight</div>
                            <div class="metric-value">\(f1(data.stringBuoyedWeight_kN))</div>
                            <div class="metric-unit">kN</div>
                        </div>
                        <div class="metric-box small \(data.bucklingOnsetMD != nil ? "warning" : "")">
                            <div class="metric-title">Buckling Onset</div>
                            <div class="metric-value">\(data.bucklingOnsetMD.map { f0($0) + " m" } ?? "None")</div>
                            <div class="metric-unit">\(data.bucklingType ?? "")</div>
                        </div>
                    </div>
                    \(data.neutralPointMD != nil ? """
                    <div class="metrics-grid secondary">
                        <div class="metric-box small">
                            <div class="metric-title">Neutral Point MD</div>
                            <div class="metric-value">\(f0(data.neutralPointMD!))</div>
                            <div class="metric-unit">m</div>
                        </div>
                    </div>
                    """ : "")
                </section>

                <!-- Drill String Table -->
                <section class="card">
                    <h2>Drill String</h2>
                    \(generateDrillStringTable(data.drillStringSections))
                </section>

                <!-- Hole Sections Table -->
                <section class="card">
                    <h2>Hole Sections</h2>
                    \(generateHoleSectionsTable(data.holeSections))
                </section>

                <!-- Hook Load vs Depth Chart -->
                <section class="card">
                    <h2>Hook Load vs Depth</h2>
                    <div class="chart-wrapper">
                        <canvas id="hookLoadChart"></canvas>
                    </div>
                </section>

                <!-- Axial Force / Buckling Chart -->
                <section class="card">
                    <h2>Axial Force & Buckling Limits</h2>
                    <div class="chart-wrapper">
                        <canvas id="axialForceChart"></canvas>
                    </div>
                </section>

                \(data.sensitivityResults.isEmpty ? "" : """
                <!-- Sensitivity Analysis Chart -->
                <section class="card">
                    <h2>Sensitivity Analysis (Hook Load vs Friction Factor)</h2>
                    <div class="chart-wrapper">
                        <canvas id="sensitivityChart"></canvas>
                    </div>
                </section>
                """)

            </main>

            <footer>
                <p>Generated by Josh Well Control &mdash; \(dateStr)</p>
            </footer>

            <script>
            const pickupSegments = \(pickupJSON);
            const slackOffSegments = \(slackOffJSON);
            const rotatingSegments = \(segmentsJSON);
            const sensitivityData = \(sensitivityJSON);

            \(generateJavaScript())
            </script>
        </body>
        </html>
        """
    }

    // MARK: - CSS

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

        @media (prefers-color-scheme: dark) {
            :root {
                --bg-color: #1a1a1a;
                --card-bg: #2a2a2a;
                --text-color: #e0e0e0;
                --text-light: #999999;
                --border-color: #444444;
            }
            tr:nth-child(even) { background: #333 !important; }
            tr:hover { background: #3a3a3a !important; }
            th:hover { background: #4795ab; }
        }

        * { box-sizing: border-box; margin: 0; padding: 0; }

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

        header h1 { font-size: 1.5rem; font-weight: 600; }
        .well-name { opacity: 0.9; font-size: 0.9rem; }

        main { max-width: 1200px; margin: 0 auto; padding: 24px; }

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

        .info-item, .param-item { display: flex; gap: 8px; }
        .label { color: var(--text-light); font-size: 0.85rem; }
        .value { font-weight: 500; }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
            gap: 12px;
            margin-bottom: 12px;
        }

        .metrics-grid.secondary { grid-template-columns: repeat(3, 1fr); }

        .metric-box {
            background: var(--bg-color);
            border-radius: 6px;
            padding: 12px;
            text-align: center;
        }

        .metric-box.small { padding: 10px; }
        .metric-box.warning .metric-value { color: var(--warning-color); }
        .metric-box.danger .metric-value { color: var(--danger-color); }

        .metric-title { font-size: 0.75rem; color: var(--text-light); margin-bottom: 4px; }
        .metric-value { font-size: 1.3rem; font-weight: 700; color: var(--safe-color); }
        .metric-box.small .metric-value { font-size: 1.1rem; }
        .metric-unit { font-size: 0.7rem; color: var(--text-light); }

        .chart-wrapper {
            position: relative;
            height: 450px;
            padding: 12px;
        }

        .chart-wrapper canvas {
            width: 100% !important;
            height: 100% !important;
        }

        table { width: 100%; border-collapse: collapse; font-size: 0.8rem; }
        thead { position: sticky; top: 0; z-index: 10; }
        th {
            background: var(--brand-color);
            color: white;
            padding: 10px 8px;
            text-align: right;
            white-space: nowrap;
        }
        th:first-child { text-align: left; }
        td { padding: 8px; text-align: right; border-bottom: 1px solid var(--border-color); }
        td:first-child { text-align: left; }
        tr:nth-child(even) { background: var(--bg-color); }
        tr:hover { background: #e3f2fd; }

        .total-row {
            background: #e0e0e0 !important;
            font-weight: 600;
        }

        footer { text-align: center; padding: 20px; color: var(--text-light); font-size: 0.8rem; }

        @media print {
            header { position: static; }
            .card { break-inside: avoid; }
            .chart-wrapper { height: 350px; }
        }
        """
    }

    // MARK: - JavaScript

    private func generateJavaScript() -> String {
        return """
        document.addEventListener('DOMContentLoaded', function() {
            initHookLoadChart();
            initAxialForceChart();
            if (sensitivityData.length > 0) {
                initSensitivityChart();
            }
        });

        function initHookLoadChart() {
            const ctx = document.getElementById('hookLoadChart');
            if (!ctx) return;

            // Build datasets: axial force profile (Y inverted) vs depth
            const pickupData = pickupSegments.map(s => ({ x: s.hookLoad, y: s.md }));
            const slackOffData = slackOffSegments.map(s => ({ x: s.hookLoad, y: s.md }));
            const rotatingData = rotatingSegments.map(s => ({ x: s.hookLoad, y: s.md }));

            new Chart(ctx, {
                type: 'scatter',
                data: {
                    datasets: [
                        {
                            label: 'Pickup (Trip Out)',
                            data: pickupData,
                            borderColor: '#4caf50',
                            backgroundColor: 'rgba(76, 175, 80, 0.1)',
                            showLine: true,
                            pointRadius: 0,
                            borderWidth: 2
                        },
                        {
                            label: 'Slack-off (Trip In)',
                            data: slackOffData,
                            borderColor: '#f44336',
                            backgroundColor: 'rgba(244, 67, 54, 0.1)',
                            showLine: true,
                            pointRadius: 0,
                            borderWidth: 2
                        },
                        {
                            label: 'Rotating Off-Bottom',
                            data: rotatingData,
                            borderColor: '#2196f3',
                            backgroundColor: 'rgba(33, 150, 243, 0.1)',
                            showLine: true,
                            pointRadius: 0,
                            borderWidth: 2
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: {
                            title: { display: true, text: 'Hook Load (kN)' },
                            grid: { color: 'rgba(128,128,128,0.2)' }
                        },
                        y: {
                            title: { display: true, text: 'Measured Depth (m)' },
                            reverse: true,
                            grid: { color: 'rgba(128,128,128,0.2)' }
                        }
                    },
                    plugins: {
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    return context.dataset.label + ': ' + context.parsed.x.toFixed(1) + ' kN at ' + context.parsed.y.toFixed(0) + ' m';
                                }
                            }
                        }
                    }
                }
            });
        }

        function initAxialForceChart() {
            const ctx = document.getElementById('axialForceChart');
            if (!ctx) return;

            const pickupAxial = pickupSegments.map(s => ({ x: s.axial, y: s.md }));
            const slackOffAxial = slackOffSegments.map(s => ({ x: s.axial, y: s.md }));
            const sinBuckle = slackOffSegments.map(s => ({ x: -s.critBuckle, y: s.md }));
            const helBuckle = slackOffSegments.map(s => ({ x: -s.helBuckle, y: s.md }));

            const datasets = [
                {
                    label: 'Pickup Axial Force',
                    data: pickupAxial,
                    borderColor: '#4caf50',
                    showLine: true,
                    pointRadius: 0,
                    borderWidth: 2
                },
                {
                    label: 'Slack-off Axial Force',
                    data: slackOffAxial,
                    borderColor: '#f44336',
                    showLine: true,
                    pointRadius: 0,
                    borderWidth: 2
                },
                {
                    label: 'Sinusoidal Buckling Limit',
                    data: sinBuckle,
                    borderColor: '#ff9800',
                    borderDash: [8, 4],
                    backgroundColor: 'transparent',
                    showLine: true,
                    pointRadius: 0,
                    borderWidth: 1.5
                },
                {
                    label: 'Helical Buckling Limit',
                    data: helBuckle,
                    borderColor: '#e91e63',
                    borderDash: [4, 4],
                    backgroundColor: 'transparent',
                    showLine: true,
                    pointRadius: 0,
                    borderWidth: 1.5
                }
            ];

            new Chart(ctx, {
                type: 'scatter',
                data: { datasets: datasets },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: {
                            title: { display: true, text: 'Axial Force (kN)  [+ tension, - compression]' },
                            grid: { color: 'rgba(128,128,128,0.2)' }
                        },
                        y: {
                            title: { display: true, text: 'Measured Depth (m)' },
                            reverse: true,
                            grid: { color: 'rgba(128,128,128,0.2)' }
                        }
                    },
                    plugins: {
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    return context.dataset.label + ': ' + context.parsed.x.toFixed(1) + ' kN at ' + context.parsed.y.toFixed(0) + ' m';
                                }
                            }
                        }
                    }
                }
            });
        }

        function initSensitivityChart() {
            const ctx = document.getElementById('sensitivityChart');
            if (!ctx) return;

            const ffLabels = sensitivityData.map(d => d.ff.toFixed(2));
            const pickupHL = sensitivityData.map(d => d.pickup);
            const slackOffHL = sensitivityData.map(d => d.slackoff);
            const rotatingHL = sensitivityData.map(d => d.rotating);

            new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: ffLabels,
                    datasets: [
                        {
                            label: 'Pickup (kN)',
                            data: pickupHL,
                            backgroundColor: 'rgba(76, 175, 80, 0.7)',
                            borderColor: '#4caf50',
                            borderWidth: 1
                        },
                        {
                            label: 'Slack-off (kN)',
                            data: slackOffHL,
                            backgroundColor: 'rgba(244, 67, 54, 0.7)',
                            borderColor: '#f44336',
                            borderWidth: 1
                        },
                        {
                            label: 'Rotating (kN)',
                            data: rotatingHL,
                            backgroundColor: 'rgba(33, 150, 243, 0.7)',
                            borderColor: '#2196f3',
                            borderWidth: 1
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        x: {
                            title: { display: true, text: 'Friction Factor' }
                        },
                        y: {
                            title: { display: true, text: 'Hook Load (kN)' },
                            beginAtZero: true
                        }
                    },
                    plugins: {
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    return context.dataset.label + ': ' + context.parsed.y.toFixed(1) + ' kN';
                                }
                            }
                        }
                    }
                }
            });
        }
        """
    }

    // MARK: - Table Generators

    private func generateDrillStringTable(_ sections: [(name: String, od_m: Double, id_m: Double, topMD: Double, bottomMD: Double, weight_kgm: Double)]) -> String {
        var html = """
        <div class="table-wrapper">
            <table>
                <thead>
                    <tr>
                        <th>Section</th>
                        <th>OD (m)</th>
                        <th>ID (m)</th>
                        <th>Top MD (m)</th>
                        <th>Bottom MD (m)</th>
                        <th>Length (m)</th>
                        <th>Weight (kg/m)</th>
                    </tr>
                </thead>
                <tbody>
        """

        var totalLength: Double = 0
        for section in sections {
            let length = section.bottomMD - section.topMD
            totalLength += length
            html += """
                    <tr>
                        <td>\(escapeHTML(section.name))</td>
                        <td>\(f4(section.od_m))</td>
                        <td>\(f4(section.id_m))</td>
                        <td>\(f0(section.topMD))</td>
                        <td>\(f0(section.bottomMD))</td>
                        <td>\(f0(length))</td>
                        <td>\(f1(section.weight_kgm))</td>
                    </tr>
            """
        }

        html += """
                    <tr class="total-row">
                        <td>Total</td>
                        <td></td>
                        <td></td>
                        <td></td>
                        <td></td>
                        <td>\(f0(totalLength))</td>
                        <td></td>
                    </tr>
                </tbody>
            </table>
        </div>
        """

        return html
    }

    private func generateHoleSectionsTable(_ sections: [(name: String, diameter_m: Double, topMD: Double, bottomMD: Double, isCased: Bool)]) -> String {
        var html = """
        <div class="table-wrapper">
            <table>
                <thead>
                    <tr>
                        <th>Section</th>
                        <th>Diameter (m)</th>
                        <th>Diameter (in)</th>
                        <th>Top MD (m)</th>
                        <th>Bottom MD (m)</th>
                        <th>Length (m)</th>
                        <th>Type</th>
                    </tr>
                </thead>
                <tbody>
        """

        for section in sections {
            let length = section.bottomMD - section.topMD
            let diameterInches = section.diameter_m * 39.3701
            let typeStr = section.isCased ? "Cased" : "Open Hole"
            html += """
                    <tr>
                        <td>\(escapeHTML(section.name))</td>
                        <td>\(f4(section.diameter_m))</td>
                        <td>\(f2(diameterInches))</td>
                        <td>\(f0(section.topMD))</td>
                        <td>\(f0(section.bottomMD))</td>
                        <td>\(f0(length))</td>
                        <td>\(typeStr)</td>
                    </tr>
            """
        }

        html += """
                </tbody>
            </table>
        </div>
        """

        return html
    }

    // MARK: - JSON Serialization

    private func segmentsToJSON(_ segments: [TorqueDragEngine.SegmentResult], label: String) -> String {
        var json = "["
        for (i, seg) in segments.enumerated() {
            if i > 0 { json += "," }
            json += """
            {"md":\(f1(seg.midMD)),"tvd":\(f1(seg.midTVD)),"axial":\(f2(seg.axialForce_kN)),"normal":\(f2(seg.normalForce_kN)),"torque":\(f3(seg.torque_kNm)),"critBuckle":\(f2(seg.criticalBucklingLoad_kN)),"helBuckle":\(f2(seg.helicalBucklingLoad_kN)),"hookLoad":\(f2(seg.axialForce_kN)),"buckle":"\(seg.bucklingStatus.rawValue)"}
            """
        }
        json += "]"
        return json
    }

    private func sensitivityToJSON(_ results: [TorqueDragEngine.SensitivityResult]) -> String {
        var json = "["
        for (i, res) in results.enumerated() {
            if i > 0 { json += "," }
            json += """
            {"ff":\(f3(res.frictionFactor)),"pickup":\(f1(res.pickupHookLoad_kN)),"slackoff":\(f1(res.slackOffHookLoad_kN)),"rotating":\(f1(res.rotatingHookLoad_kN))}
            """
        }
        json += "]"
        return json
    }

    // MARK: - Helpers

    private func escapeHTML(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func f0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func f2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func f3(_ v: Double) -> String { String(format: "%.3f", v) }
    private func f4(_ v: Double) -> String { String(format: "%.4f", v) }
}
