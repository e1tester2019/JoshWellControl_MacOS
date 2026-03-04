//
//  AppLaunchCoordinator.swift
//  Josh Well Control for Mac
//
//  Coordinates app launch sequence with animated splash screen
//

import SwiftUI
import SwiftData
import Combine

/// Manages the transition from launch screen to main app
@MainActor
class AppLaunchCoordinator: ObservableObject {
    @Published var isLaunchComplete = false
    @Published var loadingMessage = "Initializing..."
    
    /// Simulate app initialization tasks
    func performLaunchSequence() {
        Task {
            // Phase 1: Initial setup
            loadingMessage = "Loading resources..."
            try? await Task.sleep(for: .milliseconds(500))
            
            // Phase 2: Database preparation
            loadingMessage = "Preparing data store..."
            try? await Task.sleep(for: .milliseconds(400))
            
            // Phase 3: Checking sync status
            loadingMessage = "Checking iCloud sync..."
            try? await Task.sleep(for: .milliseconds(400))
            
            // Phase 4: Final preparations
            loadingMessage = "Almost ready..."
            try? await Task.sleep(for: .milliseconds(300))
            
            // Complete launch
            withAnimation(.easeOut(duration: 0.5)) {
                isLaunchComplete = true
            }
        }
    }
}

/// Root view that shows launch screen then transitions to main app
struct AppLaunchWrapper: View {
    @StateObject private var coordinator = AppLaunchCoordinator()
    @State private var showMainApp = false
    
    var body: some View {
        ZStack {
            if showMainApp {
                // Main app content
                PlatformAdaptiveContentView()
                    .transition(.opacity)
            } else {
                // Launch screen
                LaunchScreenView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            coordinator.performLaunchSequence()
        }
        .onChange(of: coordinator.isLaunchComplete) { _, isComplete in
            if isComplete {
                // Delay slightly for smoother visual transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showMainApp = true
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Launch Sequence") {
    AppLaunchWrapper()
        .frame(width: 900, height: 650)
}
