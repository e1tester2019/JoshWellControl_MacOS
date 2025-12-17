//
//  MileageTrackingViewIOS.swift
//  Josh Well Control for Mac
//
//  GPS-enabled mileage tracking views for iOS
//

#if os(iOS)
import SwiftUI
import SwiftData
import MapKit
import CoreLocation

// MARK: - Mileage Log View (iOS)

struct MileageLogViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MileageLog.date, order: .reverse) private var logs: [MileageLog]
    @StateObject private var locationService = LocationTrackingService.shared

    @State private var showingAddSheet = false
    @State private var showingActiveTracking = false
    @State private var showingPointToPoint = false
    @State private var selectedLog: MileageLog?

    var body: some View {
        NavigationStack {
            List {
                // Active Trip Section
                if locationService.isTracking, let trip = locationService.activeTrip {
                    Section {
                        ActiveTripBannerView(trip: trip) {
                            showingActiveTracking = true
                        }
                    } header: {
                        Text("Active Trip")
                    }
                }

                // Add Trip Section
                Section {
                    Button {
                        showingActiveTracking = true
                    } label: {
                        Label("Start GPS Tracking", systemImage: "location.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(locationService.isTracking)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                    HStack {
                        Button {
                            showingPointToPoint = true
                        } label: {
                            Label("Point-to-Point", systemImage: "mappin.and.ellipse")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(locationService.isTracking)

                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Manual Entry", systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                }

                // Summary Section
                Section {
                    MileageSummaryRowView(logs: logs)
                } header: {
                    Text("Summary")
                }

                // Trip Log Section
                Section {
                    if logs.isEmpty {
                        ContentUnavailableView {
                            Label("No Trips Logged", systemImage: "car.fill")
                        } description: {
                            Text("Use the buttons above to log your first trip")
                        }
                    } else {
                        ForEach(logs) { log in
                            MileageLogRowView(log: log)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedLog = log
                                }
                                .contextMenu {
                                    Button {
                                        selectedLog = log
                                    } label: {
                                        Label("View Details", systemImage: "eye")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        modelContext.delete(log)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete(perform: deleteLogs)
                    }
                } header: {
                    Text("Trip Log")
                }
            }
            .navigationTitle("Mileage")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingActiveTracking = true
                        } label: {
                            Label("Start Active Tracking", systemImage: "location.fill")
                        }
                        .disabled(locationService.isTracking)

                        Button {
                            showingPointToPoint = true
                        } label: {
                            Label("Point-to-Point Trip", systemImage: "mappin.and.ellipse")
                        }
                        .disabled(locationService.isTracking)

                        Divider()

                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Manual Entry", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Label("Log Trip", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                MileageEditorViewIOS(log: nil)
            }
            .fullScreenCover(isPresented: $showingActiveTracking) {
                ActiveTripTrackingViewIOS()
            }
            .sheet(isPresented: $showingPointToPoint) {
                PointToPointCaptureViewIOS()
            }
            .sheet(item: $selectedLog) { log in
                MileageDetailViewIOS(log: log)
            }
            .onAppear {
                requestLocationPermissionIfNeeded()
            }
        }
    }

    private func requestLocationPermissionIfNeeded() {
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestWhenInUseAuthorization()
        }
    }

    private func deleteLogs(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(logs[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Active Trip Banner

struct ActiveTripBannerView: View {
    let trip: ActiveTripData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Tracking in Progress")
                            .font(.headline)
                    }

                    HStack(spacing: 16) {
                        Label(formatDistance(trip.currentDistance), systemImage: "car.fill")
                        Label(formatDuration(from: trip.startTime), systemImage: "clock")
                        Label("\(trip.pointCount) pts", systemImage: "mappin")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        return String(format: "%.1f km", km)
    }

    private func formatDuration(from start: Date) -> String {
        let duration = Date.now.timeIntervalSince(start)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - Mileage Summary Row

struct MileageSummaryRowView: View {
    let logs: [MileageLog]

    var totalKm: Double {
        logs.reduce(0) { $0 + $1.effectiveDistance }
    }

    var thisMonthKm: Double {
        let calendar = Calendar.current
        let now = Date()
        return logs.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }.reduce(0) { $0 + $1.effectiveDistance }
    }

    var estimatedDeduction: Double {
        MileageSummary.calculateDeduction(totalKm: totalKm)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("This Month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f km", thisMonthKm))
                        .font(.title2.bold())
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Year to Date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f km", totalKm))
                        .font(.title2.bold())
                }
            }

            Divider()

            HStack {
                Text("Est. CRA Deduction")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "$%.2f", estimatedDeduction))
                    .font(.headline)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mileage Log Row

struct MileageLogRowView: View {
    let log: MileageLog

    var body: some View {
        HStack(spacing: 12) {
            // Tracking mode icon
            Image(systemName: trackingIcon)
                .font(.title2)
                .foregroundStyle(trackingColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(log.locationString.isEmpty ? "Trip" : log.locationString)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(log.displayDate)
                    if !log.purpose.isEmpty {
                        Text("•")
                        Text(log.purpose)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f km", log.effectiveDistance))
                    .font(.headline)

                if log.isRoundTrip {
                    Text("Round Trip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if log.hasGPSData {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var trackingIcon: String {
        switch log.trackingMode {
        case .manual: return "square.and.pencil"
        case .pointToPoint: return "mappin.and.ellipse"
        case .activeTracking: return "location.fill"
        }
    }

    private var trackingColor: Color {
        switch log.trackingMode {
        case .manual: return .gray
        case .pointToPoint: return .orange
        case .activeTracking: return .blue
        }
    }
}

// MARK: - Active Trip Tracking View

struct ActiveTripTrackingViewIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var locationService = LocationTrackingService.shared

    @State private var showingStopConfirmation = false
    @State private var purpose = ""
    @State private var hasInitializedLocation = false
    @State private var followsUserLocation = true
    // Default to a valid region (will be updated with actual location)
    @State private var mapPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 53.5, longitude: -113.5),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))

    // Get route coordinates from service for live display
    private var routeCoordinates: [CLLocationCoordinate2D] {
        locationService.currentRoutePoints.map { $0.coordinate }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Map with route line
                Map(position: $mapPosition, interactionModes: .all) {
                    // User's current location
                    UserAnnotation()

                    // Route polyline (the path traveled)
                    if routeCoordinates.count >= 2 {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(.blue, lineWidth: 4)
                    }

                    // Start marker
                    if let firstPoint = routeCoordinates.first {
                        Annotation("Start", coordinate: firstPoint) {
                            ZStack {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 20, height: 20)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
                .frame(height: 300)
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 8) {
                        Button {
                            followsUserLocation = true
                            centerOnUser()
                        } label: {
                            Image(systemName: followsUserLocation ? "location.fill" : "location")
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }

                        if routeCoordinates.count >= 2 {
                            Button {
                                followsUserLocation = false
                                fitRouteOnMap()
                            } label: {
                                Image(systemName: "map")
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding()
                }
                .onMapCameraChange { _ in
                    // User manually moved the map
                    followsUserLocation = false
                }

                // Trip Stats
                if let trip = locationService.activeTrip {
                    VStack(spacing: 20) {
                        HStack(spacing: 40) {
                            StatView(
                                title: "Distance",
                                value: formatDistance(trip.currentDistance),
                                icon: "car.fill"
                            )

                            StatView(
                                title: "Duration",
                                value: formatDuration(from: trip.startTime),
                                icon: "clock.fill"
                            )

                            StatView(
                                title: "Points",
                                value: "\(trip.pointCount)",
                                icon: "mappin"
                            )
                        }
                        .padding(.top, 20)

                        // Purpose field
                        TextField("Trip Purpose", text: $purpose)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)

                        Spacer()

                        // Stop Button
                        Button {
                            showingStopConfirmation = true
                        } label: {
                            Label("Stop Tracking", systemImage: "stop.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.red)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding()
                    }
                } else {
                    // Not tracking - show start button
                    VStack(spacing: 20) {
                        Spacer()

                        Text("Ready to Track")
                            .font(.title2)

                        Text("GPS will track your route as you drive")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        TextField("Trip Purpose", text: $purpose)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)

                        Button {
                            startTracking()
                        } label: {
                            Label("Start Tracking", systemImage: "location.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding()
                        .disabled(!locationService.isAuthorized)

                        if !locationService.isAuthorized {
                            Text("Location access required")
                                .font(.caption)
                                .foregroundStyle(.red)

                            Button {
                                locationService.requestWhenInUseAuthorization()
                            } label: {
                                Text("Grant Location Access")
                                    .font(.caption)
                                    .underline()
                            }
                        }

                        Spacer()
                    }
                }
            }
            .navigationTitle(locationService.isTracking ? "Tracking Trip" : "Start Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Close button just dismisses - tracking continues in background
                    Button(locationService.isTracking ? "Minimize" : "Close") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Stop Tracking?", isPresented: $showingStopConfirmation) {
                Button("Stop & Save Trip") {
                    stopAndSaveTrip()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will end the current trip and save it to your mileage log.")
            }
            .onChange(of: locationService.currentLocation) { _, newLocation in
                if let location = newLocation, followsUserLocation {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        mapPosition = .region(MKCoordinateRegion(
                            center: location.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                }
            }
            .onAppear {
                // If we already have a location from the service, use it
                if let currentLoc = locationService.currentLocation, !hasInitializedLocation {
                    mapPosition = .region(MKCoordinateRegion(
                        center: currentLoc.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                    hasInitializedLocation = true
                }
            }
            .task {
                // Request location to center the map
                guard locationService.isAuthorized, !hasInitializedLocation else { return }
                do {
                    let location = try await locationService.captureCurrentLocation()
                    if !hasInitializedLocation {
                        mapPosition = .region(MKCoordinateRegion(
                            center: location.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                        hasInitializedLocation = true
                    }
                } catch {
                    // Ignore errors - user will see their location via the blue dot
                }
            }
        }
    }

    private func startTracking() {
        locationService.startActiveTracking()
        followsUserLocation = true
        centerOnUser()
    }

    private func stopAndSaveTrip() {
        let result = locationService.stopActiveTracking()

        // Create mileage log from trip result
        let log = MileageLog(date: result.startTime ?? Date(), distance: result.totalDistance / 1000)
        log.trackingMode = .activeTracking
        log.purpose = purpose
        log.tripStartTime = result.startTime
        log.tripEndTime = result.endTime
        log.duration = result.duration

        if let startLoc = result.startLocation {
            log.startLatitude = startLoc.coordinate.latitude
            log.startLongitude = startLoc.coordinate.longitude
        }

        if let endLoc = result.endLocation {
            log.endLatitude = endLoc.coordinate.latitude
            log.endLongitude = endLoc.coordinate.longitude
        }

        // Save route points
        var routePoints: [TripRoutePoint] = []
        for location in result.routePoints {
            let point = TripRoutePoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: location.timestamp
            )
            point.speed = location.speed >= 0 ? location.speed : nil
            point.course = location.course >= 0 ? location.course : nil
            point.altitude = location.altitude
            routePoints.append(point)
        }
        log.routePoints = routePoints

        modelContext.insert(log)
        try? modelContext.save()

        dismiss()
    }

    private func centerOnUser() {
        if let location = locationService.currentLocation {
            withAnimation(.easeInOut(duration: 0.3)) {
                mapPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        }
    }

    private func fitRouteOnMap() {
        guard routeCoordinates.count >= 2 else { return }

        var minLat = routeCoordinates[0].latitude
        var maxLat = routeCoordinates[0].latitude
        var minLon = routeCoordinates[0].longitude
        var maxLon = routeCoordinates[0].longitude

        for coord in routeCoordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        var latDelta = (maxLat - minLat) * 1.3
        var lonDelta = (maxLon - minLon) * 1.3

        latDelta = max(latDelta, 0.01)
        lonDelta = max(lonDelta, 0.01)

        withAnimation(.easeInOut(duration: 0.5)) {
            mapPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            ))
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        return String(format: "%.1f km", km)
    }

    private func formatDuration(from start: Date) -> String {
        let duration = Date.now.timeIntervalSince(start)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - Stat View

struct StatView: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)

            Text(value)
                .font(.title3.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Point-to-Point Capture View

struct PointToPointCaptureViewIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var locationService = LocationTrackingService.shared

    @State private var startLocation: CLLocation?
    @State private var endLocation: CLLocation?
    @State private var isCapturingStart = false
    @State private var isCapturingEnd = false
    @State private var purpose = ""
    @State private var startLocationName = ""
    @State private var endLocationName = ""
    @State private var isRoundTrip = false
    @State private var errorMessage: String?

    var calculatedDistance: Double? {
        guard let start = startLocation, let end = endLocation else { return nil }
        return start.distance(from: end) / 1000 // Convert to km
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Start Location
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Start Location")
                                .font(.headline)
                            if let start = startLocation {
                                Text(String(format: "%.4f, %.4f", start.coordinate.latitude, start.coordinate.longitude))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not captured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button {
                            captureStartLocation()
                        } label: {
                            if isCapturingStart {
                                ProgressView()
                            } else {
                                Image(systemName: startLocation == nil ? "location.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(startLocation == nil ? .blue : .green)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCapturingStart || isCapturingEnd)
                    }

                    TextField("Start Name (optional)", text: $startLocationName)

                    // End Location
                    HStack {
                        VStack(alignment: .leading) {
                            Text("End Location")
                                .font(.headline)
                            if let end = endLocation {
                                Text(String(format: "%.4f, %.4f", end.coordinate.latitude, end.coordinate.longitude))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not captured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button {
                            captureEndLocation()
                        } label: {
                            if isCapturingEnd {
                                ProgressView()
                            } else {
                                Image(systemName: endLocation == nil ? "location.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(endLocation == nil ? .blue : .green)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCapturingStart || isCapturingEnd || startLocation == nil)
                    }

                    TextField("End Name (optional)", text: $endLocationName)
                } header: {
                    Text("Locations")
                }

                if let distance = calculatedDistance {
                    Section {
                        HStack {
                            Text("Calculated Distance")
                            Spacer()
                            Text(String(format: "%.1f km", distance))
                                .bold()
                        }

                        Toggle("Round Trip", isOn: $isRoundTrip)

                        if isRoundTrip {
                            HStack {
                                Text("Total Distance")
                                Spacer()
                                Text(String(format: "%.1f km", distance * 2))
                                    .bold()
                                    .foregroundStyle(.blue)
                            }
                        }
                    } header: {
                        Text("Distance")
                    }
                }

                Section {
                    TextField("Trip Purpose", text: $purpose, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Details")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Point-to-Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTrip()
                    }
                    .disabled(startLocation == nil || endLocation == nil)
                }
            }
        }
    }

    private func captureStartLocation() {
        isCapturingStart = true
        errorMessage = nil

        Task {
            do {
                startLocation = try await locationService.captureCurrentLocation()
            } catch {
                errorMessage = error.localizedDescription
            }
            isCapturingStart = false
        }
    }

    private func captureEndLocation() {
        isCapturingEnd = true
        errorMessage = nil

        Task {
            do {
                endLocation = try await locationService.captureCurrentLocation()
            } catch {
                errorMessage = error.localizedDescription
            }
            isCapturingEnd = false
        }
    }

    private func saveTrip() {
        guard let start = startLocation, let end = endLocation, let distance = calculatedDistance else { return }

        let log = MileageLog(date: Date(), distance: distance)
        log.trackingMode = .pointToPoint
        log.purpose = purpose
        log.isRoundTrip = isRoundTrip
        log.startLocation = startLocationName
        log.endLocation = endLocationName
        log.startLatitude = start.coordinate.latitude
        log.startLongitude = start.coordinate.longitude
        log.endLatitude = end.coordinate.latitude
        log.endLongitude = end.coordinate.longitude

        modelContext.insert(log)
        try? modelContext.save()

        dismiss()
    }
}

// MARK: - Mileage Detail View

struct MileageDetailViewIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let log: MileageLog

    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Map if GPS data available
                    if log.hasGPSData {
                        TripMapView(log: log)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                    }

                    // Trip Info Card
                    VStack(spacing: 16) {
                        // Distance
                        HStack {
                            Label("Distance", systemImage: "car.fill")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f km", log.effectiveDistance))
                                .font(.title2.bold())
                        }

                        Divider()

                        // Date
                        HStack {
                            Label("Date", systemImage: "calendar")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(log.displayDate)
                        }

                        // Duration if available
                        if let duration = log.formattedDuration {
                            HStack {
                                Label("Duration", systemImage: "clock")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(duration)
                            }
                        }

                        // Tracking mode
                        HStack {
                            Label("Tracking", systemImage: trackingIcon)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(log.trackingMode.rawValue)
                        }

                        if log.isRoundTrip {
                            HStack {
                                Label("Type", systemImage: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Round Trip")
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // Locations Card
                    if !log.startLocation.isEmpty || !log.endLocation.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Route")
                                .font(.headline)

                            if !log.startLocation.isEmpty {
                                HStack {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                    Text(log.startLocation)
                                }
                            }

                            if !log.endLocation.isEmpty {
                                HStack {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                    Text(log.endLocation)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // Purpose
                    if !log.purpose.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Purpose")
                                .font(.headline)
                            Text(log.purpose)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // Notes
                    if !log.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)
                            Text(log.notes)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // CRA Deduction
                    VStack(spacing: 8) {
                        Text("Estimated CRA Deduction")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(String(format: "$%.2f", MileageSummary.calculateDeduction(totalKm: log.effectiveDistance)))
                            .font(.title.bold())
                            .foregroundStyle(.green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Trip Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingEditor = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                MileageEditorViewIOS(log: log)
            }
            .confirmationDialog("Delete Trip?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(log)
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
    }

    private var trackingIcon: String {
        switch log.trackingMode {
        case .manual: return "square.and.pencil"
        case .pointToPoint: return "mappin.and.ellipse"
        case .activeTracking: return "location.fill"
        }
    }
}

// MARK: - Trip Map View

struct TripMapView: View {
    let log: MileageLog

    @State private var cameraPosition: MapCameraPosition = .automatic

    var startCoordinate: CLLocationCoordinate2D? {
        guard let lat = log.startLatitude, let lon = log.startLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var endCoordinate: CLLocationCoordinate2D? {
        guard let lat = log.endLatitude, let lon = log.endLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Get route coordinates from stored route points, or fall back to start/end
    var routeCoordinates: [CLLocationCoordinate2D] {
        guard let points = log.routePoints, !points.isEmpty else {
            // Just use start and end
            var coords: [CLLocationCoordinate2D] = []
            if let start = startCoordinate { coords.append(start) }
            if let end = endCoordinate { coords.append(end) }
            return coords
        }
        return points
            .sorted { $0.timestamp < $1.timestamp }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        Map(position: $cameraPosition) {
            // Route polyline
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(.blue, lineWidth: 4)
            }

            // Start marker
            if let start = startCoordinate {
                Annotation("Start", coordinate: start) {
                    ZStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 20, height: 20)
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                    }
                }
            }

            // End marker
            if let end = endCoordinate {
                Annotation("End", coordinate: end) {
                    ZStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 20, height: 20)
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .mapStyle(.standard)
        .onAppear {
            calculateCameraPosition()
        }
    }

    private func calculateCameraPosition() {
        guard !routeCoordinates.isEmpty else { return }

        var minLat = routeCoordinates[0].latitude
        var maxLat = routeCoordinates[0].latitude
        var minLon = routeCoordinates[0].longitude
        var maxLon = routeCoordinates[0].longitude

        for coord in routeCoordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let padding = 0.3

        var latDelta = (maxLat - minLat) * (1 + padding)
        var lonDelta = (maxLon - minLon) * (1 + padding)

        // Ensure minimum span
        latDelta = max(latDelta, 0.01)
        lonDelta = max(lonDelta, 0.01)

        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        let region = MKCoordinateRegion(center: center, span: span)

        cameraPosition = .region(region)
    }
}

struct TripAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let isStart: Bool
}

// MARK: - Mileage Editor View

struct MileageEditorViewIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let log: MileageLog?

    @State private var date: Date
    @State private var distance: Double
    @State private var startLocation: String
    @State private var endLocation: String
    @State private var purpose: String
    @State private var notes: String
    @State private var isRoundTrip: Bool

    init(log: MileageLog?) {
        self.log = log
        _date = State(initialValue: log?.date ?? Date())
        _distance = State(initialValue: log?.distance ?? 0)
        _startLocation = State(initialValue: log?.startLocation ?? "")
        _endLocation = State(initialValue: log?.endLocation ?? "")
        _purpose = State(initialValue: log?.purpose ?? "")
        _notes = State(initialValue: log?.notes ?? "")
        _isRoundTrip = State(initialValue: log?.isRoundTrip ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    HStack {
                        Text("Distance (km)")
                        Spacer()
                        TextField("0", value: $distance, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    Toggle("Round Trip", isOn: $isRoundTrip)
                } header: {
                    Text("Trip Details")
                }

                Section {
                    TextField("Start Location", text: $startLocation)
                    TextField("End Location", text: $endLocation)
                } header: {
                    Text("Locations")
                }

                Section {
                    TextField("Purpose", text: $purpose)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Additional Info")
                }
            }
            .navigationTitle(log == nil ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(distance <= 0)
                }
            }
        }
    }

    private func save() {
        let entry: MileageLog
        if let existing = log {
            entry = existing
        } else {
            entry = MileageLog()
            entry.trackingMode = .manual
            modelContext.insert(entry)
        }

        entry.date = date
        entry.distance = distance
        entry.startLocation = startLocation
        entry.endLocation = endLocation
        entry.purpose = purpose
        entry.notes = notes
        entry.isRoundTrip = isRoundTrip

        try? modelContext.save()
        dismiss()
    }
}
#endif
