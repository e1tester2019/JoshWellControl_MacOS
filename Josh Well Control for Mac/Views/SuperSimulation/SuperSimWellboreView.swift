//
//  SuperSimWellboreView.swift
//  Josh Well Control for Mac
//
//  Interactive Canvas-based wellbore fluid state viewer for Super Simulation.
//  Global slider scrubs through all operations to visualize fluid columns
//  in 3-column layout: Annulus | String | Annulus.
//

import SwiftUI

struct SuperSimWellboreView: View {
    @Bindable var viewModel: SuperSimViewModel

    @State private var isPlaying = false
    @State private var playbackTimer: Timer?
    @State private var playbackSpeed: Double = 10 // steps per second

    var body: some View {
        let total = viewModel.totalGlobalSteps
        if total > 0 {
            VStack(alignment: .leading, spacing: 4) {
                // Header
                HStack {
                    Text("Wellbore")
                        .font(.headline)
                    Spacer()
                    let globalIdx0 = Int(viewModel.globalStepSliderValue.rounded())
                    if let displayState = viewModel.wellboreDisplayAtGlobalStep(globalIdx0) {
                        Text(displayState.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Playback controls + slider
                HStack(spacing: 4) {
                    // Play/pause
                    Button {
                        togglePlayback(total: total)
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.borderless)
                    .help(isPlaying ? "Pause" : "Play")

                    // Step counter
                    Text("\(Int(viewModel.globalStepSliderValue.rounded()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)

                    Slider(
                        value: $viewModel.globalStepSliderValue,
                        in: 0...Double(max(0, total - 1)),
                        step: 1
                    )
                    .onChange(of: viewModel.globalStepSliderValue) {
                        // Stop playback if user manually drags to end
                        if isPlaying && Int(viewModel.globalStepSliderValue.rounded()) >= total - 1 {
                            stopPlayback()
                        }
                    }
                }

                // Speed control (only shown during playback or hovering)
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $playbackSpeed, in: 1...60, step: 1)
                        .frame(width: 80)
                        .onChange(of: playbackSpeed) {
                            if isPlaying {
                                stopPlayback()
                                startPlayback(total: total)
                            }
                        }
                    Text("\(Int(playbackSpeed)) sps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40)
                }

                // Canvas
                let globalIdx = Int(viewModel.globalStepSliderValue.rounded())
                if let displayState = viewModel.wellboreDisplayAtGlobalStep(globalIdx) {
                    wellboreCanvas(displayState)
                } else {
                    ContentUnavailableView("No data for this step", systemImage: "exclamationmark.circle")
                        .frame(minHeight: 200)
                }
            }
            .onDisappear { stopPlayback() }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
                VStack(spacing: 6) {
                    Image(systemName: "circle.hexagonpath")
                        .foregroundStyle(.secondary)
                    Text("Run operations to see wellbore state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 200)
        }
    }

    // MARK: - Playback

    private func togglePlayback(total: Int) {
        if isPlaying {
            stopPlayback()
        } else {
            // If at end, restart from beginning
            if Int(viewModel.globalStepSliderValue.rounded()) >= total - 1 {
                viewModel.globalStepSliderValue = 0
            }
            startPlayback(total: total)
        }
    }

    private func startPlayback(total: Int) {
        isPlaying = true
        let interval = 1.0 / playbackSpeed
        playbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let current = Int(viewModel.globalStepSliderValue.rounded())
            if current < total - 1 {
                viewModel.globalStepSliderValue = Double(current + 1)
            } else {
                stopPlayback()
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Canvas

    private func wellboreCanvas(_ state: SuperSimViewModel.WellboreDisplayState) -> some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let margin: CGFloat = 30 // right margin for depth ticks

            // Wellbore proportions
            let wellW = w - margin
            let pipeRatio: CGFloat = 0.35 // pipe width as fraction of wellbore
            let pipeW = wellW * pipeRatio
            let pipeX = (wellW - pipeW) / 2 // centered

            // Depth scale
            let maxPocketMD = state.layersPocket.map { $0.bottomMD }.max() ?? state.bitMD_m
            let globalMaxMD = max(state.bitMD_m, maxPocketMD)
            func yMD(_ md: Double) -> CGFloat {
                guard globalMaxMD > 0 else { return 0 }
                return CGFloat(md / globalMaxMD) * h
            }

            let yBit = yMD(state.bitMD_m)

            // 1. Fill annulus layers (left + right gap, above bit)
            for layer in state.layersAnnulus {
                let yTop = floor(yMD(layer.topMD))
                let yBot = ceil(yMD(layer.bottomMD))
                let lh = max(1, yBot - yTop)
                let col = fillColor(layer: layer)
                // Left annulus
                ctx.fill(Path(CGRect(x: 0, y: yTop, width: pipeX, height: lh)), with: .color(col))
                // Right annulus
                ctx.fill(Path(CGRect(x: pipeX + pipeW, y: yTop, width: wellW - pipeX - pipeW, height: lh)), with: .color(col))
            }

            // 2. Fill string layers (center pipe, above bit)
            for layer in state.layersString {
                let yTop = floor(yMD(layer.topMD))
                let yBot = ceil(yMD(min(layer.bottomMD, state.bitMD_m)))
                let lh = max(1, yBot - yTop)
                let col = fillColor(layer: layer)
                ctx.fill(Path(CGRect(x: pipeX, y: yTop, width: pipeW, height: lh)), with: .color(col))
            }

            // 3. Pocket layers (full width below bit — open hole, no pipe)
            for layer in state.layersPocket {
                let yTop = floor(yMD(layer.topMD))
                let yBot = ceil(yMD(layer.bottomMD))
                let lh = max(1, yBot - yTop)
                let col = fillColor(layer: layer)
                ctx.fill(Path(CGRect(x: 0, y: yTop, width: wellW, height: lh)), with: .color(col))
            }

            // 4. Pipe walls (dark lines from surface to bit)
            if state.bitMD_m > 0 {
                let pipeLineW: CGFloat = 2
                ctx.fill(Path(CGRect(x: pipeX - pipeLineW / 2, y: 0, width: pipeLineW, height: yBit)),
                         with: .color(.black))
                ctx.fill(Path(CGRect(x: pipeX + pipeW - pipeLineW / 2, y: 0, width: pipeLineW, height: yBit)),
                         with: .color(.black))
            }

            // 5. Bit marker (horizontal line at bit depth)
            ctx.fill(Path(CGRect(x: pipeX - 4, y: yBit - 1.5, width: pipeW + 8, height: 3)),
                     with: .color(.accentColor.opacity(0.9)))

            // 6. Hole wall outline
            ctx.stroke(Path(CGRect(x: 0, y: 0, width: wellW, height: h)),
                       with: .color(.primary.opacity(0.6)), lineWidth: 1)

            // 7. Depth ticks
            let tickCount = 6
            for i in 0...tickCount {
                let md = Double(i) / Double(tickCount) * globalMaxMD
                let yy = yMD(md)
                ctx.fill(Path(CGRect(x: wellW, y: yy - 0.5, width: 6, height: 1)),
                         with: .color(.secondary))
                ctx.draw(Text(String(format: "%.0f", md)).font(.system(size: 9)),
                         at: CGPoint(x: wellW + 8, y: yy), anchor: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fillColor(layer: TripLayerSnapshot) -> Color {
        // Air gets distinct light blue
        if layer.rho_kgpm3 < 10 {
            return Color(red: 0.7, green: 0.85, blue: 1.0, opacity: 0.8)
        }
        // Explicit color from mud definition
        if let r = layer.colorR, let g = layer.colorG, let b = layer.colorB {
            return Color(red: r, green: g, blue: b, opacity: layer.colorA ?? 1.0)
        }
        // Density-based greyscale fallback
        let t = min(max((layer.rho_kgpm3 - 800) / 1200, 0), 1)
        return Color(white: 0.3 + 0.6 * t)
    }
}
