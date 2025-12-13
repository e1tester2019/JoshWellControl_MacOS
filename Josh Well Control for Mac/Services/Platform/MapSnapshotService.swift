//
//  MapSnapshotService.swift
//  Josh Well Control for Mac
//
//  Map snapshot generation service for PDF exports (iOS only)
//

#if os(iOS)
import Foundation
import MapKit
import UIKit

/// Service for generating static map snapshots for PDF export
final class MapSnapshotService: Sendable {
    static let shared = MapSnapshotService()

    private init() {}

    // MARK: - Snapshot Options

    struct SnapshotOptions: @unchecked Sendable {
        var size: CGSize = CGSize(width: 400, height: 300)
        var showRoute: Bool = true
        var routeColor: UIColor = .systemBlue
        var routeLineWidth: CGFloat = 3
        var startMarkerColor: UIColor = .systemGreen
        var endMarkerColor: UIColor = .systemRed
        var markerSize: CGFloat = 12
        var padding: Double = 0.3 // Percentage padding around route

        nonisolated init() {}

        static let standard = SnapshotOptions()

        static let thumbnail = SnapshotOptions(
            size: CGSize(width: 150, height: 100),
            routeLineWidth: 2,
            markerSize: 8
        )

        static let large = SnapshotOptions(
            size: CGSize(width: 600, height: 400),
            routeLineWidth: 4,
            markerSize: 16
        )

        nonisolated init(
            size: CGSize = CGSize(width: 400, height: 300),
            showRoute: Bool = true,
            routeColor: UIColor = .systemBlue,
            routeLineWidth: CGFloat = 3,
            startMarkerColor: UIColor = .systemGreen,
            endMarkerColor: UIColor = .systemRed,
            markerSize: CGFloat = 12,
            padding: Double = 0.3
        ) {
            self.size = size
            self.showRoute = showRoute
            self.routeColor = routeColor
            self.routeLineWidth = routeLineWidth
            self.startMarkerColor = startMarkerColor
            self.endMarkerColor = endMarkerColor
            self.markerSize = markerSize
            self.padding = padding
        }
    }

    enum SnapshotError: LocalizedError {
        case missingCoordinates
        case snapshotFailed
        case invalidRegion

        var errorDescription: String? {
            switch self {
            case .missingCoordinates:
                return "Trip does not have GPS coordinates."
            case .snapshotFailed:
                return "Failed to generate map snapshot."
            case .invalidRegion:
                return "Could not calculate map region."
            }
        }
    }

    // MARK: - Generate Snapshot

    /// Generate a map snapshot for a mileage log
    func generateSnapshot(
        for mileageLog: MileageLog,
        options: SnapshotOptions? = nil
    ) async throws -> UIImage {
        let options = options ?? SnapshotOptions()
        // Ensure we have coordinates
        guard let startLat = mileageLog.startLatitude,
              let startLon = mileageLog.startLongitude,
              let endLat = mileageLog.endLatitude,
              let endLon = mileageLog.endLongitude else {
            throw SnapshotError.missingCoordinates
        }

        let start = CLLocationCoordinate2D(latitude: startLat, longitude: startLon)
        let end = CLLocationCoordinate2D(latitude: endLat, longitude: endLon)

        // Gather route points if available
        let routeCoordinates: [CLLocationCoordinate2D]
        if let points = mileageLog.routePoints, !points.isEmpty {
            routeCoordinates = points
                .sorted { $0.timestamp < $1.timestamp }
                .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        } else {
            // Just use start and end
            routeCoordinates = [start, end]
        }

        // Calculate region to show all points
        let region = calculateRegion(for: routeCoordinates, padding: options.padding)

        // Configure snapshotter
        let snapshotOptions = MKMapSnapshotter.Options()
        snapshotOptions.region = region
        snapshotOptions.size = options.size
        snapshotOptions.mapType = .standard
        snapshotOptions.showsBuildings = true

        let snapshotter = MKMapSnapshotter(options: snapshotOptions)

        // Generate snapshot
        let snapshot = try await snapshotter.start()

        // Draw route and markers on snapshot
        let image = drawOverlays(
            on: snapshot,
            start: start,
            end: end,
            routePoints: routeCoordinates,
            options: options
        )

        return image
    }

    /// Generate a snapshot from raw coordinates
    func generateSnapshot(
        startCoordinate: CLLocationCoordinate2D,
        endCoordinate: CLLocationCoordinate2D,
        routePoints: [CLLocationCoordinate2D] = [],
        options: SnapshotOptions? = nil
    ) async throws -> UIImage {
        let options = options ?? SnapshotOptions()
        let allPoints = routePoints.isEmpty ? [startCoordinate, endCoordinate] : routePoints
        let region = calculateRegion(for: allPoints, padding: options.padding)

        let snapshotOptions = MKMapSnapshotter.Options()
        snapshotOptions.region = region
        snapshotOptions.size = options.size
        snapshotOptions.mapType = .standard

        let snapshotter = MKMapSnapshotter(options: snapshotOptions)
        let snapshot = try await snapshotter.start()

        let image = drawOverlays(
            on: snapshot,
            start: startCoordinate,
            end: endCoordinate,
            routePoints: allPoints,
            options: options
        )

        return image
    }

    // MARK: - Region Calculation

    private func calculateRegion(
        for coordinates: [CLLocationCoordinate2D],
        padding: Double
    ) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            // Default to a reasonable region if no coordinates
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 53.5461, longitude: -113.4938), // Edmonton
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2

        var latDelta = (maxLat - minLat) * (1 + padding)
        var lonDelta = (maxLon - minLon) * (1 + padding)

        // Ensure minimum span for close points
        latDelta = max(latDelta, 0.005)
        lonDelta = max(lonDelta, 0.005)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }

    // MARK: - Drawing

    private func drawOverlays(
        on snapshot: MKMapSnapshotter.Snapshot,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        routePoints: [CLLocationCoordinate2D],
        options: SnapshotOptions
    ) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(options.size, true, 0)
        defer { UIGraphicsEndImageContext() }

        // Draw the map snapshot
        snapshot.image.draw(at: .zero)

        guard let context = UIGraphicsGetCurrentContext() else {
            return snapshot.image
        }

        // Draw route line if we have points and option enabled
        if options.showRoute && routePoints.count >= 2 {
            context.setStrokeColor(options.routeColor.cgColor)
            context.setLineWidth(options.routeLineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            var isFirst = true
            for coord in routePoints {
                let point = snapshot.point(for: coord)
                if isFirst {
                    context.move(to: point)
                    isFirst = false
                } else {
                    context.addLine(to: point)
                }
            }
            context.strokePath()
        }

        // Draw start marker (green)
        let startPoint = snapshot.point(for: start)
        drawMarker(
            at: startPoint,
            color: options.startMarkerColor,
            size: options.markerSize,
            context: context
        )

        // Draw end marker (red)
        let endPoint = snapshot.point(for: end)
        drawMarker(
            at: endPoint,
            color: options.endMarkerColor,
            size: options.markerSize,
            context: context
        )

        return UIGraphicsGetImageFromCurrentImageContext() ?? snapshot.image
    }

    private func drawMarker(
        at point: CGPoint,
        color: UIColor,
        size: CGFloat,
        context: CGContext
    ) {
        let radius = size / 2

        // Outer circle (colored)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: size,
            height: size
        ))

        // Inner circle (white)
        let innerRadius = radius * 0.5
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(
            x: point.x - innerRadius,
            y: point.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        ))

        // Border
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: size,
            height: size
        ))
    }

    // MARK: - Save Snapshot to MileageLog

    /// Generate and save a snapshot to the mileage log's mapSnapshotData
    func saveSnapshot(
        to mileageLog: MileageLog,
        options: SnapshotOptions? = nil
    ) async throws {
        let options = options ?? SnapshotOptions()
        let image = try await generateSnapshot(for: mileageLog, options: options)

        // Convert to JPEG data for storage
        if let data = image.jpegData(compressionQuality: 0.8) {
            mileageLog.mapSnapshotData = data
        }
    }
}
#endif
