//
//  KillMudHTMLGenerator.swift
//  Josh Well Control for Mac
//
//  Generates an interactive HTML kill sheet training form.
//  Users enter the correct inputs for each formula; results auto-calculate.
//

import Foundation

struct KillMudReportData {
    let wellName: String
    let generatedDate: Date

    let bitMD_m: Double
    let bitTVD_m: Double
    let controlMD_m: Double
    let controlTVD_m: Double
    let heelMD_m: Double

    let baseMudDensity_kgpm3: Double
    let targetESD_kgpm3: Double
    let porePressureESD_kgpm3: Double
    let fracGradientESD_kgpm3: Double
    let crackFloat_kPa: Double

    let geometry: KillMudSolverService.SolverGeometry
    let results: [KillMudSolverService.SolverResult]

    let killPressure_kPa: Double
    let additionalPressure_kPa: Double
    let killMWDiff_kgpm3: Double
    let floatMW_kgpm3: Double
}

class KillMudHTMLGenerator {
    static let shared = KillMudHTMLGenerator()
    private init() {}

    func generateHTML(for d: KillMudReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        let dateStr = dateFormatter.string(from: d.generatedDate)
        let resultsRowsHTML = resultsRows(d)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Kill Mud Sheet \u{2014} \(esc(d.wellName))</title>
        <style>\(css)</style>
        </head>
        <body>
        <div class="container">

        <div class="header">
            <h1>Slug and Backfill Kill Sheet</h1>
            <div class="meta">\(esc(d.wellName)) \u{2014} \(dateStr)</div>
        </div>

        <!-- WELL DATA -->
        <div class="section">
            <h2>1. Well Data</h2>
            <p class="hint">Reference values from the well plan. Use these as inputs in the calculations below.</p>
            <div class="data-grid">
                <div class="data-item"><span class="data-label">Heel Depth</span><span class="data-val">\(f0(d.heelMD_m)) m</span></div>
                <div class="data-item"><span class="data-label">TVD (Heel)</span><span class="data-val">\(f0(d.bitTVD_m)) m</span></div>
                <div class="data-item"><span class="data-label">Active MW</span><span class="data-val">\(f1(d.baseMudDensity_kgpm3)) kg/m\u{00B3}</span></div>
                <div class="data-item"><span class="data-label">Target ESD (PP+O/K)</span><span class="data-val">\(f1(d.targetESD_kgpm3)) kg/m\u{00B3}</span></div>
                <div class="data-item"><span class="data-label">Bit Depth</span><span class="data-val">\(f0(d.bitMD_m)) m</span></div>
                <div class="data-item"><span class="data-label">Crack Float</span><span class="data-val">\(f0(d.crackFloat_kPa)) kPa</span></div>
                <div class="data-item"><span class="data-label">Pipe Capacity</span><span class="data-val">\(f4(d.geometry.pipeCapacity_m3_per_m)) m\u{00B3}/m</span></div>
                <div class="data-item"><span class="data-label">Csg Capacity</span><span class="data-val">\(f4(d.geometry.casingCapacity_m3_per_m)) m\u{00B3}/m</span></div>
                <div class="data-item"><span class="data-label">Pipe Displacement</span><span class="data-val">\(f2(d.geometry.steelDisplacement_m3)) m\u{00B3}</span></div>
                <div class="data-item"><span class="data-label">g (constant)</span><span class="data-val">0.00981</span></div>
            </div>
        </div>

        <!-- KILL PRESSURE -->
        <div class="section">
            <h2>2. Kill Pressure</h2>
            <div class="method-box">
                <p>Calculate the total pressure deficit and the pipe kill density needed to overcome it
                plus crack the float equipment.</p>
            </div>

            <div class="calc-step">
                <div class="step-header">A. MW Difference</div>
                <div class="step-formula">MW Diff = Target ESD \u{2212} Active MW</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="a1" class="in" placeholder="Target ESD" oninput="calcA()">
                    <span class="op">\u{2212}</span>
                    <input type="text" inputmode="decimal" id="a2" class="in" placeholder="Active MW" oninput="calcA()">
                    <span class="op">=</span>
                    <span class="result" id="rA">\u{2014}</span>
                    <span class="unit">kg/m\u{00B3}</span>
                </div>
            </div>

            <div class="calc-step">
                <div class="step-header">B. Kill Well Pressure</div>
                <div class="step-formula">Kill Well Press = MW Diff \u{00D7} TVD \u{00D7} g</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="b1" class="in" placeholder="MW Diff (A)" oninput="calcB()">
                    <span class="op">\u{00D7}</span>
                    <input type="text" inputmode="decimal" id="b2" class="in" placeholder="TVD" oninput="calcB()">
                    <span class="op">\u{00D7}</span>
                    <span class="const">0.00981</span>
                    <span class="op">=</span>
                    <span class="result" id="rB">\u{2014}</span>
                    <span class="unit">kPa</span>
                </div>
            </div>

            <div class="calc-step">
                <div class="step-header">C. Float MW</div>
                <div class="step-formula">Float MW = Crack Float \u{00F7} (TVD \u{00D7} g)</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="c1" class="in" placeholder="Crack Float" oninput="calcC()">
                    <span class="op">\u{00F7} (</span>
                    <input type="text" inputmode="decimal" id="c2" class="in" placeholder="TVD" oninput="calcC()">
                    <span class="op">\u{00D7}</span>
                    <span class="const">0.00981</span>
                    <span class="op">) =</span>
                    <span class="result" id="rC">\u{2014}</span>
                    <span class="unit">kg/m\u{00B3}</span>
                </div>
            </div>

            <div class="calc-step highlight">
                <div class="step-header">D. Kill String MW</div>
                <div class="step-formula">Kill String MW = Target ESD + MW Diff + Float MW</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="d1" class="in" placeholder="Target ESD" oninput="calcD()">
                    <span class="op">+</span>
                    <input type="text" inputmode="decimal" id="d2" class="in" placeholder="MW Diff (A)" oninput="calcD()">
                    <span class="op">+</span>
                    <input type="text" inputmode="decimal" id="d3" class="in" placeholder="Float MW (C)" oninput="calcD()">
                    <span class="op">=</span>
                    <span class="result" id="rD">\u{2014}</span>
                    <span class="unit">kg/m\u{00B3}</span>
                </div>
            </div>
        </div>

        <!-- SLUG CALCULATION -->
        <div class="section">
            <h2>3. Slug Calculation</h2>
            <div class="method-box">
                <p>Heavy kill string mud creates higher hydrostatic on the pipe side.
                The excess drains through the floats into the annulus, creating an air gap at surface.</p>
            </div>

            <div class="calc-step">
                <div class="step-header">E. Pit Gain</div>
                <div class="step-formula">Pit Gain = (Kill String MW \u{00F7} Target ESD \u{2212} 1) \u{00D7} Pipe Kill Volume</div>
                <div class="step-inputs">
                    <span class="op">(</span>
                    <input type="text" inputmode="decimal" id="e1" class="in" placeholder="KS MW (D)" oninput="calcE()">
                    <span class="op">\u{00F7}</span>
                    <input type="text" inputmode="decimal" id="e2" class="in" placeholder="Target ESD" oninput="calcE()">
                    <span class="op">\u{2212} 1 ) \u{00D7}</span>
                    <input type="text" inputmode="decimal" id="e3" class="in" placeholder="Pipe Kill Vol" oninput="calcE()">
                    <span class="op">=</span>
                    <span class="result" id="rE">\u{2014}</span>
                    <span class="unit">m\u{00B3}</span>
                </div>
            </div>

            <div class="calc-step">
                <div class="step-header">F. Drain Height</div>
                <div class="step-formula">Drain Height = Pit Gain \u{00F7} Pipe Capacity</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="f1" class="in" placeholder="Pit Gain (E)" oninput="calcF()">
                    <span class="op">\u{00F7}</span>
                    <input type="text" inputmode="decimal" id="f2" class="in" placeholder="Pipe Capacity" oninput="calcF()">
                    <span class="op">=</span>
                    <span class="result" id="rF">\u{2014}</span>
                    <span class="unit">m</span>
                </div>
            </div>

            <div class="calc-step highlight">
                <div class="step-header">G. Kill Depth</div>
                <div class="step-formula">Kill Depth = Heel Depth \u{2212} Drain Height</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="g1" class="in" placeholder="Heel Depth" oninput="calcG()">
                    <span class="op">\u{2212}</span>
                    <input type="text" inputmode="decimal" id="g2" class="in" placeholder="Drain Ht (F)" oninput="calcG()">
                    <span class="op">=</span>
                    <span class="result" id="rG">\u{2014}</span>
                    <span class="unit">m</span>
                </div>
                <div class="step-note">Length of pipe containing kill mud after slug drops</div>
            </div>
        </div>

        <!-- KILL STRING -->
        <div class="section">
            <h2>4. Kill String Pressure</h2>
            <div class="method-box">
                <p>The kill string mud that drains into the annulus creates a column of heavy fluid.
                Its height in the bore determines the pipe kill pressure contribution.</p>
            </div>

            <div class="calc-step">
                <div class="step-header">H. Kill String Volume</div>
                <div class="step-formula">KS Volume = Kill Depth \u{00D7} Pipe Capacity</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="h1" class="in" placeholder="Kill Depth (G)" oninput="calcH()">
                    <span class="op">\u{00D7}</span>
                    <input type="text" inputmode="decimal" id="h2" class="in" placeholder="Pipe Capacity" oninput="calcH()">
                    <span class="op">=</span>
                    <span class="result" id="rH">\u{2014}</span>
                    <span class="unit">m\u{00B3}</span>
                </div>
            </div>

            <div class="calc-step">
                <div class="step-header">I. Kill String Height</div>
                <div class="step-formula">KS Height = KS Volume \u{00F7} Csg Capacity</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="i1" class="in" placeholder="KS Vol (H)" oninput="calcI()">
                    <span class="op">\u{00F7}</span>
                    <input type="text" inputmode="decimal" id="i2" class="in" placeholder="Csg Capacity" oninput="calcI()">
                    <span class="op">=</span>
                    <span class="result" id="rI">\u{2014}</span>
                    <span class="unit">m</span>
                </div>
                <div class="step-note">Equivalent height of kill string fluid in the casing bore</div>
            </div>

            <div class="calc-step">
                <div class="step-header">J. Pipe Kill MW Diff</div>
                <div class="step-formula">Pipe MW Diff = Kill String MW \u{2212} Active MW</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="j1" class="in" placeholder="KS MW (D)" oninput="calcJ()">
                    <span class="op">\u{2212}</span>
                    <input type="text" inputmode="decimal" id="j2" class="in" placeholder="Active MW" oninput="calcJ()">
                    <span class="op">=</span>
                    <span class="result" id="rJ">\u{2014}</span>
                    <span class="unit">kg/m\u{00B3}</span>
                </div>
            </div>

            <div class="calc-step highlight">
                <div class="step-header">K. Pipe Kill Pressure</div>
                <div class="step-formula">Pipe Kill Press = KS Height \u{00D7} Pipe MW Diff \u{00D7} g</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="k1" class="in" placeholder="KS Height (I)" oninput="calcK()">
                    <span class="op">\u{00D7}</span>
                    <input type="text" inputmode="decimal" id="k2" class="in" placeholder="Pipe MW Diff (J)" oninput="calcK()">
                    <span class="op">\u{00D7}</span>
                    <span class="const">0.00981</span>
                    <span class="op">=</span>
                    <span class="result" id="rK">\u{2014}</span>
                    <span class="unit">kPa</span>
                </div>
            </div>
        </div>

        <!-- ANNULUS KILL -->
        <div class="section">
            <h2>5. Annulus Kill Density</h2>
            <div class="method-box">
                <p>The remaining pressure (total kill \u{2212} pipe kill contribution) must be provided by the
                annulus backfill over the displacement height.</p>
                <div class="formula">
                    Kill Ann MW = Remaining Press \u{00F7} (Disp Height \u{00D7} g) + Active MW
                </div>
            </div>

            <div class="calc-step">
                <div class="step-header">L. Remaining Pressure</div>
                <div class="step-formula">Remaining Press = Kill Well Press \u{2212} Pipe Kill Press</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="l1" class="in" placeholder="Kill Well (B)" oninput="calcL()">
                    <span class="op">\u{2212}</span>
                    <input type="text" inputmode="decimal" id="l2" class="in" placeholder="Pipe Kill (K)" oninput="calcL()">
                    <span class="op">=</span>
                    <span class="result" id="rL">\u{2014}</span>
                    <span class="unit">kPa</span>
                </div>
            </div>

            <div class="calc-step">
                <div class="step-header">M. Displacement Height</div>
                <div class="step-formula">Disp Height = Disp Volume \u{00F7} Csg Capacity</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="m1" class="in" placeholder="Disp Vol" oninput="calcM()">
                    <span class="op">\u{00F7}</span>
                    <input type="text" inputmode="decimal" id="m2" class="in" placeholder="Csg Capacity" oninput="calcM()">
                    <span class="op">=</span>
                    <span class="result" id="rM">\u{2014}</span>
                    <span class="unit">m</span>
                </div>
            </div>

            <div class="calc-step highlight">
                <div class="step-header">N. Kill Annulus MW</div>
                <div class="step-formula">Kill Ann MW = Remaining Press \u{00F7} (Disp Height \u{00D7} g) + Active MW</div>
                <div class="step-inputs">
                    <input type="text" inputmode="decimal" id="n1" class="in" placeholder="Remain (L)" oninput="calcN()">
                    <span class="op">\u{00F7} (</span>
                    <input type="text" inputmode="decimal" id="n2" class="in" placeholder="Disp Ht (M)" oninput="calcN()">
                    <span class="op">\u{00D7}</span>
                    <span class="const">0.00981</span>
                    <span class="op">) +</span>
                    <input type="text" inputmode="decimal" id="n3" class="in" placeholder="Active MW" oninput="calcN()">
                    <span class="op">=</span>
                    <span class="result" id="rN">\u{2014}</span>
                    <span class="unit">kg/m\u{00B3}</span>
                </div>
            </div>
        </div>

        <!-- TANK SETUP -->
        <div class="section">
            <h2>6. Tank Setup</h2>
            <div class="method-box">
                <p>Prepare two tanks with the calculated mud weights. Pump the kill string first,
                then the annulus backfill.</p>
            </div>
            <table class="options-table">
                <thead>
                    <tr><th>Tank</th><th>Mud Weight</th><th>Volume</th><th>Purpose</th></tr>
                </thead>
                <tbody>
                    <tr>
                        <td>Tank 1</td>
                        <td><strong>\(f0(d.geometry.pipeDensity_kgpm3))</strong> kg/m\u{00B3}</td>
                        <td>\(f1(d.geometry.killStringVolume_m3)) m\u{00B3}</td>
                        <td>Kill string \u{2192} returns to active</td>
                    </tr>
                    <tr>
                        <td>Tank 2</td>
                        <td><strong><span id="tankAnnMW">\u{2014}</span></strong> kg/m\u{00B3}</td>
                        <td>\(f1(d.geometry.steelDisplacement_m3 + d.geometry.slugDrop_m3)) m\u{00B3}</td>
                        <td>Annulus backfill (disp + slug drop)</td>
                    </tr>
                </tbody>
            </table>
        </div>

        <!-- APP RESULTS -->
        <div class="section">
            <h2>7. App Results (Reference)</h2>
            <p class="hint">Compare your hand calculations against the app\u{2019}s sim-validated results.</p>
            <div class="data-grid ref">
                <div class="data-item"><span class="data-label">Kill String MW</span><span class="data-val">\(f0(d.geometry.pipeDensity_kgpm3)) kg/m\u{00B3}</span></div>
                <div class="data-item"><span class="data-label">Kill String Vol</span><span class="data-val">\(f2(d.geometry.killStringVolume_m3)) m\u{00B3}</span></div>
                <div class="data-item"><span class="data-label">Slug Drop</span><span class="data-val">\(f2(d.geometry.slugDrop_m3)) m\u{00B3}</span></div>
                <div class="data-item"><span class="data-label">Drain Height</span><span class="data-val">\(f0(d.geometry.drainHeight_m)) m</span></div>
                <div class="data-item"><span class="data-label">Kill Depth</span><span class="data-val">\(f0(d.geometry.killDepth_m)) m</span></div>
                <div class="data-item"><span class="data-label">Kill Well Press</span><span class="data-val">\(f0(d.geometry.totalKillPressure_kPa)) kPa</span></div>
                <div class="data-item"><span class="data-label">Pipe Kill Press</span><span class="data-val">\(f0(d.geometry.pipeKillPressure_kPa)) kPa</span></div>
                <div class="data-item"><span class="data-label">Remaining Press</span><span class="data-val">\(f0(d.geometry.remainingPressure_kPa)) kPa</span></div>
                <div class="data-item"><span class="data-label">Disp Height</span><span class="data-val">\(f0(d.geometry.dispHeight_m)) m</span></div>
                <div class="data-item"><span class="data-label">KS Height (csg bore)</span><span class="data-val">\(f0(d.geometry.killStringHeight_m)) m</span></div>
            </div>
            <h3>Density Sweep Results</h3>
            <table class="options-table">
                <thead>
                    <tr>
                        <th>Ann \u{03C1} (kg/m\u{00B3})</th><th>Kill Depth (m)</th>
                        <th>Max ESD</th><th>Max SABP (kPa)</th><th>Status</th>
                    </tr>
                </thead>
                <tbody>\(resultsRowsHTML)</tbody>
            </table>
        </div>

        <!-- DEFINITIONS -->
        <div class="section">
            <h2>8. Definitions</h2>
            <table class="def-table">
                <tr><td><strong>ESD</strong></td><td>Equivalent Static Density \u{2014} effective density at a given depth</td></tr>
                <tr><td><strong>Target ESD</strong></td><td>Pore pressure + overkill \u{2014} the ESD to maintain at TVD</td></tr>
                <tr><td><strong>Crack Float</strong></td><td>Pressure to open float equipment so string drains to annulus</td></tr>
                <tr><td><strong>Kill String</strong></td><td>Heavy mud pumped into the drill string; excess U-tubes into annulus</td></tr>
                <tr><td><strong>Kill Depth</strong></td><td>Pipe length containing kill mud after slug drops (Heel \u{2212} drain height)</td></tr>
                <tr><td><strong>Steel Displacement</strong></td><td>Pipe wall volume (OD\u{2212}ID) removed during trip</td></tr>
                <tr><td><strong>Slug Drop</strong></td><td>Pipe kill mud that U-tubes from string to annulus</td></tr>
                <tr><td><strong>Remaining Press</strong></td><td>Kill well pressure not covered by the pipe kill contribution</td></tr>
                <tr><td><strong>Kill Ann MW</strong></td><td>Backfill density to provide remaining pressure over displacement height</td></tr>
                <tr><td><strong>SABP</strong></td><td>Surface Annular Back Pressure held to maintain target ESD</td></tr>
            </table>
        </div>

        <div class="footer">Generated by Josh Well Control for Mac</div>
        </div>

        <script>
        function v(id) { return parseFloat(document.getElementById(id).value); }
        function show(id, val, dp) {
            const el = document.getElementById(id);
            el.textContent = isNaN(val) ? '\\u2014' : val.toFixed(dp === undefined ? 1 : dp);
            el.classList.toggle('has-value', !isNaN(val));
        }
        const G = 0.00981;

        function calcA() { show('rA', v('a1') - v('a2'), 1); }
        function calcB() { show('rB', v('b1') * v('b2') * G, 0); }
        function calcC() { var d = v('c2') * G; show('rC', d > 0 ? v('c1') / d : NaN, 0); }
        function calcD() { show('rD', v('d1') + v('d2') + v('d3'), 0); }
        function calcE() {
            var ratio = v('e2') > 0 ? v('e1') / v('e2') - 1 : NaN;
            show('rE', ratio * v('e3'), 2);
        }
        function calcF() { var pc = v('f2'); show('rF', pc > 0 ? v('f1') / pc : NaN, 0); }
        function calcG() { show('rG', v('g1') - v('g2'), 0); }
        function calcH() { show('rH', v('h1') * v('h2'), 2); }
        function calcI() { var cc = v('i2'); show('rI', cc > 0 ? v('i1') / cc : NaN, 0); }
        function calcJ() { show('rJ', v('j1') - v('j2'), 0); }
        function calcK() { show('rK', v('k1') * v('k2') * G, 0); }
        function calcL() { show('rL', v('l1') - v('l2'), 0); }
        function calcM() { var cc = v('m2'); show('rM', cc > 0 ? v('m1') / cc : NaN, 0); }
        function calcN() {
            var d = v('n2') * G;
            var result = d > 0 ? v('n1') / d + v('n3') : NaN;
            show('rN', result, 0);
            // Update Tank 2 display
            var t2 = document.getElementById('tankAnnMW');
            if (t2) t2.textContent = isNaN(result) ? '\\u2014' : result.toFixed(0);
        }
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Helpers

    private func resultsRows(_ d: KillMudReportData) -> String {
        d.results.map { r in
            let status: String
            if !r.feasible { status = "\u{26A0}\u{FE0F} Exceeds" }
            else if r.relived { status = "\u{21A9}\u{FE0F} Re-lives" }
            else { status = "\u{2705} OK" }
            let esdClass = r.maxESDAtControl_kgpm3 > d.fracGradientESD_kgpm3 ? " class=\"warn\"" : ""
            return """
            <tr><td>\(f0(r.annulusKillDensity_kgpm3))</td>
            <td>\(f0(r.sustainedKillDepth_m))</td><td\(esdClass)>\(f1(r.maxESDAtControl_kgpm3))</td>
            <td>\(f0(r.maxSABP_kPa))</td><td>\(status)</td></tr>
            """
        }.joined(separator: "\n")
    }

    private func f0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func f2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func f4(_ v: Double) -> String { String(format: "%.4f", v) }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private var css: String {
        """
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #1a1a1a; color: #e0e0e0; line-height: 1.6; font-size: 14px;
        }
        .container { max-width: 900px; margin: 0 auto; padding: 20px; }

        .header { text-align: center; padding: 24px 0; border-bottom: 2px solid #333; margin-bottom: 24px; }
        .header h1 { font-size: 26px; color: #fff; }
        .header .meta { color: #888; font-size: 13px; }

        .section {
            background: #222; border-radius: 8px; padding: 20px;
            margin-bottom: 20px; border: 1px solid #333;
        }
        .section h2 { font-size: 18px; color: #4fc3f7; margin-bottom: 12px; border-bottom: 1px solid #333; padding-bottom: 6px; }
        .section h3 { color: #81d4fa; margin: 16px 0 8px; font-size: 15px; }

        .hint { color: #888; font-style: italic; margin-bottom: 12px; font-size: 13px; }

        .method-box {
            background: #2a2a2a; border-left: 3px solid #4fc3f7; border-radius: 6px;
            padding: 12px; margin-bottom: 16px;
        }
        .method-box p { margin-bottom: 6px; }
        .note-inline { color: #777; font-size: 12px; font-style: italic; }

        .data-grid {
            display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 6px;
        }
        .data-grid.ref { grid-template-columns: repeat(2, 1fr); }
        .data-item {
            display: flex; justify-content: space-between; padding: 4px 10px;
            background: #2a2a2a; border-radius: 4px;
        }
        .data-label { color: #aaa; font-size: 13px; }
        .data-val { font-family: 'SF Mono', monospace; font-weight: 600; color: #81d4fa; font-size: 13px; }

        .calc-step {
            background: #2a2a2a; border-radius: 6px; padding: 12px 14px;
            margin-bottom: 10px; border: 1px solid #333;
        }
        .calc-step.highlight { border-color: #4fc3f7; background: #1a2a3a; }
        .step-header { font-weight: 700; color: #fff; margin-bottom: 2px; }
        .step-formula { font-family: 'SF Mono', monospace; font-size: 12px; color: #888; margin-bottom: 8px; }
        .step-note { font-size: 12px; color: #888; margin-top: 6px; font-style: italic; }

        .step-inputs { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
        .step-inputs.three-line { flex-direction: column; align-items: stretch; gap: 6px; }
        .sub-row { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
        .sub-label { color: #888; font-size: 12px; min-width: 200px; }

        .in {
            width: 130px; padding: 5px 8px; border: 1px solid #555; border-radius: 4px;
            background: #111; color: #fff; font-family: 'SF Mono', monospace;
            font-size: 14px; text-align: right;
        }
        .in.sm { width: 90px; }
        .in:focus { border-color: #4fc3f7; outline: none; background: #1a1a2e; }
        .in::placeholder { color: #777; font-size: 12px; text-align: left; }

        .op { color: #888; font-size: 15px; flex-shrink: 0; }

        .result {
            font-family: 'SF Mono', monospace; font-weight: 700; font-size: 16px;
            color: #666; min-width: 80px; text-align: right;
        }
        .result.has-value { color: #4caf50; }
        .unit { color: #888; font-size: 12px; }

        .options-table { width: 100%; border-collapse: collapse; margin-top: 8px; font-size: 13px; }
        .options-table th {
            background: #333; color: #aaa; padding: 6px; text-align: center;
            font-weight: 500; font-size: 12px;
        }
        .options-table td {
            padding: 6px; text-align: center; border-bottom: 1px solid #333;
            font-family: 'SF Mono', monospace;
        }
        .options-table .warn { color: #ffb74d; }

        .def-table { width: 100%; border-collapse: collapse; }
        .def-table td { padding: 6px 10px; border-bottom: 1px solid #2a2a2a; font-size: 13px; vertical-align: top; }
        .def-table td:first-child { width: 130px; }

        .const {
            font-family: 'SF Mono', monospace; font-size: 13px; color: #81d4fa;
            background: #2a2a2a; padding: 3px 8px; border-radius: 4px; white-space: nowrap;
        }
        .formula {
            font-family: 'SF Mono', monospace; font-size: 13px; color: #ccc;
            margin-top: 8px; line-height: 1.8;
        }
        .zone-table-wrap { overflow-x: auto; margin: 8px 0; }
        .zone-table { width: 100%; border-collapse: collapse; font-size: 13px; }
        .zone-table th {
            background: #333; color: #aaa; padding: 6px 8px; text-align: center;
            font-weight: 500; font-size: 11px; white-space: nowrap;
        }
        .zone-table td {
            padding: 4px 6px; text-align: center; border-bottom: 1px solid #333;
            font-family: 'SF Mono', monospace; font-size: 13px;
        }
        .zone-table .in { width: 80px; font-size: 12px; text-align: center; }
        .zone-total td { font-weight: 600; border-top: 2px solid #555; }
        .zone-btn {
            padding: 4px 10px; background: #333; color: #aaa; border: 1px solid #555;
            border-radius: 4px; cursor: pointer; font-size: 12px;
        }
        .zone-btn:hover { background: #444; color: #fff; }
        .zone-btn.del { padding: 2px 8px; font-size: 14px; }

        .footer { text-align: center; color: #555; font-size: 12px; padding: 16px 0; border-top: 1px solid #333; }

        @media print {
            body { background: #fff; color: #000; }
            .section { border: 1px solid #ccc; break-inside: avoid; }
            .calc-step { background: #f5f5f5; border-color: #ccc; }
            .calc-step.highlight { background: #e3f2fd; border-color: #42a5f5; }
            .in { background: #fff; color: #000; border: 1px solid #999; }
            .data-val, .result.has-value { color: #0277bd; }
            .const { background: #e8e8e8; color: #0277bd; }
            .zone-table td { border: 1px solid #ccc; }
        }
        """
    }
}
