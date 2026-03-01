//
//  EquipmentFilterViewIOS.swift
//  Josh Well Control for Mac
//
//  Collapsible filter section for the iOS Equipment Hub.
//

import SwiftUI
import SwiftData

#if os(iOS)
struct EquipmentFilterViewIOS: View {
    @Bindable var vm: EquipmentHubViewModel
    let categories: [RentalCategory]
    let vendors: [Vendor]
    let wells: [Well]

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if vm.selectedTab == .equipment {
                Picker("Status", selection: $vm.filterStatus) {
                    Text("All Statuses").tag(nil as EquipmentLocation?)
                    ForEach(EquipmentLocation.allCases, id: \.self) { status in
                        Label(status.rawValue, systemImage: status.icon)
                            .tag(status as EquipmentLocation?)
                    }
                }

                Picker("Category", selection: $vm.filterCategory) {
                    Text("All Categories").tag(nil as RentalCategory?)
                    ForEach(categories) { cat in
                        Label(cat.name, systemImage: cat.icon)
                            .tag(cat as RentalCategory?)
                    }
                }

                Picker("Vendor", selection: $vm.filterVendor) {
                    Text("All Vendors").tag(nil as Vendor?)
                    ForEach(vendors) { vendor in
                        Text(vendor.companyName).tag(vendor as Vendor?)
                    }
                }

                Toggle("Active Only", isOn: $vm.filterActiveOnly)
            }

            Picker("Well", selection: $vm.filterWell) {
                Text("All Wells").tag(nil as Well?)
                ForEach(wells) { well in
                    Text(well.name).tag(well as Well?)
                }
            }

            if vm.hasActiveFilters {
                Button("Clear All Filters", role: .destructive) {
                    withAnimation(EquipmentAnimation.filterChange) {
                        vm.clearFilters()
                    }
                }
            }
        } label: {
            HStack {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                if vm.hasActiveFilters {
                    Text("Active")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue)
                        .cornerRadius(4)
                }
            }
        }
    }
}
#endif
