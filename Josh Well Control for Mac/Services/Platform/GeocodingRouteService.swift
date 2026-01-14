//
//  GeocodingRouteService.swift
//  Josh Well Control for Mac
//
//  Address search, geocoding, and route calculation service
//

import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - Supporting Types

/// Source of a resolved destination
enum DestinationSource: Codable, Equatable {
    case addressSearch(query: String)
    case well(wellID: UUID, padName: String)
    case client(clientID: UUID, companyName: String)
    case currentLocation
    case manual

    var displayName: String {
        switch self {
        case .addressSearch(let query):
            return "Search: \(query)"
        case .well(_, let padName):
            return "Well: \(padName)"
        case .client(_, let companyName):
            return "Client: \(companyName)"
        case .currentLocation:
            return "Current Location"
        case .manual:
            return "Manual Entry"
        }
    }
}

/// A resolved destination with coordinates
struct ResolvedDestination: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let source: DestinationSource

    var subtitle: String? {
        address ?? source.displayName
    }
}

/// Result from route calculation
struct RouteCalculationResult {
    let distance: CLLocationDistance  // meters
    let expectedTravelTime: TimeInterval  // seconds
    let startCoordinate: CLLocationCoordinate2D
    let endCoordinate: CLLocationCoordinate2D
    let polylinePoints: [CLLocationCoordinate2D]?

    var distanceKm: Double {
        distance / 1000
    }

    var formattedDistance: String {
        String(format: "%.1f km", distanceKm)
    }

    var formattedTravelTime: String {
        let hours = Int(expectedTravelTime) / 3600
        let minutes = (Int(expectedTravelTime) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
}

/// Errors from geocoding/routing operations
enum GeocodingRouteError: LocalizedError {
    case geocodingFailed(String)
    case noResults
    case routeNotFound
    case networkError
    case invalidAddress

    var errorDescription: String? {
        switch self {
        case .geocodingFailed(let reason):
            return "Could not find location: \(reason)"
        case .noResults:
            return "No results found for that address."
        case .routeNotFound:
            return "Could not calculate a driving route."
        case .networkError:
            return "Network error. Please check your connection."
        case .invalidAddress:
            return "Please enter a valid address."
        }
    }
}

// MARK: - Address Search Result

struct AddressSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion?

    init(title: String, subtitle: String, completion: MKLocalSearchCompletion? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.completion = completion
    }
}

// MARK: - GeocodingRouteService

/// Service for address search, geocoding, and route calculation
@MainActor
class GeocodingRouteService: NSObject, ObservableObject {
    static let shared = GeocodingRouteService()

    // MARK: - Published State
    @Published var searchResults: [AddressSearchResult] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String?

    // MARK: - Private Properties
    private let geocoder = CLGeocoder()
    private var searchCompleter: MKLocalSearchCompleter?
    private var searchDebounceTask: Task<Void, Never>?

    // Cache recent geocode results
    private var geocodeCache: [String: CLLocationCoordinate2D] = [:]
    private let maxCacheSize = 20

    // MARK: - Init
    private override init() {
        super.init()
        setupSearchCompleter()
    }

    private func setupSearchCompleter() {
        let completer = MKLocalSearchCompleter()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        // Focus on Canada/Alberta region for better local results
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 54.0, longitude: -115.0),
            span: MKCoordinateSpan(latitudeDelta: 15.0, longitudeDelta: 20.0)
        )
        self.searchCompleter = completer
    }

    // MARK: - Address Search (Autocomplete)

    /// Search for addresses with autocomplete (debounced)
    func searchAddresses(_ query: String) {
        searchDebounceTask?.cancel()

        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchError = nil

        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }

            searchCompleter?.queryFragment = query
        }
    }

    /// Clear search results
    func clearSearch() {
        searchResults = []
        isSearching = false
        searchError = nil
        searchCompleter?.queryFragment = ""
    }

    // MARK: - Geocoding

    /// Convert an address string to coordinates
    func geocodeAddress(_ address: String) async throws -> CLLocationCoordinate2D {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeocodingRouteError.invalidAddress
        }

        // Check cache first
        if let cached = geocodeCache[address] {
            return cached
        }

        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            guard let placemark = placemarks.first,
                  let location = placemark.location else {
                throw GeocodingRouteError.noResults
            }

            // Cache the result
            addToCache(address: address, coordinate: location.coordinate)

            return location.coordinate
        } catch let error as CLError {
            switch error.code {
            case .network:
                throw GeocodingRouteError.networkError
            case .geocodeFoundNoResult:
                throw GeocodingRouteError.noResults
            default:
                throw GeocodingRouteError.geocodingFailed(error.localizedDescription)
            }
        }
    }

    /// Geocode a search completion result
    func geocodeSearchResult(_ result: AddressSearchResult) async throws -> ResolvedDestination {
        guard let completion = result.completion else {
            // Manual result - try to geocode the title as an address
            let coordinate = try await geocodeAddress(result.title)
            return ResolvedDestination(
                name: result.title,
                coordinate: coordinate,
                address: result.subtitle,
                source: .addressSearch(query: result.title)
            )
        }

        // Use MKLocalSearch for more accurate geocoding of completions
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)

        do {
            let response = try await search.start()
            guard let item = response.mapItems.first else {
                throw GeocodingRouteError.noResults
            }

            let address = formatAddress(from: item.placemark)
            return ResolvedDestination(
                name: item.name ?? result.title,
                coordinate: item.placemark.coordinate,
                address: address,
                source: .addressSearch(query: result.title)
            )
        } catch {
            throw GeocodingRouteError.geocodingFailed(error.localizedDescription)
        }
    }

    /// Format a full address from a placemark
    private func formatAddress(from placemark: MKPlacemark) -> String {
        var parts: [String] = []

        if let street = placemark.thoroughfare {
            if let number = placemark.subThoroughfare {
                parts.append("\(number) \(street)")
            } else {
                parts.append(street)
            }
        }

        if let city = placemark.locality {
            parts.append(city)
        }

        if let province = placemark.administrativeArea {
            parts.append(province)
        }

        return parts.joined(separator: ", ")
    }

    // MARK: - Route Calculation

    /// Calculate driving route between two coordinates
    func calculateRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) async throws -> RouteCalculationResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)

        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else {
                throw GeocodingRouteError.routeNotFound
            }

            // Extract polyline points
            let polyline = route.polyline
            var points: [CLLocationCoordinate2D] = []
            let pointCount = polyline.pointCount
            let polylinePoints = polyline.points()
            for i in 0..<pointCount {
                points.append(polylinePoints[i].coordinate)
            }

            return RouteCalculationResult(
                distance: route.distance,
                expectedTravelTime: route.expectedTravelTime,
                startCoordinate: start,
                endCoordinate: end,
                polylinePoints: points
            )
        } catch let error as MKError {
            switch error.code {
            case .directionsNotFound:
                throw GeocodingRouteError.routeNotFound
            case .serverFailure:
                throw GeocodingRouteError.networkError
            default:
                throw GeocodingRouteError.routeNotFound
            }
        }
    }

    /// Calculate route from current location to a destination
    func calculateRouteFromCurrentLocation(
        currentLocation: CLLocation,
        to destination: ResolvedDestination
    ) async throws -> RouteCalculationResult {
        return try await calculateRoute(
            from: currentLocation.coordinate,
            to: destination.coordinate
        )
    }

    // MARK: - Reverse Geocoding

    /// Get address string from coordinates
    func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async throws -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else {
                return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
            }

            return formatAddress(from: MKPlacemark(placemark: placemark))
        } catch {
            // Fall back to coordinate string
            return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        }
    }

    // MARK: - Straight-Line Distance (Fallback)

    /// Calculate straight-line (haversine) distance as fallback
    func calculateStraightLineDistance(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        return startLocation.distance(from: endLocation)
    }

    // MARK: - Cache Management

    private func addToCache(address: String, coordinate: CLLocationCoordinate2D) {
        if geocodeCache.count >= maxCacheSize {
            // Remove oldest entry (simple FIFO)
            if let firstKey = geocodeCache.keys.first {
                geocodeCache.removeValue(forKey: firstKey)
            }
        }
        geocodeCache[address] = coordinate
    }

    func clearCache() {
        geocodeCache.removeAll()
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension GeocodingRouteService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.searchResults = completer.results.map { completion in
                AddressSearchResult(
                    title: completion.title,
                    subtitle: completion.subtitle,
                    completion: completion
                )
            }
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.searchError = error.localizedDescription
            self.isSearching = false
        }
    }
}
