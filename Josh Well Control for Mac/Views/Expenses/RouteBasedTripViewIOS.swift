//
//  RouteBasedTripViewIOS.swift
//  Josh Well Control for Mac
//
//  Route-based mileage tracking view for iOS
//

#if os(iOS)
import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct RouteBasedTripViewIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var locationService = LocationTrackingService.shared
    @StateObject private var geocodingService = GeocodingRouteService.shared

    // Trip data
    @State private var startLocation: CLLocation?
    @State private var startLocationName: String = ""
    @State private var destination: ResolvedDestination?
    @State private var calculatedRoute: RouteCalculationResult?
    @State private var purpose: String = ""
    @State private var isRoundTrip: Bool = false
    @State private var tripDate: Date = Date()
    @State private var isHistoricalEntry: Bool = false

    // UI state
    @State private var isCapturingStart: Bool = false
    @State private var isCalculatingRoute: Bool = false
    @State private var showingDestinationPicker: Bool = false
    @State private var showingStartAddressEntry: Bool = false
    @State private var errorMessage: String?

    // Map
    @State private var mapPosition: MapCameraPosition = .automatic

    // Client/Well linking
    @Query(sort: \Client.companyName) private var clients: [Client]
    @Query(sort: \Well.name) private var wells: [Well]
    @State private var selectedClient: Client?
    @State private var selectedWell: Well?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Map preview
                    mapSection

                    // Start location
                    startLocationSection

                    // Destination
                    destinationSection

                    // Route info
                    if let route = calculatedRoute {
                        routeInfoSection(route: route)
                    }

                    // Trip details
                    tripDetailsSection

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // Save button
                    saveButton
                }
                .padding()
            }
            .navigationTitle("Route-Based Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingDestinationPicker) {
                DestinationPickerView(
                    selectedDestination: $destination,
                    onSelect: { dest in
                        destination = dest
                        calculateRouteIfReady()
                    }
                )
            }
            .sheet(isPresented: $showingStartAddressEntry) {
                startAddressEntrySheet
            }
            .onAppear {
                if !isHistoricalEntry && startLocation == nil {
                    captureCurrentLocation()
                }
            }
        }
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Group {
            if let route = calculatedRoute, let points = route.polylinePoints, points.count >= 2 {
                Map(position: $mapPosition) {
                    // Route polyline
                    MapPolyline(coordinates: points)
                        .stroke(.blue, lineWidth: 4)

                    // Start marker
                    Annotation("Start", coordinate: route.startCoordinate) {
                        ZStack {
                            Circle().fill(.green).frame(width: 20, height: 20)
                            Circle().fill(.white).frame(width: 8, height: 8)
                        }
                    }

                    // End marker
                    Annotation("End", coordinate: route.endCoordinate) {
                        ZStack {
                            Circle().fill(.red).frame(width: 20, height: 20)
                            Circle().fill(.white).frame(width: 8, height: 8)
                        }
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let start = startLocation {
                Map(position: $mapPosition) {
                    Annotation("Start", coordinate: start.coordinate) {
                        ZStack {
                            Circle().fill(.green).frame(width: 20, height: 20)
                            Circle().fill(.white).frame(width: 8, height: 8)
                        }
                    }

                    if let dest = destination {
                        Annotation("Destination", coordinate: dest.coordinate) {
                            ZStack {
                                Circle().fill(.red).frame(width: 20, height: 20)
                                Circle().fill(.white).frame(width: 8, height: 8)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onAppear {
                    mapPosition = .region(MKCoordinateRegion(
                        center: start.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 200)
                    .overlay {
                        VStack {
                            Image(systemName: "map")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Route will appear here")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
    }

    // MARK: - Start Location Section

    private var startLocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start Location")
                .font(.headline)

            // Historical entry toggle
            Toggle("Enter past trip", isOn: $isHistoricalEntry)
                .onChange(of: isHistoricalEntry) { _, newValue in
                    if newValue {
                        startLocation = nil
                        startLocationName = ""
                    }
                }

            if isHistoricalEntry {
                // Manual start address entry
                Button {
                    showingStartAddressEntry = true
                } label: {
                    HStack {
                        Image(systemName: startLocation != nil ? "checkmark.circle.fill" : "location")
                            .foregroundStyle(startLocation != nil ? .green : .blue)

                        VStack(alignment: .leading) {
                            Text(startLocation != nil ? "Start Location Set" : "Enter Start Address")
                                .font(.subheadline)
                            if !startLocationName.isEmpty {
                                Text(startLocationName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
            } else {
                // GPS capture
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let start = startLocation {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Current Location Captured")
                                    .font(.subheadline)
                            }
                            Text(String(format: "%.4f, %.4f", start.coordinate.latitude, start.coordinate.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Capture your current location")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        captureCurrentLocation()
                    } label: {
                        if isCapturingStart {
                            ProgressView()
                        } else {
                            Image(systemName: "location.fill")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCapturingStart)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Destination Section

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Destination")
                .font(.headline)

            Button {
                showingDestinationPicker = true
            } label: {
                HStack {
                    Image(systemName: destination != nil ? "mappin.circle.fill" : "mappin.and.ellipse")
                        .foregroundStyle(destination != nil ? .red : .blue)

                    VStack(alignment: .leading, spacing: 4) {
                        if let dest = destination {
                            Text(dest.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            if let address = dest.address {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("Select Destination")
                                .font(.subheadline)
                            Text("Search address, well, or client")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Route Info Section

    private func routeInfoSection(route: RouteCalculationResult) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                VStack {
                    Text(route.formattedDistance)
                        .font(.title2.bold())
                    Text("Distance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack {
                    Text(route.formattedTravelTime)
                        .font(.title2.bold())
                    Text("Drive Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isRoundTrip {
                    Divider()
                        .frame(height: 40)

                    VStack {
                        Text(String(format: "%.1f km", route.distanceKm * 2))
                            .font(.title2.bold())
                            .foregroundStyle(.blue)
                        Text("Round Trip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)

            Toggle("Round Trip", isOn: $isRoundTrip)
                .padding(.horizontal)
        }
    }

    // MARK: - Trip Details Section

    private var tripDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trip Details")
                .font(.headline)

            if isHistoricalEntry {
                DatePicker("Date", selection: $tripDate, displayedComponents: .date)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
            }

            TextField("Purpose (optional)", text: $purpose)
                .textFieldStyle(.roundedBorder)

            // Client picker
            Picker("Client", selection: $selectedClient) {
                Text("None").tag(nil as Client?)
                ForEach(clients) { client in
                    Text(client.companyName).tag(client as Client?)
                }
            }

            // Well picker
            Picker("Well", selection: $selectedWell) {
                Text("None").tag(nil as Well?)
                ForEach(wells) { well in
                    Text(well.name).tag(well as Well?)
                }
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            saveTrip()
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text(calculatedRoute != nil ? "Save Trip" : "Calculate & Save")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(canSave ? Color.blue : Color.gray)
            .foregroundStyle(.white)
            .cornerRadius(12)
        }
        .disabled(!canSave || isCalculatingRoute)
    }

    private var canSave: Bool {
        startLocation != nil && destination != nil
    }

    // MARK: - Start Address Entry Sheet

    private var startAddressEntrySheet: some View {
        NavigationStack {
            DestinationPickerView(
                selectedDestination: .constant(nil),
                onSelect: { dest in
                    startLocation = CLLocation(
                        latitude: dest.coordinate.latitude,
                        longitude: dest.coordinate.longitude
                    )
                    startLocationName = dest.name
                    showingStartAddressEntry = false
                    calculateRouteIfReady()
                }
            )
            .navigationTitle("Start Location")
        }
    }

    // MARK: - Actions

    private func captureCurrentLocation() {
        isCapturingStart = true
        errorMessage = nil

        Task {
            do {
                let location = try await locationService.captureCurrentLocation()
                await MainActor.run {
                    startLocation = location
                    calculateRouteIfReady()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isCapturingStart = false
            }
        }
    }

    private func calculateRouteIfReady() {
        guard let start = startLocation, let dest = destination else { return }

        isCalculatingRoute = true
        errorMessage = nil

        Task {
            do {
                let route = try await geocodingService.calculateRoute(
                    from: start.coordinate,
                    to: dest.coordinate
                )
                await MainActor.run {
                    calculatedRoute = route
                    fitMapToRoute(route)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not calculate route: \(error.localizedDescription)"
                    // Fall back to straight-line distance
                    let straightLine = geocodingService.calculateStraightLineDistance(
                        from: start.coordinate,
                        to: dest.coordinate
                    )
                    calculatedRoute = RouteCalculationResult(
                        distance: straightLine,
                        expectedTravelTime: 0,
                        startCoordinate: start.coordinate,
                        endCoordinate: dest.coordinate,
                        polylinePoints: [start.coordinate, dest.coordinate]
                    )
                }
            }
            await MainActor.run {
                isCalculatingRoute = false
            }
        }
    }

    private func fitMapToRoute(_ route: RouteCalculationResult) {
        let start = route.startCoordinate
        let end = route.endCoordinate

        let centerLat = (start.latitude + end.latitude) / 2
        let centerLon = (start.longitude + end.longitude) / 2
        let latDelta = abs(start.latitude - end.latitude) * 1.5
        let lonDelta = abs(start.longitude - end.longitude) * 1.5

        withAnimation {
            mapPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(
                    latitudeDelta: max(latDelta, 0.02),
                    longitudeDelta: max(lonDelta, 0.02)
                )
            ))
        }
    }

    private func saveTrip() {
        guard let start = startLocation, let dest = destination else { return }

        // Calculate route if not done yet
        if calculatedRoute == nil {
            calculateRouteIfReady()
            return
        }

        guard let route = calculatedRoute else { return }

        // Create MileageLog
        let log = MileageLog()
        log.date = isHistoricalEntry ? tripDate : Date()
        log.distance = route.distanceKm
        log.trackingMode = .routeBased
        log.purpose = purpose
        log.isRoundTrip = isRoundTrip

        // Start location
        log.startLatitude = start.coordinate.latitude
        log.startLongitude = start.coordinate.longitude
        log.startLocation = startLocationName

        // End location
        log.endLatitude = dest.coordinate.latitude
        log.endLongitude = dest.coordinate.longitude
        log.endLocation = dest.name

        // Route calculation data
        log.wasRouteCalculated = true
        log.calculatedDistance = route.distanceKm
        log.expectedTravelTime = route.expectedTravelTime

        // Destination info
        log.destinationName = dest.name
        log.destinationLatitude = dest.coordinate.latitude
        log.destinationLongitude = dest.coordinate.longitude

        // Encode destination source
        if let sourceData = try? JSONEncoder().encode(dest.source),
           let sourceString = String(data: sourceData, encoding: .utf8) {
            log.destinationSourceRaw = sourceString
        }

        // Links
        log.client = selectedClient
        log.well = selectedWell

        // Save
        modelContext.insert(log)
        try? modelContext.save()

        dismiss()
    }
}
#endif
