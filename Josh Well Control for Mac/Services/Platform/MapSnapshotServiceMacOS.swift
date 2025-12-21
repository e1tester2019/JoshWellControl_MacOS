//
//  MapSnapshotServiceMacOS.swift
//  Josh Well Control for Mac
//
//  Map snapshot generation service for PDF/HTML exports (macOS)
//

#if os(macOS)
import Foundation
import MapKit
import AppKit

/// Service for generating static map snapshots for export on macOS
/// Options for map snapshot generation - defined outside class to avoid actor isolation
struct MapSnapshotOptions {
    var size: CGSize = CGSize(width: 600, height: 400)
    var showRoute: Bool = true
    var routeColor: NSColor = .systemBlue
    var routeLineWidth: CGFloat = 3
    var startMarkerColor: NSColor = .systemGreen
    var endMarkerColor: NSColor = .systemRed
    var markerSize: CGFloat = 14
    var padding: Double = 0.3

    @MainActor static let standard = MapSnapshotOptions()
    @MainActor static let thumbnail = MapSnapshotOptions(size: CGSize(width: 200, height: 150), routeLineWidth: 2, markerSize: 10)
    @MainActor static let large = MapSnapshotOptions(size: CGSize(width: 800, height: 500), routeLineWidth: 4, markerSize: 18)
}

@MainActor
final class MapSnapshotServiceMacOS {
    static let shared = MapSnapshotServiceMacOS()

    private init() {}

    enum SnapshotError: LocalizedError {
        case missingCoordinates
        case snapshotFailed

        var errorDescription: String? {
            switch self {
            case .missingCoordinates:
                return "Trip does not have GPS coordinates."
            case .snapshotFailed:
                return "Failed to generate map snapshot."
            }
        }
    }

    // MARK: - Generate Snapshot

    func generateSnapshot(
        for mileageLog: MileageLog,
        options: MapSnapshotOptions? = nil
    ) async throws -> NSImage {
        let opts = options ?? MapSnapshotOptions.standard
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
            routeCoordinates = [start, end]
        }

        return try await generateSnapshot(
            startCoordinate: start,
            endCoordinate: end,
            routePoints: routeCoordinates,
            options: opts
        )
    }

    func generateSnapshot(
        startCoordinate: CLLocationCoordinate2D,
        endCoordinate: CLLocationCoordinate2D,
        routePoints: [CLLocationCoordinate2D] = [],
        options: MapSnapshotOptions? = nil
    ) async throws -> NSImage {
        let opts = options ?? MapSnapshotOptions.standard
        let allPoints = routePoints.isEmpty ? [startCoordinate, endCoordinate] : routePoints
        let region = calculateRegion(for: allPoints, padding: opts.padding)

        let snapshotOptions = MKMapSnapshotter.Options()
        snapshotOptions.region = region
        snapshotOptions.size = opts.size
        snapshotOptions.mapType = .standard
        snapshotOptions.showsBuildings = true

        let snapshotter = MKMapSnapshotter(options: snapshotOptions)
        let snapshot = try await snapshotter.start()

        let image = drawOverlays(
            on: snapshot,
            start: startCoordinate,
            end: endCoordinate,
            routePoints: allPoints,
            options: opts
        )

        return image
    }

    // MARK: - Generate JPEG Data

    func generateJPEGData(
        for mileageLog: MileageLog,
        options: MapSnapshotOptions? = nil,
        compressionFactor: CGFloat = 0.85
    ) async throws -> Data {
        let image = try await generateSnapshot(for: mileageLog, options: options ?? MapSnapshotOptions.standard)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor]) else {
            throw SnapshotError.snapshotFailed
        }
        return jpegData
    }

    // MARK: - Region Calculation

    private func calculateRegion(
        for coordinates: [CLLocationCoordinate2D],
        padding: Double
    ) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 53.5461, longitude: -113.4938),
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
        options: MapSnapshotOptions
    ) -> NSImage {
        let image = NSImage(size: options.size)
        image.lockFocus()

        // Draw the map snapshot
        snapshot.image.draw(in: NSRect(origin: .zero, size: options.size))

        // Draw route line
        if options.showRoute && routePoints.count >= 2 {
            let path = NSBezierPath()
            path.lineWidth = options.routeLineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            var isFirst = true
            for coord in routePoints {
                let point = snapshot.point(for: coord)
                if isFirst {
                    path.move(to: point)
                    isFirst = false
                } else {
                    path.line(to: point)
                }
            }

            options.routeColor.setStroke()
            path.stroke()
        }

        // Draw start marker (green)
        let startPoint = snapshot.point(for: start)
        drawMarker(at: startPoint, color: options.startMarkerColor, size: options.markerSize)

        // Draw end marker (red)
        let endPoint = snapshot.point(for: end)
        drawMarker(at: endPoint, color: options.endMarkerColor, size: options.markerSize)

        image.unlockFocus()
        return image
    }

    private func drawMarker(at point: CGPoint, color: NSColor, size: CGFloat) {
        let radius = size / 2

        // Outer circle (colored)
        let outerRect = NSRect(
            x: point.x - radius,
            y: point.y - radius,
            width: size,
            height: size
        )
        let outerPath = NSBezierPath(ovalIn: outerRect)
        color.setFill()
        outerPath.fill()

        // Inner circle (white)
        let innerRadius = radius * 0.5
        let innerRect = NSRect(
            x: point.x - innerRadius,
            y: point.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        )
        let innerPath = NSBezierPath(ovalIn: innerRect)
        NSColor.white.setFill()
        innerPath.fill()

        // Border
        NSColor.white.setStroke()
        outerPath.lineWidth = 1.5
        outerPath.stroke()
    }
}
#endif
