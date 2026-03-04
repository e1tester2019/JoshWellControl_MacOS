//
//  LaunchScreenView.swift
//  Josh Well Control for Mac
//
//  Animated launch screen with drilling rig visualization
//

import SwiftUI

struct LaunchScreenView: View {
    @State private var isAnimating = false
    @State private var rotationAngle: Double = 0
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.8
    @State private var pulseScale: Double = 1.0
    
    // Helper function for fluid particle colors (represents mud flow)
    private func fluidColor(for index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.6, green: 0.4, blue: 0.2), // Brown mud
            Color(red: 0.5, green: 0.3, blue: 0.1), // Darker brown
            Color(red: 0.7, green: 0.5, blue: 0.3), // Light brown
            Color(red: 0.4, green: 0.6, blue: 0.8), // Blue (water-based mud)
            Color(red: 0.3, green: 0.5, blue: 0.7), // Cyan tint
            Color(red: 0.8, green: 0.6, blue: 0.4), // Tan
        ]
        return colors[index % colors.count]
    }
    
    var body: some View {
        ZStack {
            // Background gradient - petroleum/industrial theme
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.1, blue: 0.15),
                    Color(red: 0.1, green: 0.15, blue: 0.2),
                    Color(red: 0.15, green: 0.2, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Animated background elements - representing wellbore depth markers
            ForEach(0..<20, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.02))
                    .frame(width: 100 + CGFloat(index * 50))
                    .offset(y: isAnimating ? -CGFloat(index * 30) : CGFloat(index * 30))
                    .animation(
                        .easeInOut(duration: 3)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: isAnimating
                    )
            }
            
            // Main content
            VStack(spacing: 40) {
                // App icon/logo area
                ZStack {
                    // Pulsing glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.cyan.opacity(0.3), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .scaleEffect(pulseScale)
                        .opacity(isAnimating ? 0.5 : 0)
                    
                    // Animated fluid flow particles (mud circulation from bottom to top)
                    ForEach(0..<12) { index in
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        fluidColor(for: index),
                                        fluidColor(for: index).opacity(0.3)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 8, height: 8)
                            .offset(
                                x: cos(Double(index) * .pi / 6) * 60,
                                y: isAnimating ? -120 : 60
                            )
                            .opacity(isAnimating ? 0 : 1)
                            .animation(
                                .easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.15),
                                value: isAnimating
                            )
                    }
                    
                    // Outer ring - representing wellbore/open hole
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.6), .cyan.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(rotationAngle))
                    
                    // Middle ring - representing casing string
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.orange.opacity(0.6), .yellow.opacity(0.4)],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-rotationAngle * 1.5))
                    
                    // Enhanced PDC drill bit (based on reference image)
                    ZStack {
                        // Bit body (steel cone)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 0.6, green: 0.65, blue: 0.7),  // Light gray steel
                                        Color(red: 0.4, green: 0.45, blue: 0.5)   // Darker steel
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 30
                                )
                            )
                            .frame(width: 60, height: 60)
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            }
                        
                        // PDC cutters arranged in 3 blades (spiral pattern like real PDC bits)
                        ForEach(0..<3) { blade in
                            ForEach(0..<4) { cutter in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.2, green: 0.25, blue: 0.3),  // Dark cutter
                                                Color(red: 0.1, green: 0.15, blue: 0.2)   // Very dark
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 6, height: 10)
                                    .offset(
                                        x: 0,
                                        y: -15 - Double(cutter) * 5
                                    )
                                    .rotationEffect(.degrees(Double(blade) * 120 + Double(cutter) * 10))
                            }
                        }
                        
                        // Bit body details (threads/connection rings)
                        ForEach(0..<8) { ring in
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.1),
                                    lineWidth: 0.5
                                )
                                .frame(
                                    width: 50 - CGFloat(ring) * 4,
                                    height: 50 - CGFloat(ring) * 4
                                )
                        }
                        
                        // Center nozzle/hub (where mud flows through)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 0.3, green: 0.35, blue: 0.4),
                                        Color(red: 0.15, green: 0.2, blue: 0.25)
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 8
                                )
                            )
                            .frame(width: 16, height: 16)
                            .overlay {
                                Circle()
                                    .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                            }
                        
                        // Cutting edge highlights (represent wear/cutting action)
                        ForEach(0..<6) { index in
                            Capsule()
                                .fill(Color.cyan.opacity(0.4))
                                .frame(width: 2, height: 20)
                                .offset(y: -20)
                                .rotationEffect(.degrees(Double(index) * 60))
                        }
                    }
                    .rotationEffect(.degrees(rotationAngle * 2))
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
                }
                .scaleEffect(scale)
                .opacity(opacity)
                
                // App title and tagline
                VStack(spacing: 12) {
                    Text("Josh Well Control")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .cyan.opacity(0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Managed Pressure Drilling & Wellbore Hydraulics")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .opacity(opacity)
                
                // Loading indicator
                VStack(spacing: 12) {
                    // Custom animated loading bar
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 200, height: 4)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: isAnimating ? 200 : 0, height: 4)
                            .animation(
                                .easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: false),
                                value: isAnimating
                            )
                    }
                    
                    Text("Initializing...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .opacity(opacity)
            }
            
            // Version/copyright footer
            VStack {
                Spacer()
                Text("Version 1.0 • © 2025")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 20)
            }
            .opacity(opacity)
        }
        .onAppear {
            // Animate elements on appear
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 1.0
                scale = 1.0
            }
            
            // Start continuous rotation animation
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            
            // Pulse animation for glow effect
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulseScale = 1.3
            }
            
            // Start background animation
            isAnimating = true
        }
    }
}

// MARK: - Preview

#Preview("Launch Screen") {
    LaunchScreenView()
        .frame(width: 800, height: 600)
}

#Preview("Launch Screen - Light") {
    LaunchScreenView()
        .frame(width: 800, height: 600)
        .preferredColorScheme(.light)
}

#Preview("Launch Screen - Dark") {
    LaunchScreenView()
        .frame(width: 800, height: 600)
        .preferredColorScheme(.dark)
}
