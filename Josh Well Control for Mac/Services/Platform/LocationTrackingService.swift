//
//  LocationTrackingService.swift
//  Josh Well Control for Mac
//
//  GPS trip tracking service for mileage logging (iOS only)
//

#if os(iOS)
import Foundation
import CoreLocation
import Combine

// MARK: - Supporting Types

struct ActiveTripData {
    let startTime: Date
    var currentDistance: CLLocationDistance = 0
    var pointCount: Int = 0
    var lastLocation: CLLocation?
}

struct TripResult {
    let startLocation: CLLocation?
    let endLocation: CLLocation?
    let routePoints: [CLLocation]
    let totalDistance: CLLocationDistance
    let duration: TimeInterval
    let startTime: Date?
    let endTime: Date?

    static var empty: TripResult {
        TripResult(
            startLocation: nil,
            endLocation: nil,
            routePoints: [],
            totalDistance: 0,
            duration: 0,
            startTime: nil,
            endTime: nil
        )
    }
}

enum BatteryOptimizationLevel {
    case high      // Best accuracy, most battery usage
    case balanced  // Good accuracy, moderate battery
    case low       // Basic accuracy, battery saver
}

enum LocationTrackingError: LocalizedError {
    case notAuthorized
    case locationUnavailable
    case timeout
    case serviceDisabled

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Location access not authorized. Please enable in Settings."
        case .locationUnavailable:
            return "Unable to determine your location."
        case .timeout:
            return "Location request timed out."
        case .serviceDisabled:
            return "Location services are disabled on this device."
        }
    }
}

// MARK: - LocationTrackingService

/// Service for GPS trip tracking with both continuous and point-to-point modes
@MainActor
class LocationTrackingService: NSObject, ObservableObject {
    static let shared = LocationTrackingService()

    // MARK: - Published State
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking: Bool = false
    @Published var currentLocation: CLLocation?
    @Published var trackingError: LocationTrackingError?
    @Published var activeTrip: ActiveTripData?

    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var routePoints: [CLLocation] = []
    private var tripStartTime: Date?

    /// Access current route points for live map display
    var currentRoutePoints: [CLLocation] {
        routePoints
    }

    // Battery optimization settings
    private var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private var distanceFilter: CLLocationDistance = 10 // meters

    // Single location capture continuation
    private var singleLocationContinuation: CheckedContinuation<CLLocation, Error>?

    // MARK: - Init
    private override init() {
        super.init()

        locationManager.delegate = self
        // Don't set activityType or pausesLocationUpdatesAutomatically here
        // as they can cause issues without proper background configuration

        // Check initial authorization status
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Authorization

    /// Request "when in use" location authorization
    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Request "always" authorization for background tracking
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    var isAuthorized: Bool {
        // Use cached status from delegate callback to avoid main thread blocking
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var canTrackInBackground: Bool {
        // Use cached status - iOS won't grant Always without UIBackgroundModes being set
        authorizationStatus == .authorizedAlways
    }

    // MARK: - Point-to-Point Mode

    /// Capture a single location (for point-to-point tracking)
    func captureCurrentLocation() async throws -> CLLocation {
        // Check authorization using cached status (non-blocking)
        guard isAuthorized else {
            throw LocationTrackingError.notAuthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.singleLocationContinuation = continuation
            self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
            self.locationManager.requestLocation()

            // Timeout after 30 seconds
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if self.singleLocationContinuation != nil {
                    self.singleLocationContinuation?.resume(throwing: LocationTrackingError.timeout)
                    self.singleLocationContinuation = nil
                }
            }
        }
    }

    /// Calculate distance between two locations
    func calculateDistance(from start: CLLocation, to end: CLLocation) -> CLLocationDistance {
        return start.distance(from: end)
    }

    // MARK: - Active Tracking Mode

    /// Start continuous GPS tracking for a trip
    func startActiveTracking() {
        guard !isTracking else { return }

        isTracking = true
        tripStartTime = Date()
        routePoints = []
        trackingError = nil

        locationManager.desiredAccuracy = desiredAccuracy
        locationManager.distanceFilter = distanceFilter

        // Start location updates
        locationManager.startUpdatingLocation()

        // Enable background updates if we have Always authorization
        if canTrackInBackground {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        }

        activeTrip = ActiveTripData(startTime: tripStartTime!)
    }

    /// Stop tracking and return the trip result
    func stopActiveTracking() -> TripResult {
        guard isTracking else { return TripResult.empty }

        isTracking = false

        // Disable background updates
        if canTrackInBackground {
            locationManager.allowsBackgroundLocationUpdates = false
        }

        locationManager.stopUpdatingLocation()

        let endTime = Date()
        let result = TripResult(
            startLocation: routePoints.first,
            endLocation: routePoints.last,
            routePoints: routePoints,
            totalDistance: calculateTotalDistance(),
            duration: endTime.timeIntervalSince(tripStartTime ?? endTime),
            startTime: tripStartTime,
            endTime: endTime
        )

        activeTrip = nil
        return result
    }

    // MARK: - Battery Optimization

    /// Set battery optimization level
    func setBatteryOptimization(level: BatteryOptimizationLevel) {
        switch level {
        case .high:
            desiredAccuracy = kCLLocationAccuracyBest
            distanceFilter = 5
        case .balanced:
            desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            distanceFilter = 20
        case .low:
            desiredAccuracy = kCLLocationAccuracyHundredMeters
            distanceFilter = 100
        }

        if isTracking {
            locationManager.desiredAccuracy = desiredAccuracy
            locationManager.distanceFilter = distanceFilter
        }
    }

    // MARK: - Private Helpers

    private func calculateTotalDistance() -> CLLocationDistance {
        guard routePoints.count > 1 else { return 0 }

        var total: CLLocationDistance = 0
        for i in 1..<routePoints.count {
            total += routePoints[i].distance(from: routePoints[i - 1])
        }
        return total
    }

    private func processLocation(_ location: CLLocation) {
        // Filter out inaccurate locations
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 100 else {
            return
        }

        currentLocation = location

        if isTracking {
            // Add to route if it's a meaningful change
            if let lastPoint = routePoints.last {
                let distance = location.distance(from: lastPoint)
                if distance >= distanceFilter {
                    routePoints.append(location)
                    updateActiveTrip()
                }
            } else {
                // First point
                routePoints.append(location)
                updateActiveTrip()
            }
        }
    }

    private func updateActiveTrip() {
        guard var trip = activeTrip else { return }
        trip.currentDistance = calculateTotalDistance()
        trip.pointCount = routePoints.count
        trip.lastLocation = routePoints.last
        activeTrip = trip
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTrackingService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            // Handle single location request
            if let continuation = self.singleLocationContinuation {
                continuation.resume(returning: location)
                self.singleLocationContinuation = nil
                return
            }

            // Process for active tracking
            self.processLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let continuation = self.singleLocationContinuation {
                continuation.resume(throwing: LocationTrackingError.locationUnavailable)
                self.singleLocationContinuation = nil
            }

            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    self.trackingError = .notAuthorized
                case .locationUnknown:
                    self.trackingError = .locationUnavailable
                default:
                    self.trackingError = .locationUnavailable
                }
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus

            // Clear error if now authorized
            if self.isAuthorized {
                self.trackingError = nil
            }
        }
    }
}
#endif
