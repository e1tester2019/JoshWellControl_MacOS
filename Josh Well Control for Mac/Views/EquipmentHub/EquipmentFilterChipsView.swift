//
//  EquipmentFilterChipsView.swift
//  Josh Well Control for Mac
//
//  Search field + filter pickers + view mode toggle for Equipment Hub.
//

import SwiftUI

struct EquipmentFilterChipsView: View {
    @Bindable var vm: EquipmentHubViewModel
    let categories: [RentalCategory]
    let vendors: [Vendor]
    let wells: [Well]

    var body: some View {
        HStack(spacing: 8) {
            // Search
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search equipment...", text: $vm.searchText)
                    .textFieldStyle(.plain)
                if !vm.searchText.isEmpty {
                    Button {
                        vm.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
            )
            .frame(maxWidth: 220)

            // Status filter
            Picker("Status", selection: $vm.filterStatus) {
                Text("All Status").tag(nil as EquipmentLocation?)
                ForEach(EquipmentLocation.allCases, id: \.self) { status in
                    Label(status.rawValue, systemImage: status.icon).tag(status as EquipmentLocation?)
                }
            }
            .frame(maxWidth: 140)

            // Category filter
            Picker("Category", selection: $vm.filterCategory) {
                Text("All Categories").tag(nil as RentalCategory?)
                ForEach(categories) { cat in
                    Label(cat.name, systemImage: cat.icon).tag(cat as RentalCategory?)
                }
            }
            .frame(maxWidth: 150)

            // Vendor filter
            Picker("Vendor", selection: $vm.filterVendor) {
                Text("All Vendors").tag(nil as Vendor?)
                ForEach(vendors) { vendor in
                    Text(vendor.companyName).tag(vendor as Vendor?)
                }
            }
            .frame(maxWidth: 150)

            // Well filter
            Picker("Well", selection: $vm.filterWell) {
                Text("All Wells").tag(nil as Well?)
                ForEach(wells) { well in
                    Text(well.name).tag(well as Well?)
                }
            }
            .frame(maxWidth: 140)

            // Active only toggle
            Toggle("Active", isOn: $vm.filterActiveOnly)
                .toggleStyle(.checkbox)

            if vm.hasActiveFilters {
                Button {
                    vm.clearFilters()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            // View mode picker (equipment tab only)
            if vm.selectedTab == .equipment {
                Picker("View", selection: $vm.viewMode) {
                    ForEach(EquipmentViewMode.allCases) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 120)
            }
        }
    }
}
