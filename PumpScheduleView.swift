import SwiftUI
import SwiftData
import Observation

struct PumpScheduleView: View {
    @Bindable var project: ProjectState
    @State private var vm = ViewModel()

    var body: some View {
        VStack(spacing: 12) {
            header
            Divider()
            visualization
        }
        .padding(12)
        .onAppear { vm.bootstrap(project: project) }
        .navigationTitle("Pump Schedule")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Pump staged parcels from final layers: annulus first, then string.")
                .foregroundStyle(.secondary)
            Spacer()
            if let stg = vm.currentStage(project: project) {
                Rectangle().fill(stg.color).frame(width: 16, height: 12).cornerRadius(2)
                Text(stg.name).font(.caption)
                Text("\(vm.stageDisplayIndex + 1)/\(vm.stages.count)").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No stages").font(.caption).foregroundStyle(.secondary)
            }
            Button(action: { vm.prevStageOrWrap() }) { Label("Previous", systemImage: "chevron.left") }
                .disabled(vm.stages.isEmpty)
            Slider(value: $vm.progress, in: 0...1)
                .frame(width: 260)
            Button(action: { vm.nextStageOrWrap() }) { Label("Next", systemImage: "chevron.right") }
                .disabled(vm.stages.isEmpty)
        }
    }

    private var visualization: some View {
        GroupBox("Well Snapshot") {
            GeometryReader { geo in
                Canvas { ctx, size in
                    let stage = vm.currentStage(project: project)
                    let totalV = stage?.totalVolume_m3 ?? 0
                    let pumpedV = max(0.0, min(vm.progress * max(totalV, 0), totalV))
                    let stacks = vm.stacksFor(project: project, stageIndex: vm.stageDisplayIndex, pumpedV: pumpedV)
                    let stringSegs: [Seg] = stacks.string.map { Seg(topMD: $0.top, bottomMD: $0.bottom, color: $0.color) }
                    let annulusSegs: [Seg] = stacks.annulus.map { Seg(topMD: $0.top, bottomMD: $0.bottom, color: $0.color) }

                    // Draw columns
                    let bitMD = maxDepth
                    let gap: CGFloat = 8
                    let colW = (size.width - 2*gap) / 3
                    let annLeft  = CGRect(x: 0, y: 0, width: colW, height: size.height)
                    let strRect  = CGRect(x: colW + gap, y: 0, width: colW, height: size.height)
                    let annRight = CGRect(x: 2*(colW + gap), y: 0, width: colW, height: size.height)

                    func yGlobal(_ md: Double) -> CGFloat {
                        guard bitMD > 0 else { return 0 }
                        return CGFloat(md / bitMD) * size.height
                    }

                    drawColumn(&ctx, layers: annulusSegs, in: annLeft, yGlobal: yGlobal)
                    drawColumn(&ctx, layers: stringSegs, in: strRect, yGlobal: yGlobal)
                    drawColumn(&ctx, layers: annulusSegs, in: annRight, yGlobal: yGlobal)

                    ctx.draw(Text("Annulus"), at: CGPoint(x: annLeft.midX,  y: 12))
                    ctx.draw(Text("String"),  at: CGPoint(x: strRect.midX,  y: 12))
                    ctx.draw(Text("Annulus"), at: CGPoint(x: annRight.midX, y: 12))

                    // Depth ticks (MD right, TVD left)
                    let tickCount = 6
                    for i in 0...tickCount {
                        let md = Double(i) / Double(tickCount) * bitMD
                        let yy = yGlobal(md)
                        let tvd = project.tvd(of: md)
                        ctx.fill(Path(CGRect(x: size.width - 10, y: yy - 0.5, width: 10, height: 1)), with: .color(.secondary))
                        ctx.draw(Text(String(format: "%.0f", md)), at: CGPoint(x: size.width - 12, y: yy - 6), anchor: .trailing)
                        ctx.fill(Path(CGRect(x: 0, y: yy - 0.5, width: 10, height: 1)), with: .color(.secondary))
                        ctx.draw(Text(String(format: "%.0f", tvd)), at: CGPoint(x: 12, y: yy - 6), anchor: .leading)
                    }
                }
            }
            .frame(minHeight: 260)
        }
    }

    private var maxDepth: Double {
        max(
            project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
            project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        )
    }

    // MARK: - Layer building
    private struct Layer { var topMD: Double; var bottomMD: Double; var color: Color }

    // MARK: - Stack for volume displacement model visualization
    private struct Seg {
        var topMD: Double
        var bottomMD: Double
        var color: Color
    }

    private func drawColumn(_ ctx: inout GraphicsContext, layers: [Seg], in rect: CGRect, yGlobal: (Double)->CGFloat) {
        for L in layers {
            let yTop = yGlobal(L.topMD)
            let yBot = yGlobal(L.bottomMD)
            let yMin = min(yTop, yBot)
            let h = max(1, abs(yBot - yTop))
            let sub = CGRect(x: rect.minX, y: yMin, width: rect.width, height: h)
            ctx.fill(Path(sub), with: .color(L.color))
        }
        ctx.stroke(Path(rect), with: .color(.black.opacity(0.8)), lineWidth: 1)
    }

    // MARK: - VM
    @Observable
    class ViewModel {
        enum Side { case annulus, string }
        struct Stage { let name: String; let color: Color; let totalVolume_m3: Double; let side: Side }
        var stages: [Stage] = []
        var stageIndex: Int = 0
        var progress: Double = 0
        var stageDisplayIndex: Int { min(max(stageIndex, 0), max(stages.count - 1, 0)) }
        func currentStage(project: ProjectState) -> Stage? { stages.isEmpty ? nil : stages[stageDisplayIndex] }
        func buildStages(project: ProjectState) {
            stages.removeAll()
            let bitMD = max(
                project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
                project.drillString.map { $0.bottomDepth_m }.max() ?? 0
            )
            let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)
            // Annulus first – order by shallow to deep (top MD ascending)
            let ann = project.finalLayers.filter { $0.placement == .annulus || $0.placement == .both }
                .sorted { min($0.topMD_m, $0.bottomMD_m) < min($1.topMD_m, $1.bottomMD_m) }
            for L in ann {
                let t = min(L.topMD_m, L.bottomMD_m)
                let b = max(L.topMD_m, L.bottomMD_m)
                let vol = geom.volumeInAnnulus_m3(t, b)
                let col = L.mud?.color ?? L.color
                stages.append(Stage(name: L.name, color: col, totalVolume_m3: vol, side: .annulus))
            }
            // Then string – order deepest to shallowest as per spec
            let str = project.finalLayers.filter { $0.placement == .string || $0.placement == .both }
                .sorted { min($0.topMD_m, $0.bottomMD_m) < min($1.topMD_m, $1.bottomMD_m) }
                .reversed()
            for L in str {
                let t = min(L.topMD_m, L.bottomMD_m)
                let b = max(L.topMD_m, L.bottomMD_m)
                let vol = geom.volumeInString_m3(t, b)
                let col = L.mud?.color ?? L.color
                stages.append(Stage(name: L.name, color: col, totalVolume_m3: vol, side: .string))
            }
            stageIndex = 0
            progress = 0
        }
        func bootstrap(project: ProjectState) { buildStages(project: project) }
        func nextStageOrWrap() {
            if progress >= 0.9999 { stageIndex = min(stageIndex + 1, max(stages.count - 1, 0)); progress = 0 }
            else { progress = 1 }
        }
        func prevStageOrWrap() {
            if progress <= 0.0001 { stageIndex = max(stageIndex - 1, 0); progress = 1 }
            else { progress = 0 }
        }

        struct Seg { var top: Double; var bottom: Double; var color: Color }

        private func merge(_ segs: [Seg]) -> [Seg] {
            let tol = 1e-6
            var out: [Seg] = []
            for s0 in segs.sorted(by: { $0.top < $1.top }) {
                var s = s0
                if var last = out.last {
                    if abs(last.bottom - s.top) <= tol && last.color == s.color {
                        out[out.count - 1].bottom = s.bottom
                    } else {
                        // Snap tiny overlaps/gaps
                        if abs(s.top - last.bottom) <= tol { s.top = last.bottom }
                        out.append(s)
                    }
                } else {
                    out.append(s)
                }
            }
            return out
        }

        private func takeFromBottom(_ segs: [Seg], length: Double, bitMD: Double, geom: ProjectGeometryService) -> (remaining: [Seg], parcels: [(volume_m3: Double, color: Color)]) {
            let tol = 1e-9
            var need = max(0, length)
            var parcels: [(Double, Color)] = []
            var remaining: [Seg] = []
            let ordered = segs.sorted { $0.top < $1.top }
            // Walk from bottom toward surface
            for s in ordered.reversed() {
                if need <= tol { remaining.insert(s, at: 0); continue }
                let span = max(0, s.bottom - s.top)
                if span <= tol { continue }
                let take = min(span, need)
                let sliceTop = max(0, s.bottom - take)
                let sliceBot = s.bottom
                let vol = geom.volumeInString_m3(sliceTop, sliceBot)
                parcels.append((vol, s.color))
                need -= take
                // Keep the upper part if any remains
                if span - take > tol {
                    remaining.insert(Seg(top: s.top, bottom: s.bottom - take, color: s.color), at: 0)
                }
            }
            // If we still need more, we've consumed everything; otherwise the earlier loop inserted untouched upper segments when need dropped to zero.
            return (merge(remaining), parcels)
        }

        private func injectAtSurfaceString(_ segs: [Seg], length: Double, color: Color, bitMD: Double) -> [Seg] {
            let L = max(0, length)
            guard L > 1e-9 else { return segs }
            // Shift down by L and clip to [0, bitMD]
            var shifted: [Seg] = []
            for s in segs {
                let nt = min(bitMD, s.top + L)
                let nb = min(bitMD, s.bottom + L)
                if nb > nt + 1e-9 { shifted.append(Seg(top: nt, bottom: nb, color: s.color)) }
            }
            // Insert new parcel at top
            let head = Seg(top: 0, bottom: min(bitMD, L), color: color)
            shifted.append(head)
            return merge(shifted)
        }

        private func annulusLengthFromBottom(forVolume vol: Double, bitMD: Double, geom: ProjectGeometryService) -> Double {
            let target = max(0, vol)
            if target <= 1e-12 { return 0 }
            var lo: Double = 0
            var hi: Double = bitMD
            // If full column volume is still less than target, clamp to bitMD
            let full = geom.volumeInAnnulus_m3(0.0, bitMD)
            if target >= full { return bitMD }
            for _ in 0..<64 {
                let mid = 0.5 * (lo + hi)
                let v = geom.volumeInAnnulus_m3(max(0, bitMD - mid), bitMD)
                if abs(v - target) <= 1e-9 * max(1.0, target) { return mid }
                if v < target { lo = mid } else { hi = mid }
            }
            return 0.5 * (lo + hi)
        }

        private func pushUpFromBitAnnulus(_ segs: [Seg], parcels: [(volume_m3: Double, color: Color)], bitMD: Double, geom: ProjectGeometryService) -> [Seg] {
            var current = segs
            guard !parcels.isEmpty else { return current }
            // Compute lengths for each parcel and total length
            var lengths: [Double] = parcels.map { annulusLengthFromBottom(forVolume: max(0, $0.volume_m3), bitMD: bitMD, geom: geom) }
            let totalL = lengths.reduce(0, +)
            if totalL <= 1e-9 { return current }
            // Shift existing stack up by totalL
            var shifted: [Seg] = []
            for s in current {
                let nt = max(0, s.top - totalL)
                let nb = max(0, s.bottom - totalL)
                if nb > nt + 1e-9 { shifted.append(Seg(top: nt, bottom: nb, color: s.color)) }
            }
            // Insert the batch at the bottom, contiguous from [bit-totalL, bit]
            var cursorTop = max(0, bitMD - totalL)
            for (i, p) in parcels.enumerated() {
                let L = max(0, lengths[i])
                guard L > 1e-9 else { continue }
                let seg = Seg(top: cursorTop, bottom: min(bitMD, cursorTop + L), color: p.color)
                shifted.append(seg)
                cursorTop += L
            }
            return merge(shifted)
        }

        // Recompute stacks from base for a given stage index and pumped volume
        func stacksFor(project: ProjectState, stageIndex: Int, pumpedV: Double) -> (string: [Seg], annulus: [Seg]) {
            let bitMD = max(
                project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
                project.drillString.map { $0.bottomDepth_m }.max() ?? 0
            )
            let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)
            let base = project.activeMud?.color ?? Color.gray.opacity(0.35)
            var string: [Seg] = [Seg(top: 0, bottom: bitMD, color: base)]
            var annulus: [Seg] = [Seg(top: 0, bottom: bitMD, color: base)]
            // Apply all previous stages fully
            for i in 0..<max(0, min(stageIndex, stages.count)) {
                let st = stages[i]
                let pV = max(0, st.totalVolume_m3)
                // Determine exiting parcels from string before shifting
                let Ls = geom.lengthForStringVolume_m(0.0, pV)
                let taken = takeFromBottom(string, length: Ls, bitMD: bitMD, geom: geom)
                string = injectAtSurfaceString(string, length: Ls, color: st.color, bitMD: bitMD)
                annulus = pushUpFromBitAnnulus(annulus, parcels: taken.parcels, bitMD: bitMD, geom: geom)
            }
            // Apply current stage partially
            if stages.indices.contains(stageIndex) {
                let st = stages[stageIndex]
                let pV = max(0, min(pumpedV, st.totalVolume_m3))
                let Ls = geom.lengthForStringVolume_m(0.0, pV)
                let taken = takeFromBottom(string, length: Ls, bitMD: bitMD, geom: geom)
                string = injectAtSurfaceString(string, length: Ls, color: st.color, bitMD: bitMD)
                annulus = pushUpFromBitAnnulus(annulus, parcels: taken.parcels, bitMD: bitMD, geom: geom)
            }
            return (string, annulus)
        }
    }
}
#if DEBUG
import SwiftData
struct PumpSchedule_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! ModelContainer(
            for: ProjectState.self,
                 FinalFluidLayer.self,
                 AnnulusSection.self,
                 DrillStringSection.self,
                 MudProperties.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let p = ProjectState()
        ctx.insert(p)
        // Geometry
        let a = AnnulusSection(name: "Casing", topDepth_m: 0, length_m: 800, innerDiameter_m: 0.244, outerDiameter_m: 0)
        let b = AnnulusSection(name: "OpenHole", topDepth_m: 800, length_m: 5200 - 800, innerDiameter_m: 0.159, outerDiameter_m: 0)
        a.project = p; b.project = p; p.annulus.append(contentsOf: [a,b]); ctx.insert(a); ctx.insert(b)
        let ds = DrillStringSection(name: "4\" DP", topDepth_m: 0, length_m: 5200, outerDiameter_m: 0.1016, innerDiameter_m: 0.0803)
        ds.project = p; p.drillString.append(ds); ctx.insert(ds)
        // Muds
        let active = MudProperties(name: "Active", density_kgm3: 1260, color: .yellow, project: p)
        active.isActive = true
        let heavy = MudProperties(name: "Heavy", density_kgm3: 1855, color: .red, project: p)
        p.muds.append(contentsOf: [active, heavy])
        ctx.insert(active); ctx.insert(heavy)
        // Final layers
        let ann1 = FinalFluidLayer(project: p, name: "Annulus ECD Mud", placement: .annulus, topMD_m: 800, bottomMD_m: 1500, density_kgm3: 1855, color: .red, mud: heavy)
        let ann2 = FinalFluidLayer(project: p, name: "Base", placement: .annulus, topMD_m: 0, bottomMD_m: 800, density_kgm3: 1260, color: .yellow, mud: active)
        let str1 = FinalFluidLayer(project: p, name: "Air", placement: .string, topMD_m: 0, bottomMD_m: 320, density_kgm3: 1, color: .white, mud: nil)
        let str2 = FinalFluidLayer(project: p, name: "Base", placement: .string, topMD_m: 320, bottomMD_m: 5200, density_kgm3: 1260, color: .yellow, mud: active)
        ctx.insert(ann1); ctx.insert(ann2); ctx.insert(str1); ctx.insert(str2)
        try? ctx.save()
        return PumpScheduleView(project: p).modelContainer(container).frame(width: 900, height: 520)
    }
}
#endif

