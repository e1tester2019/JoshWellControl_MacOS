//
//  LaunchScreenConfiguration.swift
//  Josh Well Control for Mac
//
//  Configuration and customization options for launch screen
//

import SwiftUI
import Combine

/// Configuration for launch screen appearance and behavior
struct LaunchScreenConfiguration {
    /// Minimum time to show launch screen (in seconds)
    var minimumDisplayTime: TimeInterval = 1.5
    
    /// Maximum time to show launch screen (timeout in seconds)
    var maximumDisplayTime: TimeInterval = 10.0
    
    /// Enable/disable launch screen (useful for debugging)
    var isEnabled: Bool = true
    
    /// Animation speed multiplier (1.0 = normal, 2.0 = double speed)
    var animationSpeedMultiplier: Double = 1.0
    
    /// Show version info
    var showVersionInfo: Bool = true
    
    /// Custom app name override
    var customAppName: String? = nil
    
    /// Custom tagline override
    var customTagline: String? = nil
    
    /// Enable debug mode (shows timing info)
    var debugMode: Bool = false
    
    static let `default` = LaunchScreenConfiguration()
    
    /// Fast configuration for development
    static let fast = LaunchScreenConfiguration(
        minimumDisplayTime: 0.3,
        animationSpeedMultiplier: 2.0
    )
    
    /// Disabled configuration for debugging
    static let disabled = LaunchScreenConfiguration(
        isEnabled: false
    )
}

// MARK: - Enhanced Launch Coordinator with Configuration

@MainActor
class ConfigurableAppLaunchCoordinator: ObservableObject {
    @Published var isLaunchComplete = false
    @Published var loadingMessage = "Initializing..."
    @Published var progress: Double = 0.0
    
    private let configuration: LaunchScreenConfiguration
    private var launchStartTime: Date?
    
    init(configuration: LaunchScreenConfiguration = .default) {
        self.configuration = configuration
    }
    
    /// Perform app launch sequence with configuration
    func performLaunchSequence() {
        launchStartTime = Date()
        
        // Skip if disabled
        guard configuration.isEnabled else {
            isLaunchComplete = true
            return
        }
        
        Task {
            let speedFactor = 1.0 / configuration.animationSpeedMultiplier
            
            // Phase 1: Initial setup
            await updateProgress(0.2, message: "Loading resources...", delay: 500 * speedFactor)
            
            // Phase 2: Database preparation
            await updateProgress(0.4, message: "Preparing data store...", delay: 400 * speedFactor)
            
            // Phase 3: Checking sync status
            await updateProgress(0.6, message: "Checking iCloud sync...", delay: 400 * speedFactor)
            
            // Phase 4: Loading preferences
            await updateProgress(0.8, message: "Loading preferences...", delay: 300 * speedFactor)
            
            // Phase 5: Final preparations
            await updateProgress(0.95, message: "Almost ready...", delay: 200 * speedFactor)
            
            // Ensure minimum display time
            if let startTime = launchStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                let remaining = configuration.minimumDisplayTime - elapsed
                if remaining > 0 {
                    try? await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
                }
            }
            
            // Complete
            await updateProgress(1.0, message: "Ready!", delay: 100)
            
            withAnimation(.easeOut(duration: 0.5)) {
                isLaunchComplete = true
            }
        }
    }
    
    private func updateProgress(_ value: Double, message: String, delay: TimeInterval) async {
        loadingMessage = message
        progress = value
        
        if configuration.debugMode {
            print("Launch: \(message) (\(Int(value * 100))%)")
        }
        
        try? await Task.sleep(for: .milliseconds(Int(delay)))
    }
}

// MARK: - Alternative Launch Screen Styles

/// Minimal launch screen variant
struct MinimalLaunchScreen: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.9
    
    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.15, blue: 0.2)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Simple icon
                Image(systemName: "drop.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(scale)
                
                Text("Josh Well Control")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(.cyan)
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 1.0
                scale = 1.0
            }
        }
    }
}

/// Professional launch screen with company branding
struct ProfessionalLaunchScreen: View {
    @State private var isAnimating = false
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            // Clean gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.05, blue: 0.1),
                    Color(red: 0.05, green: 0.1, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo area
                VStack(spacing: 20) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.8), .cyan.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 50))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .cyan.opacity(0.5), radius: 20, y: 10)
                    
                    // Title
                    VStack(spacing: 8) {
                        Text("Josh Well Control")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .cyan, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: isAnimating ? 200 : 0, height: 2)
                            .animation(.easeInOut(duration: 1).delay(0.3), value: isAnimating)
                        
                        Text("Wellbore Hydraulics Engineering")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                // Loading
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.cyan)
                        .scaleEffect(1.2)
                    
                    Text("Loading...")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 50)
                
                // Footer
                Text("Version 1.0")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 20)
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                opacity = 1.0
            }
            isAnimating = true
        }
    }
}

// MARK: - Preview

#Preview("Standard Launch") {
    LaunchScreenView()
        .frame(width: 900, height: 650)
}

#Preview("Minimal Launch") {
    MinimalLaunchScreen()
        .frame(width: 900, height: 650)
}

#Preview("Professional Launch") {
    ProfessionalLaunchScreen()
        .frame(width: 900, height: 650)
}
