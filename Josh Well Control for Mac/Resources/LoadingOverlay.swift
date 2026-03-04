//
//  LoadingOverlay.swift
//  Josh Well Control for Mac
//
//  Reusable loading screen overlay with progress indication
//

import SwiftUI

struct LoadingOverlay: View {
    let isShowing: Bool
    let message: String
    let progress: Double?  // Optional progress (0.0 to 1.0), nil for indeterminate
    
    init(isShowing: Bool, message: String = "Loading...", progress: Double? = nil) {
        self.isShowing = isShowing
        self.message = message
        self.progress = progress
    }
    
    var body: some View {
        ZStack {
            if isShowing {
                // Semi-transparent background
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                // Loading card
                VStack(spacing: 20) {
                    // Icon or spinner
                    if let progress = progress {
                        // Determinate progress
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(
                                    Color.accentColor,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .frame(width: 80, height: 80)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.3), value: progress)
                            
                            Text("\(Int(progress * 100))%")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                    } else {
                        // Indeterminate spinner
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(2.0)
                            .frame(width: 80, height: 80)
                    }
                    
                    // Message
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        
                        if progress != nil {
                            Text("Please wait...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(40)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        #if os(macOS)
                        .fill(.regularMaterial)
                        #else
                        .fill(.ultraThinMaterial)
                        #endif
                        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                }
                .frame(minWidth: 300)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isShowing)
    }
}

// MARK: - View Extension

extension View {
    /// Apply a loading overlay to any view
    func loadingOverlay(
        isShowing: Bool,
        message: String = "Loading...",
        progress: Double? = nil
    ) -> some View {
        ZStack {
            self
            LoadingOverlay(isShowing: isShowing, message: message, progress: progress)
        }
    }
}

// MARK: - Previews

#Preview("Indeterminate") {
    Text("Content Behind Loading Screen")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .loadingOverlay(isShowing: true, message: "Running simulation...")
}

#Preview("With Progress") {
    Text("Content Behind Loading Screen")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .loadingOverlay(isShowing: true, message: "Processing trip-in...", progress: 0.65)
}

