//
//  PlatformAdaptiveContentView.swift
//  Josh Well Control for Mac
//
//  Platform-adaptive content view that selects optimal UI for each platform
//

import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
#endif

/// Main platform-adaptive content view that routes to platform-specific implementations
struct PlatformAdaptiveContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.updatedAt, order: .reverse) private var wells: [Well]

    var body: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            iPhoneOptimizedContentView()
        } else {
            iPadOptimizedContentView()
        }
        #elseif os(macOS)
        MacOSOptimizedContentView()
        #endif
    }
}

#Preview {
    PlatformAdaptiveContentView()
        .modelContainer(for: [Well.self, ProjectState.self])
}
