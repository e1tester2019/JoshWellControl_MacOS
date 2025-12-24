//
//  TripRecordComparisonGenerator.swift
//  Josh Well Control for Mac
//
//  Generates HTML and CSV comparison reports for trip recordings vs simulations.
//

import Foundation

/// Generator for trip record comparison reports (HTML and CSV)
class TripRecordComparisonGenerator {
    static let shared = TripRecordComparisonGenerator()

    private init() {}

    // MARK: - Report Data Structure

    struct ComparisonReportData {
        let wellName: String
        let projectName: String
        let generatedDate: Date

        // Record info
        let recordName: String
        let recordStatus: String
        let sourceSimulationName: String
        let createdAt: Date
        let completedAt: Date?

        // Configuration
        let startMD: Double
        let endMD: Double
        let controlMD: Double
        let stepSize: Double
        let baseMudDensity: Double
        let backfillDensity: Double
        let targetESD: Double
        let crackFloat: Double

        // Summary statistics
        let totalSteps: Int
        let stepsRecorded: Int
        let stepsSkipped: Int
        let stepsPending: Int
        let avgSABPVariance: Double
        let maxSABPVariance: Double
        let avgBackfillVariance: Double
        let maxBackfillVariance: Double

        // Step data
        let steps: [StepData]

        struct StepData {
            let stepIndex: Int
            let bitMD_m: Double
            let bitTVD_m: Double
            let status: String
            let skipped: Bool
            let notes: String

            // Simulated values
            let simSABP_kPa: Double
            let simSABP_Dynamic_kPa: Double
            let simBackfill_m3: Double
            let simCumulativeBackfill_m3: Double
            let simESDatTD_kgpm3: Double
            let simFloatState: String

            // Actual values (optional)
            let actualSABP_kPa: Double?
            let actualSABP_Dynamic_kPa: Double?
            let actualBackfill_m3: Double?

            // Variance (optional)
            let sabpVariance_kPa: Double?
            let backfillVariance_m3: Double?
            let backfillVariancePercent: Double?
        }
    }

    // MARK: - Create Report Data from TripRecord

    func createReportData(from record: TripRecord, wellName: String, projectName: String) -> ComparisonReportData {
        let steps = record.sortedSteps.map { step -> ComparisonReportData.StepData in
            ComparisonReportData.StepData(
                stepIndex: step.stepIndex,
                bitMD_m: step.bitMD_m,
                bitTVD_m: step.bitTVD_m,
                status: step.status.rawValue,
                skipped: step.skipped,
                notes: step.notes,
                simSABP_kPa: step.simSABP_kPa,
                simSABP_Dynamic_kPa: step.simSABP_Dynamic_kPa,
                simBackfill_m3: step.simBackfill_m3,
                simCumulativeBackfill_m3: step.simCumulativeBackfill_m3,
                simESDatTD_kgpm3: step.simESDatTD_kgpm3,
                simFloatState: step.simFloatState,
                actualSABP_kPa: step.actualSABP_kPa,
                actualSABP_Dynamic_kPa: step.actualSABP_Dynamic_kPa,
                actualBackfill_m3: step.actualBackfill_m3,
                sabpVariance_kPa: step.sabpVariance_kPa,
                backfillVariance_m3: step.backfillVariance_m3,
                backfillVariancePercent: step.backfillVariancePercent
            )
        }

        return ComparisonReportData(
            wellName: wellName,
            projectName: projectName,
            generatedDate: Date(),
            recordName: record.name,
            recordStatus: record.status.label,
            sourceSimulationName: record.sourceSimulationName,
            createdAt: record.createdAt,
            completedAt: record.completedAt,
            startMD: record.startBitMD_m,
            endMD: record.endMD_m,
            controlMD: record.shoeMD_m,
            stepSize: record.step_m,
            baseMudDensity: record.baseMudDensity_kgpm3,
            backfillDensity: record.backfillDensity_kgpm3,
            targetESD: record.targetESDAtTD_kgpm3,
            crackFloat: record.crackFloat_kPa,
            totalSteps: record.stepCount,
            stepsRecorded: record.stepsRecorded,
            stepsSkipped: record.stepsSkipped,
            stepsPending: record.stepCount - record.stepsRecorded - record.stepsSkipped,
            avgSABPVariance: record.avgSABPVariance_kPa,
            maxSABPVariance: record.maxSABPVariance_kPa,
            avgBackfillVariance: record.avgBackfillVariance_m3,
            maxBackfillVariance: record.maxBackfillVariance_m3,
            steps: steps
        )
    }

    // MARK: - CSV Generation

    func generateCSV(for data: ComparisonReportData) -> String {
        var csv = ""

        // Header
        csv += "Step,Bit MD (m),Bit TVD (m),Status,"
        csv += "Sim SABP (kPa),Act SABP (kPa),SABP Var (kPa),"
        csv += "Sim Dynamic (kPa),Act Dynamic (kPa),"
        csv += "Sim Backfill (m³),Act Backfill (m³),BF Var (m³),BF Var (%),"
        csv += "Sim Cum BF (m³),Sim ESD (kg/m³),Float State,Notes\n"

        // Data rows
        for step in data.steps {
            csv += "\(step.stepIndex),"
            csv += "\(String(format: "%.1f", step.bitMD_m)),"
            csv += "\(String(format: "%.1f", step.bitTVD_m)),"
            csv += "\(step.skipped ? "Skipped" : step.status),"

            // SABP
            csv += "\(String(format: "%.0f", step.simSABP_kPa)),"
            csv += step.actualSABP_kPa.map { String(format: "%.0f", $0) } ?? ""
            csv += ","
            csv += step.sabpVariance_kPa.map { String(format: "%+.0f", $0) } ?? ""
            csv += ","

            // Dynamic SABP
            csv += "\(String(format: "%.0f", step.simSABP_Dynamic_kPa)),"
            csv += step.actualSABP_Dynamic_kPa.map { String(format: "%.0f", $0) } ?? ""
            csv += ","

            // Backfill
            csv += "\(String(format: "%.3f", step.simBackfill_m3)),"
            csv += step.actualBackfill_m3.map { String(format: "%.3f", $0) } ?? ""
            csv += ","
            csv += step.backfillVariance_m3.map { String(format: "%+.3f", $0) } ?? ""
            csv += ","
            csv += step.backfillVariancePercent.map { String(format: "%+.1f", $0) } ?? ""
            csv += ","

            // Other
            csv += "\(String(format: "%.3f", step.simCumulativeBackfill_m3)),"
            csv += "\(String(format: "%.0f", step.simESDatTD_kgpm3)),"
            csv += "\"\(step.simFloatState)\","
            csv += "\"\(step.notes.replacingOccurrences(of: "\"", with: "\"\""))\"\n"
        }

        return csv
    }

    // MARK: - HTML Generation

    func generateHTML(for data: ComparisonReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"
        let dateStr = dateFormatter.string(from: data.generatedDate)
        let createdStr = dateFormatter.string(from: data.createdAt)
        let completedStr = data.completedAt.map { dateFormatter.string(from: $0) } ?? "In Progress"

        let stepsJSON = stepsToJSON(data.steps)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Trip Record Comparison - \(escapeHTML(data.wellName))</title>
            <style>
                \(generateCSS())
            </style>
        </head>
        <body>
            <header>
                <div class="header-content">
                    <h1>Trip Record Comparison Report</h1>
                    <span class="well-name">\(escapeHTML(data.wellName))</span>
                </div>
            </header>

            <main>
                <!-- Record Information -->
                <section class="card">
                    <h2>Record Information</h2>
                    <div class="info-grid">
                        <div class="info-item">
                            <span class="label">Record Name:</span>
                            <span class="value">\(escapeHTML(data.recordName))</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Status:</span>
                            <span class="value status-\(data.recordStatus.lowercased().replacingOccurrences(of: " ", with: "-"))">\(data.recordStatus)</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Source Simulation:</span>
                            <span class="value">\(escapeHTML(data.sourceSimulationName))</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Well:</span>
                            <span class="value">\(escapeHTML(data.wellName))</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Project:</span>
                            <span class="value">\(escapeHTML(data.projectName))</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Created:</span>
                            <span class="value">\(createdStr)</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Completed:</span>
                            <span class="value">\(completedStr)</span>
                        </div>
                    </div>
                </section>

                <!-- Configuration -->
                <section class="card">
                    <h2>Configuration</h2>
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
                    </div>
                </section>

                <!-- Progress & Variance Summary -->
                <section class="card">
                    <h2>Summary</h2>
                    <div class="summary-grid">
                        <div class="summary-section">
                            <h3>Progress</h3>
                            <div class="progress-bar-container">
                                <div class="progress-bar" style="width: \(String(format: "%.0f", Double(data.stepsRecorded + data.stepsSkipped) / Double(max(1, data.totalSteps)) * 100))%"></div>
                            </div>
                            <div class="metrics-grid">
                                <div class="metric-box small">
                                    <div class="metric-title">Total Steps</div>
                                    <div class="metric-value">\(data.totalSteps)</div>
                                </div>
                                <div class="metric-box small">
                                    <div class="metric-title">Recorded</div>
                                    <div class="metric-value good">\(data.stepsRecorded)</div>
                                </div>
                                <div class="metric-box small">
                                    <div class="metric-title">Skipped</div>
                                    <div class="metric-value warning">\(data.stepsSkipped)</div>
                                </div>
                                <div class="metric-box small">
                                    <div class="metric-title">Pending</div>
                                    <div class="metric-value">\(data.stepsPending)</div>
                                </div>
                            </div>
                        </div>
                        <div class="summary-section">
                            <h3>Variance Analysis</h3>
                            <div class="metrics-grid">
                                <div class="metric-box \(varianceClass(data.avgSABPVariance, threshold: 50))">
                                    <div class="metric-title">Avg SABP Variance</div>
                                    <div class="metric-value">\(String(format: "%+.0f", data.avgSABPVariance))</div>
                                    <div class="metric-unit">kPa</div>
                                </div>
                                <div class="metric-box \(varianceClass(data.maxSABPVariance, threshold: 100))">
                                    <div class="metric-title">Max SABP Variance</div>
                                    <div class="metric-value">\(String(format: "%.0f", data.maxSABPVariance))</div>
                                    <div class="metric-unit">kPa</div>
                                </div>
                                <div class="metric-box \(varianceClass(data.avgBackfillVariance * 100, threshold: 5))">
                                    <div class="metric-title">Avg Backfill Var</div>
                                    <div class="metric-value">\(String(format: "%+.3f", data.avgBackfillVariance))</div>
                                    <div class="metric-unit">m³</div>
                                </div>
                                <div class="metric-box \(varianceClass(data.maxBackfillVariance * 100, threshold: 10))">
                                    <div class="metric-title">Max Backfill Var</div>
                                    <div class="metric-value">\(String(format: "%.3f", data.maxBackfillVariance))</div>
                                    <div class="metric-unit">m³</div>
                                </div>
                            </div>
                        </div>
                    </div>
                </section>

                <!-- Variance Charts -->
                <section class="card">
                    <h2>Variance Analysis Charts</h2>
                    <div class="charts-grid">
                        <div class="chart-container">
                            <canvas id="chart-sabp"></canvas>
                            <div class="chart-tooltip" id="tooltip-sabp"></div>
                        </div>
                        <div class="chart-container">
                            <canvas id="chart-sabp-variance"></canvas>
                            <div class="chart-tooltip" id="tooltip-sabp-variance"></div>
                        </div>
                        <div class="chart-container">
                            <canvas id="chart-backfill"></canvas>
                            <div class="chart-tooltip" id="tooltip-backfill"></div>
                        </div>
                        <div class="chart-container">
                            <canvas id="chart-backfill-variance"></canvas>
                            <div class="chart-tooltip" id="tooltip-backfill-variance"></div>
                        </div>
                    </div>
                </section>

                <!-- Data Table -->
                <section class="card">
                    <h2>Step-by-Step Comparison</h2>
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
                                    <th class="sim-col" onclick="sortTable(2)">Sim SABP ⇅</th>
                                    <th class="act-col" onclick="sortTable(3)">Act SABP ⇅</th>
                                    <th class="var-col" onclick="sortTable(4)">Var (kPa) ⇅</th>
                                    <th class="sim-col" onclick="sortTable(5)">Sim BF ⇅</th>
                                    <th class="act-col" onclick="sortTable(6)">Act BF ⇅</th>
                                    <th class="var-col" onclick="sortTable(7)">Var (%) ⇅</th>
                                    <th onclick="sortTable(8)">Float ⇅</th>
                                    <th onclick="sortTable(9)">Status ⇅</th>
                                </tr>
                            </thead>
                            <tbody>
                                \(generateTableRows(data.steps))
                            </tbody>
                        </table>
                    </div>
                    <div class="table-legend">
                        <span class="legend-sim">■ Simulated</span>
                        <span class="legend-act">■ Actual</span>
                        <span class="legend-var">■ Variance</span>
                    </div>
                </section>
            </main>

            <footer>
                <p>Generated by Josh Well Control • \(dateStr)</p>
            </footer>

            <script>
                const steps = \(stepsJSON);
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
            --sim-color: #2196f3;
            --act-color: #4caf50;
            --var-color: #9c27b0;
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
            margin: 8px 0;
        }

        .info-grid, .params-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 12px;
        }

        .info-item, .param-item { display: flex; gap: 8px; }
        .label { color: var(--text-light); font-size: 0.85rem; }
        .value { font-weight: 500; }

        .status-completed { color: var(--safe-color); }
        .status-in-progress { color: var(--warning-color); }
        .status-cancelled { color: var(--danger-color); }

        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
        }

        .summary-section { background: var(--bg-color); padding: 16px; border-radius: 6px; }

        .progress-bar-container {
            width: 100%;
            height: 8px;
            background: #ddd;
            border-radius: 4px;
            margin-bottom: 12px;
            overflow: hidden;
        }

        .progress-bar {
            height: 100%;
            background: var(--safe-color);
            border-radius: 4px;
            transition: width 0.3s;
        }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(100px, 1fr));
            gap: 8px;
        }

        .metric-box {
            background: white;
            border-radius: 6px;
            padding: 12px;
            text-align: center;
        }

        .metric-box.small { padding: 8px; }
        .metric-title { font-size: 0.7rem; color: var(--text-light); margin-bottom: 4px; }
        .metric-value { font-size: 1.2rem; font-weight: 700; }
        .metric-box.small .metric-value { font-size: 1rem; }
        .metric-value.good { color: var(--safe-color); }
        .metric-value.warning { color: var(--warning-color); }
        .metric-value.danger { color: var(--danger-color); }
        .metric-unit { font-size: 0.65rem; color: var(--text-light); }

        .metric-box.good-box .metric-value { color: var(--safe-color); }
        .metric-box.warning-box .metric-value { color: var(--warning-color); }
        .metric-box.danger-box .metric-value { color: var(--danger-color); }

        .charts-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 16px;
        }

        @media (max-width: 768px) {
            .charts-grid { grid-template-columns: 1fr; }
        }

        .chart-container {
            background: var(--bg-color);
            border-radius: 6px;
            padding: 12px;
            height: 250px;
            position: relative;
        }

        .chart-container canvas { width: 100% !important; height: 100% !important; }

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

        .chart-tooltip.visible { opacity: 1; }

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

        .table-wrapper { overflow-x: auto; max-height: 500px; overflow-y: auto; }

        table { width: 100%; border-collapse: collapse; font-size: 0.8rem; }
        thead { position: sticky; top: 0; z-index: 10; }

        th {
            background: var(--brand-color);
            color: white;
            padding: 10px 8px;
            text-align: right;
            cursor: pointer;
            white-space: nowrap;
        }

        th:hover { background: #4795ab; }
        th.sim-col { background: var(--sim-color); }
        th.act-col { background: var(--act-color); }
        th.var-col { background: var(--var-color); }

        td {
            padding: 8px;
            text-align: right;
            border-bottom: 1px solid var(--border-color);
        }

        tr:nth-child(even) { background: var(--bg-color); }
        tr:hover { background: #e3f2fd; }
        tr.skipped { opacity: 0.5; background: #fff3e0; }
        tr.recorded { background: #e8f5e9; }

        .var-positive { color: var(--danger-color); }
        .var-negative { color: var(--safe-color); }
        .var-neutral { color: var(--text-light); }

        .table-legend {
            margin-top: 8px;
            font-size: 0.7rem;
            color: var(--text-light);
            display: flex;
            gap: 16px;
        }

        .legend-sim { color: var(--sim-color); }
        .legend-act { color: var(--act-color); }
        .legend-var { color: var(--var-color); }

        footer {
            text-align: center;
            padding: 20px;
            color: var(--text-light);
            font-size: 0.8rem;
        }

        @media print {
            header { position: static; }
            .table-controls { display: none; }
            .card { break-inside: avoid; }
        }
        """
    }

    // MARK: - JavaScript

    private func generateJavaScript() -> String {
        return """
        document.addEventListener('DOMContentLoaded', function() {
            initCharts();
        });

        function initCharts() {
            const depths = steps.map(s => s.bitMD);
            const simSABP = steps.map(s => s.simSABP);
            const actSABP = steps.map(s => s.actSABP);
            const sabpVar = steps.map(s => s.sabpVar);
            const simBF = steps.map(s => s.simBF);
            const actBF = steps.map(s => s.actBF);
            const bfVar = steps.map(s => s.bfVarPct);

            createChart('chart-sabp', 'SABP: Simulated vs Actual', depths, [
                { data: simSABP, label: 'Simulated', color: '#2196f3', hasNull: false },
                { data: actSABP, label: 'Actual', color: '#4caf50', hasNull: true }
            ]);

            createChart('chart-sabp-variance', 'SABP Variance (kPa)', depths, [
                { data: sabpVar, label: 'Variance', color: '#9c27b0', hasNull: true, isVariance: true }
            ]);

            createChart('chart-backfill', 'Backfill: Simulated vs Actual', depths, [
                { data: simBF, label: 'Simulated', color: '#2196f3', hasNull: false },
                { data: actBF, label: 'Actual', color: '#4caf50', hasNull: true }
            ]);

            createChart('chart-backfill-variance', 'Backfill Variance (%)', depths, [
                { data: bfVar, label: 'Variance', color: '#9c27b0', hasNull: true, isVariance: true }
            ]);
        }

        function createChart(canvasId, title, xData, datasets) {
            const canvas = document.getElementById(canvasId);
            if (!canvas) return null;
            const ctx = canvas.getContext('2d');
            if (!ctx) return null;

            const rect = canvas.parentElement.getBoundingClientRect();
            if (rect.width > 50 && rect.height > 50) {
                canvas.width = rect.width - 24;
                canvas.height = rect.height - 24;
            }
            if (canvas.width < 100) canvas.width = 280;
            if (canvas.height < 100) canvas.height = 180;

            const w = canvas.width;
            const h = canvas.height;
            const margin = { top: 30, right: 20, bottom: 30, left: 55 };
            const plotW = w - margin.left - margin.right;
            const plotH = h - margin.top - margin.bottom;

            const xMin = Math.min(...xData);
            const xMax = Math.max(...xData);

            let yMin = Infinity, yMax = -Infinity;
            datasets.forEach(ds => {
                ds.data.forEach(v => {
                    if (v !== null) {
                        yMin = Math.min(yMin, v);
                        yMax = Math.max(yMax, v);
                    }
                });
            });

            // Handle variance charts (center on zero)
            if (datasets[0].isVariance) {
                const absMax = Math.max(Math.abs(yMin), Math.abs(yMax), 1);
                yMin = -absMax * 1.1;
                yMax = absMax * 1.1;
            } else {
                const yPad = (yMax - yMin) * 0.1 || 1;
                yMin -= yPad;
                yMax += yPad;
            }

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

            // Zero line for variance charts
            if (datasets[0].isVariance) {
                const zeroY = margin.top + ((yMax - 0) / (yMax - yMin)) * plotH;
                ctx.strokeStyle = '#999';
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(margin.left, zeroY);
                ctx.lineTo(w - margin.right, zeroY);
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
                ctx.fillText(val.toFixed(val >= 100 || val <= -100 ? 0 : 1), margin.left - 5, y + 3);
            }

            // X labels
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
                let started = false;
                xData.forEach((x, i) => {
                    const val = ds.data[i];
                    if (val === null) {
                        started = false;
                        return;
                    }
                    const px = margin.left + ((xMax - x) / (xMax - xMin)) * plotW;
                    const py = margin.top + ((yMax - val) / (yMax - yMin)) * plotH;
                    if (!started) {
                        ctx.moveTo(px, py);
                        started = true;
                    } else {
                        ctx.lineTo(px, py);
                    }
                });
                ctx.stroke();
            });

            // Legend
            let legendX = margin.left;
            datasets.forEach(ds => {
                ctx.fillStyle = ds.color;
                ctx.fillRect(legendX, margin.top - 15, 12, 3);
                ctx.fillStyle = '#666';
                ctx.font = '8px -apple-system, sans-serif';
                ctx.textAlign = 'left';
                ctx.fillText(ds.label, legendX + 15, margin.top - 12);
                legendX += ds.label.length * 5 + 35;
            });
        }

        // Table functionality
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
            a.download = 'trip_record_comparison.csv';
            a.click();
            URL.revokeObjectURL(url);
        }
        """
    }

    // MARK: - Helpers

    private func escapeHTML(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func varianceClass(_ value: Double, threshold: Double) -> String {
        let absVal = abs(value)
        if absVal <= threshold / 2 { return "good-box" }
        if absVal <= threshold { return "warning-box" }
        return "danger-box"
    }

    private func stepsToJSON(_ steps: [ComparisonReportData.StepData]) -> String {
        var json = "["
        for (i, step) in steps.enumerated() {
            if i > 0 { json += "," }
            json += """
            {
                "bitMD": \(step.bitMD_m),
                "bitTVD": \(step.bitTVD_m),
                "simSABP": \(step.simSABP_kPa),
                "actSABP": \(step.actualSABP_kPa.map { String($0) } ?? "null"),
                "sabpVar": \(step.sabpVariance_kPa.map { String($0) } ?? "null"),
                "simBF": \(step.simBackfill_m3),
                "actBF": \(step.actualBackfill_m3.map { String($0) } ?? "null"),
                "bfVarPct": \(step.backfillVariancePercent.map { String($0) } ?? "null"),
                "status": "\(step.status)",
                "skipped": \(step.skipped)
            }
            """
        }
        json += "]"
        return json
    }

    private func generateTableRows(_ steps: [ComparisonReportData.StepData]) -> String {
        var html = ""
        for step in steps {
            let rowClass: String
            if step.skipped {
                rowClass = "skipped"
            } else if step.actualSABP_kPa != nil || step.actualBackfill_m3 != nil {
                rowClass = "recorded"
            } else {
                rowClass = ""
            }

            let varianceClass: (Double?) -> String = { val in
                guard let v = val else { return "var-neutral" }
                if abs(v) < 1 { return "var-neutral" }
                return v > 0 ? "var-positive" : "var-negative"
            }

            html += """
            <tr class="\(rowClass)">
                <td>\(String(format: "%.0f", step.bitMD_m))</td>
                <td>\(String(format: "%.0f", step.bitTVD_m))</td>
                <td>\(String(format: "%.0f", step.simSABP_kPa))</td>
                <td>\(step.actualSABP_kPa.map { String(format: "%.0f", $0) } ?? "--")</td>
                <td class="\(varianceClass(step.sabpVariance_kPa))">\(step.sabpVariance_kPa.map { String(format: "%+.0f", $0) } ?? "--")</td>
                <td>\(String(format: "%.3f", step.simBackfill_m3))</td>
                <td>\(step.actualBackfill_m3.map { String(format: "%.3f", $0) } ?? "--")</td>
                <td class="\(varianceClass(step.backfillVariancePercent))">\(step.backfillVariancePercent.map { String(format: "%+.1f", $0) } ?? "--")</td>
                <td>\(step.simFloatState)</td>
                <td>\(step.skipped ? "Skipped" : (step.actualSABP_kPa != nil ? "✓" : "○"))</td>
            </tr>
            """
        }
        return html
    }
}
