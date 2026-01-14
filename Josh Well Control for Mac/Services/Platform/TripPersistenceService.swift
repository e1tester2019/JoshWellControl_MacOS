//
//  TripPersistenceService.swift
//  Josh Well Control for Mac
//
//  Persists in-progress trip state to UserDefaults for recovery
//

import Foundation
import CoreLocation
import Combine

// MARK: - Persisted Trip State

/// Codable struct for persisting trip state to UserDefaults
struct PersistedTripState: Codable {
    let tripID: UUID
    let startTime: Date
    let trackingModeRaw: String
    let purpose: String

    // Start location
    let startLatitude: Double?
    let startLongitude: Double?
    let startLocationName: String?

    // Destination (for route-based)
    let destinationLatitude: Double?
    let destinationLongitude: Double?
    let destinationName: String?
    let destinationSourceRaw: String?

    // Calculated route info
    let calculatedDistanceMeters: Double?
    let expectedTravelTime: TimeInterval?

    // Route points count (actual points stored separately)
    var routePointCount: Int

    // Client/Well links
    let clientID: UUID?
    let wellID: UUID?

    // Last save timestamp
    var lastSavedAt: Date

    init(
        tripID: UUID = UUID(),
        startTime: Date = Date(),
        trackingModeRaw: String,
        purpose: String = "",
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        startLocationName: String? = nil,
        destinationLatitude: Double? = nil,
        destinationLongitude: Double? = nil,
        destinationName: String? = nil,
        destinationSourceRaw: String? = nil,
        calculatedDistanceMeters: Double? = nil,
        expectedTravelTime: TimeInterval? = nil,
        routePointCount: Int = 0,
        clientID: UUID? = nil,
        wellID: UUID? = nil
    ) {
        self.tripID = tripID
        self.startTime = startTime
        self.trackingModeRaw = trackingModeRaw
        self.purpose = purpose
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.startLocationName = startLocationName
        self.destinationLatitude = destinationLatitude
        self.destinationLongitude = destinationLongitude
        self.destinationName = destinationName
        self.destinationSourceRaw = destinationSourceRaw
        self.calculatedDistanceMeters = calculatedDistanceMeters
        self.expectedTravelTime = expectedTravelTime
        self.routePointCount = routePointCount
        self.clientID = clientID
        self.wellID = wellID
        self.lastSavedAt = Date()
    }

    // Computed properties for display
    var formattedDuration: String {
        let duration = Date().timeIntervalSince(startTime)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }

    var hasDestination: Bool {
        destinationLatitude != nil && destinationLongitude != nil
    }

    var hasStartLocation: Bool {
        startLatitude != nil && startLongitude != nil
    }
}

// MARK: - Persisted Route Point

/// Lightweight route point for storage
struct PersistedRoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let altitude: Double?
    let speed: Double?
    let course: Double?

    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.timestamp = location.timestamp
        self.altitude = location.altitude
        self.speed = location.speed >= 0 ? location.speed : nil
        self.course = location.course >= 0 ? location.course : nil
    }

    func toCLLocation() -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude ?? 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            course: course ?? -1,
            speed: speed ?? -1,
            timestamp: timestamp
        )
    }
}

// MARK: - TripPersistenceService

/// Service for persisting in-progress trip state
@MainActor
class TripPersistenceService: ObservableObject {
    static let shared = TripPersistenceService()

    // MARK: - Published State
    @Published var hasIncompleteTrip: Bool = false
    @Published var incompleteTripState: PersistedTripState?

    // MARK: - Private Properties
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // UserDefaults keys
    private enum Keys {
        static let activeTripState = "ActiveTripState"
        static let activeTripRoutePoints = "ActiveTripRoutePoints"
    }

    // Save interval
    private var lastRoutePointSave: Date = .distantPast
    private let saveInterval: TimeInterval = 30 // seconds

    // MARK: - Init
    private init() {
        checkForIncompleteTrip()
    }

    // MARK: - Public Methods

    /// Check for incomplete trip on app launch
    func checkForIncompleteTrip() {
        if let state = loadTripState() {
            hasIncompleteTrip = true
            incompleteTripState = state
        } else {
            hasIncompleteTrip = false
            incompleteTripState = nil
        }
    }

    /// Save the initial trip state when tracking starts
    func saveTripState(_ state: PersistedTripState) {
        do {
            var mutableState = state
            mutableState.lastSavedAt = Date()
            let data = try encoder.encode(mutableState)
            defaults.set(data, forKey: Keys.activeTripState)
        } catch {
            print("Failed to save trip state: \(error)")
        }
    }

    /// Load the persisted trip state
    func loadTripState() -> PersistedTripState? {
        guard let data = defaults.data(forKey: Keys.activeTripState) else {
            return nil
        }

        do {
            return try decoder.decode(PersistedTripState.self, from: data)
        } catch {
            print("Failed to load trip state: \(error)")
            return nil
        }
    }

    /// Update the trip state (e.g., route point count)
    func updateTripState(routePointCount: Int) {
        guard var state = loadTripState() else { return }
        state.routePointCount = routePointCount
        state.lastSavedAt = Date()
        saveTripState(state)
    }

    /// Clear the persisted trip state after successful completion
    func clearTripState() {
        defaults.removeObject(forKey: Keys.activeTripState)
        defaults.removeObject(forKey: Keys.activeTripRoutePoints)
        hasIncompleteTrip = false
        incompleteTripState = nil
    }

    // MARK: - Route Points

    /// Save route points (batch save for efficiency)
    func saveRoutePoints(_ points: [PersistedRoutePoint]) {
        do {
            let data = try encoder.encode(points)
            defaults.set(data, forKey: Keys.activeTripRoutePoints)
        } catch {
            print("Failed to save route points: \(error)")
        }
    }

    /// Save route points from CLLocation array
    func saveRoutePoints(from locations: [CLLocation]) {
        let points = locations.map { PersistedRoutePoint(from: $0) }
        saveRoutePoints(points)
    }

    /// Load persisted route points
    func loadRoutePoints() -> [PersistedRoutePoint] {
        guard let data = defaults.data(forKey: Keys.activeTripRoutePoints) else {
            return []
        }

        do {
            return try decoder.decode([PersistedRoutePoint].self, from: data)
        } catch {
            print("Failed to load route points: \(error)")
            return []
        }
    }

    /// Load route points as CLLocation array
    func loadRoutePointsAsCLLocations() -> [CLLocation] {
        loadRoutePoints().map { $0.toCLLocation() }
    }

    /// Check if we should save route points (time-based throttle)
    func shouldSaveRoutePoints() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastRoutePointSave) >= saveInterval {
            lastRoutePointSave = now
            return true
        }
        return false
    }

    /// Force save route points (ignores throttle)
    func forceSaveRoutePoints(from locations: [CLLocation]) {
        lastRoutePointSave = Date()
        saveRoutePoints(from: locations)
        updateTripState(routePointCount: locations.count)
    }

    // MARK: - Recovery Helpers

    /// Get the distance traveled so far from persisted route points
    func calculatePersistedDistance() -> Double {
        let points = loadRoutePoints()
        guard points.count > 1 else { return 0 }

        var total: Double = 0
        for i in 1..<points.count {
            let start = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let end = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            total += start.distance(from: end)
        }
        return total / 1000 // Return in km
    }

    /// Check if the persisted trip is stale (older than 24 hours)
    func isPersistedTripStale() -> Bool {
        guard let state = loadTripState() else { return false }
        let age = Date().timeIntervalSince(state.startTime)
        return age > 24 * 60 * 60 // 24 hours
    }
}
