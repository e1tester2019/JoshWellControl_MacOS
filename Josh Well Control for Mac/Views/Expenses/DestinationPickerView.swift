//
//  DestinationPickerView.swift
//  Josh Well Control for Mac
//
//  Destination picker for route-based mileage tracking (iOS)
//

#if os(iOS)
import SwiftUI
import SwiftData
import CoreLocation
import Combine

struct DestinationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var selectedDestination: ResolvedDestination?
    let onSelect: (ResolvedDestination) -> Void

    @StateObject private var geocodingService = GeocodingRouteService.shared

    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var isGeocoding = false
    @State private var geocodingError: String?

    // SwiftData queries
    @Query(sort: \Pad.name) private var allPads: [Pad]
    @Query(sort: \Client.companyName) private var allClients: [Client]

    // Filtered pads (only those with coordinates)
    private var padsWithCoordinates: [Pad] {
        allPads.filter { $0.latitude != nil && $0.longitude != nil }
    }

    // Filtered clients (only those with addresses)
    private var clientsWithAddresses: [Client] {
        allClients.filter { !$0.address.isEmpty || !$0.city.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Source", selection: $selectedTab) {
                    Text("Search").tag(0)
                    Text("Wells").tag(1)
                    Text("Clients").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                // Tab content
                Group {
                    switch selectedTab {
                    case 0:
                        addressSearchTab
                    case 1:
                        wellsTab
                    case 2:
                        clientsTab
                    default:
                        addressSearchTab
                    }
                }
            }
            .navigationTitle("Select Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .init(
                get: { geocodingError != nil },
                set: { if !$0 { geocodingError = nil } }
            )) {
                Button("OK") { geocodingError = nil }
            } message: {
                Text(geocodingError ?? "")
            }
        }
    }

    // MARK: - Address Search Tab

    private var addressSearchTab: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search for an address...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        geocodingService.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            .padding()
            .onChange(of: searchText) { _, newValue in
                geocodingService.searchAddresses(newValue)
            }

            // Search results
            if geocodingService.isSearching {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if geocodingService.searchResults.isEmpty && !searchText.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("No Results", systemImage: "mappin.slash")
                } description: {
                    Text("Try a different search term")
                }
                Spacer()
            } else {
                List(geocodingService.searchResults) { result in
                    Button {
                        selectSearchResult(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(isGeocoding)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Wells Tab

    private var wellsTab: some View {
        Group {
            if padsWithCoordinates.isEmpty {
                ContentUnavailableView {
                    Label("No Well Locations", systemImage: "mappin.slash")
                } description: {
                    Text("Add GPS coordinates to your pads to select them as destinations")
                }
            } else {
                List(padsWithCoordinates) { pad in
                    Button {
                        selectPad(pad)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pad.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                if !pad.surfaceLocation.isEmpty {
                                    Text(pad.surfaceLocation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                // Show well names on this pad
                                if let wells = pad.wells, !wells.isEmpty {
                                    Text(wells.map { $0.name }.joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Image(systemName: "location.fill")
                                .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Clients Tab

    private var clientsTab: some View {
        Group {
            if clientsWithAddresses.isEmpty {
                ContentUnavailableView {
                    Label("No Client Addresses", systemImage: "building.2")
                } description: {
                    Text("Add addresses to your clients to select them as destinations")
                }
            } else {
                List(clientsWithAddresses) { client in
                    Button {
                        selectClient(client)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(client.companyName)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(client.fullAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(isGeocoding)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Selection Handlers

    private func selectSearchResult(_ result: AddressSearchResult) {
        isGeocoding = true
        geocodingError = nil

        Task {
            do {
                let destination = try await geocodingService.geocodeSearchResult(result)
                await MainActor.run {
                    selectedDestination = destination
                    onSelect(destination)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    geocodingError = error.localizedDescription
                }
            }
            await MainActor.run {
                isGeocoding = false
            }
        }
    }

    private func selectPad(_ pad: Pad) {
        guard let lat = pad.latitude, let lon = pad.longitude else { return }

        let destination = ResolvedDestination(
            name: pad.name,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            address: pad.surfaceLocation.isEmpty ? nil : pad.surfaceLocation,
            source: .well(wellID: pad.id, padName: pad.name)
        )

        selectedDestination = destination
        onSelect(destination)
        dismiss()
    }

    private func selectClient(_ client: Client) {
        isGeocoding = true
        geocodingError = nil

        Task {
            do {
                let coordinate = try await geocodingService.geocodeAddress(client.fullAddress)
                let destination = ResolvedDestination(
                    name: client.companyName,
                    coordinate: coordinate,
                    address: client.fullAddress,
                    source: .client(clientID: client.id, companyName: client.companyName)
                )
                await MainActor.run {
                    selectedDestination = destination
                    onSelect(destination)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    geocodingError = "Could not find location for \(client.companyName). \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                isGeocoding = false
            }
        }
    }
}
#endif
