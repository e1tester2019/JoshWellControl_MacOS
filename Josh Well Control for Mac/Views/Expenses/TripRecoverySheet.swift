//
//  TripRecoverySheet.swift
//  Josh Well Control for Mac
//
//  Sheet for recovering incomplete trips on app launch (iOS)
//

#if os(iOS)
import SwiftUI
import SwiftData

struct TripRecoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let persistedState: PersistedTripState
    let onResume: () -> Void
    let onDiscard: () -> Void

    @StateObject private var persistenceService = TripPersistenceService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Warning icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                    .padding(.top, 20)

                // Title
                Text("Incomplete Trip Found")
                    .font(.title2.bold())

                // Trip details
                VStack(alignment: .leading, spacing: 12) {
                    detailRow(icon: "clock", title: "Started", value: formattedStartTime)
                    detailRow(icon: "timer", title: "Duration", value: persistedState.formattedDuration)
                    detailRow(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "Points", value: "\(persistedState.routePointCount)")

                    if let distance = calculateDistance() {
                        detailRow(icon: "car.fill", title: "Distance", value: String(format: "%.1f km", distance))
                    }

                    if !persistedState.purpose.isEmpty {
                        detailRow(icon: "text.alignleft", title: "Purpose", value: persistedState.purpose)
                    }

                    if let destName = persistedState.destinationName {
                        detailRow(icon: "mappin", title: "Destination", value: destName)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Stale warning
                if persistenceService.isPersistedTripStale() {
                    HStack {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text("This trip is over 24 hours old")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // Resume button (only for active tracking)
                    if persistedState.trackingModeRaw == TripTrackingMode.activeTracking.rawValue {
                        Button {
                            onResume()
                            dismiss()
                        } label: {
                            Label("Resume Tracking", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                    }

                    // Save as-is button
                    Button {
                        saveIncompleteTrip()
                    } label: {
                        Label("Save Trip", systemImage: "checkmark.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }

                    // Discard button
                    Button(role: .destructive) {
                        onDiscard()
                        dismiss()
                    } label: {
                        Label("Discard Trip", systemImage: "trash")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundStyle(.red)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Trip Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: persistedState.startTime)
    }

    private func calculateDistance() -> Double? {
        let distance = persistenceService.calculatePersistedDistance()
        return distance > 0 ? distance : nil
    }

    private func saveIncompleteTrip() {
        // Load route points
        let routePoints = persistenceService.loadRoutePoints()

        // Create MileageLog
        let log = MileageLog()
        log.date = persistedState.startTime

        // Calculate distance from route points or use calculated distance
        if let calculatedDist = persistedState.calculatedDistanceMeters {
            log.distance = calculatedDist / 1000
        } else {
            log.distance = persistenceService.calculatePersistedDistance()
        }

        // Set tracking mode
        if let mode = TripTrackingMode(rawValue: persistedState.trackingModeRaw) {
            log.trackingMode = mode
        } else {
            log.trackingMode = .activeTracking
        }

        log.purpose = persistedState.purpose

        // Start location
        if let startLat = persistedState.startLatitude,
           let startLon = persistedState.startLongitude {
            log.startLatitude = startLat
            log.startLongitude = startLon
        } else if let firstPoint = routePoints.first {
            log.startLatitude = firstPoint.latitude
            log.startLongitude = firstPoint.longitude
        }
        log.startLocation = persistedState.startLocationName ?? ""

        // End location (from destination or last route point)
        if let destLat = persistedState.destinationLatitude,
           let destLon = persistedState.destinationLongitude {
            log.endLatitude = destLat
            log.endLongitude = destLon
            log.endLocation = persistedState.destinationName ?? ""
        } else if let lastPoint = routePoints.last {
            log.endLatitude = lastPoint.latitude
            log.endLongitude = lastPoint.longitude
        }

        // Duration
        log.tripStartTime = persistedState.startTime
        log.tripEndTime = persistedState.lastSavedAt
        log.duration = persistedState.lastSavedAt.timeIntervalSince(persistedState.startTime)

        // Route calculation data
        if let calcDist = persistedState.calculatedDistanceMeters {
            log.wasRouteCalculated = true
            log.calculatedDistance = calcDist / 1000
        }
        log.expectedTravelTime = persistedState.expectedTravelTime

        // Destination info
        log.destinationName = persistedState.destinationName
        log.destinationLatitude = persistedState.destinationLatitude
        log.destinationLongitude = persistedState.destinationLongitude
        log.destinationSourceRaw = persistedState.destinationSourceRaw

        // Save route points
        if !routePoints.isEmpty {
            var tripRoutePoints: [TripRoutePoint] = []
            for point in routePoints {
                let tripPoint = TripRoutePoint(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    timestamp: point.timestamp
                )
                tripPoint.speed = point.speed
                tripPoint.course = point.course
                tripPoint.altitude = point.altitude
                tripRoutePoints.append(tripPoint)
            }
            log.routePoints = tripRoutePoints
        }

        // TODO: Link client/well if IDs are stored
        // This would require querying the model context

        // Save to database
        modelContext.insert(log)
        try? modelContext.save()

        // Clear persisted state
        persistenceService.clearTripState()

        dismiss()
    }
}
#endif
