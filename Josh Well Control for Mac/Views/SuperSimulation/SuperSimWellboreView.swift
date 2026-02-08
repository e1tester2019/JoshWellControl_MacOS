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
            // Three-column layout: Annulus | String | Annulus
            let gap: CGFloat = 8
            let colW = (size.width - 2 * gap) / 3
            let annLeft = CGRect(x: 0, y: 0, width: colW, height: size.height)
            let strRect = CGRect(x: colW + gap, y: 0, width: colW, height: size.height)
            let annRight = CGRect(x: 2 * (colW + gap), y: 0, width: colW, height: size.height)

            // Unified vertical scale by MD
            let maxPocketMD = state.layersPocket.map { $0.bottomMD }.max() ?? state.bitMD_m
            let globalMaxMD = max(state.bitMD_m, maxPocketMD)
            func yGlobal(_ md: Double) -> CGFloat {
                guard globalMaxMD > 0 else { return 0 }
                return CGFloat(md / globalMaxMD) * size.height
            }

            // Draw annulus (left & right) and string (center), above bit
            drawColumn(&ctx, layers: state.layersAnnulus, in: annLeft, bitMD: state.bitMD_m, yGlobal: yGlobal)
            drawColumn(&ctx, layers: state.layersString, in: strRect, bitMD: state.bitMD_m, yGlobal: yGlobal)
            drawColumn(&ctx, layers: state.layersAnnulus, in: annRight, bitMD: state.bitMD_m, yGlobal: yGlobal)

            // Pocket (below bit): draw full width
            for layer in state.layersPocket {
                let yTop = yGlobal(layer.topMD)
                let yBot = yGlobal(layer.bottomMD)
                let yMin = min(yTop, yBot)
                let col = fillColor(layer: layer)
                let top = floor(yMin)
                let bottom = ceil(max(yTop, yBot))
                var sub = CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))
                sub = sub.insetBy(dx: 0, dy: -0.25)
                ctx.fill(Path(sub), with: .color(col))
            }

            // Headers
            ctx.draw(Text("Annulus").font(.caption2), at: CGPoint(x: annLeft.midX, y: 12))
            ctx.draw(Text("String").font(.caption2), at: CGPoint(x: strRect.midX, y: 12))
            ctx.draw(Text("Annulus").font(.caption2), at: CGPoint(x: annRight.midX, y: 12))

            // Bit marker
            let yBit = yGlobal(state.bitMD_m)
            ctx.fill(Path(CGRect(x: 0, y: yBit - 0.5, width: size.width, height: 1)),
                     with: .color(.accentColor.opacity(0.9)))

            // Depth ticks
            let tickCount = 6
            for i in 0...tickCount {
                let md = Double(i) / Double(tickCount) * globalMaxMD
                let yy = yGlobal(md)
                ctx.fill(Path(CGRect(x: size.width - 10, y: yy - 0.5, width: 10, height: 1)),
                         with: .color(.secondary))
                ctx.draw(Text(String(format: "%.0f", md)).font(.system(size: 9)),
                         at: CGPoint(x: size.width - 12, y: yy - 6), anchor: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drawing Helpers

    private func drawColumn(
        _ ctx: inout GraphicsContext,
        layers: [TripLayerSnapshot],
        in rect: CGRect,
        bitMD: Double,
        yGlobal: (Double) -> CGFloat
    ) {
        for layer in layers where layer.bottomMD <= bitMD {
            let yTop = yGlobal(layer.topMD)
            let yBot = yGlobal(layer.bottomMD)
            let yMin = min(yTop, yBot)
            let col = fillColor(layer: layer)
            let top = floor(yMin)
            let bottom = ceil(max(yTop, yBot))
            var sub = CGRect(x: rect.minX, y: top, width: rect.width, height: max(1, bottom - top))
            sub = sub.insetBy(dx: 0, dy: -0.25)
            ctx.fill(Path(sub), with: .color(col))
        }
        ctx.stroke(Path(rect), with: .color(.black.opacity(0.8)), lineWidth: 1)
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
