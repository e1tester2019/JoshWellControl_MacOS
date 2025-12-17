//
//  EnhancedWellPicker.swift
//  Josh Well Control for Mac
//
//  Searchable, filterable well picker with favorites, recents, and archive
//

import SwiftUI
import SwiftData

struct EnhancedWellPicker: View {
    let wells: [Well]
    @Binding var selectedWell: Well?
    @Binding var selectedProject: ProjectState?
    let modelContext: ModelContext

    @State private var filterService = WellFilterService()
    @State private var showPopover = false

    private var filteredWells: [Well] {
        filterService.filteredWells(from: wells)
    }

    var body: some View {
        #if os(macOS)
        macOSPicker
        #else
        iOSPicker
        #endif
    }

    // MARK: - macOS Implementation

    #if os(macOS)
    private var macOSPicker: some View {
        Button(action: { showPopover.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: selectedWell?.isFavorite == true ? "star.fill" : "building.2")
                    .foregroundStyle(selectedWell?.isFavorite == true ? .yellow : .secondary)
                Text(selectedWell?.name ?? "Select Well")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            wellPickerContent
                .frame(width: 320, height: 400)
        }
        .help("Select Well")
    }
    #endif

    // MARK: - iOS Implementation

    #if os(iOS)
    private var iOSPicker: some View {
        Button(action: { showPopover = true }) {
            HStack {
                Image(systemName: selectedWell?.isFavorite == true ? "star.fill" : "building.2")
                    .foregroundStyle(selectedWell?.isFavorite == true ? .yellow : .secondary)
                Text(selectedWell?.name ?? "Select Well")
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showPopover) {
            NavigationStack {
                wellPickerContent
                    .navigationTitle("Select Well")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPopover = false }
                        }
                    }
            }
        }
    }
    #endif

    // MARK: - Shared Content

    private var wellPickerContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search wells...", text: $filterService.searchText)
                    .textFieldStyle(.plain)
                if !filterService.searchText.isEmpty {
                    Button(action: { filterService.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.3))

            // Category picker
            Picker("Category", selection: $filterService.selectedCategory) {
                ForEach(WellFilterCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Wells list
            if filteredWells.isEmpty {
                ContentUnavailableView {
                    Label("No Wells", systemImage: "building.2")
                } description: {
                    if filterService.selectedCategory == .favorites {
                        Text("No favorite wells. Star a well to add it here.")
                    } else if filterService.selectedCategory == .recent {
                        Text("No recently accessed wells.")
                    } else if filterService.selectedCategory == .archived {
                        Text("No archived wells.")
                    } else {
                        Text("No wells match your search.")
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredWells) { well in
                        WellPickerRow(
                            well: well,
                            isSelected: selectedWell?.id == well.id,
                            onSelect: {
                                selectWell(well)
                            },
                            onToggleFavorite: {
                                filterService.toggleFavorite(well, context: modelContext)
                            },
                            onArchive: {
                                if well.isArchived {
                                    filterService.unarchive(well, context: modelContext)
                                } else {
                                    filterService.archive(well, context: modelContext)
                                }
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Actions footer
            HStack {
                Button(action: createNewWell) {
                    Label("New Well", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()

                if filterService.selectedCategory != .archived {
                    Toggle("Show Archived", isOn: $filterService.showArchived)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .padding(10)
        }
    }

    // MARK: - Actions

    private func selectWell(_ well: Well) {
        selectedWell = well
        selectedProject = well.projects?.first
        showPopover = false
    }

    private func createNewWell() {
        let well = Well(name: "New Well")
        modelContext.insert(well)
        let project = ProjectState()
        project.well = well
        well.projects = [project]
        modelContext.insert(project)
        try? modelContext.save()
        selectedWell = well
        selectedProject = project
        showPopover = false
    }
}

// MARK: - Well Picker Row

struct WellPickerRow: View {
    let well: Well
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onArchive: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Favorite star
                Button(action: onToggleFavorite) {
                    Image(systemName: well.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(well.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)

                // Well info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(well.name)
                            .fontWeight(isSelected ? .semibold : .regular)
                        if well.isArchived {
                            Text("Archived")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.2))
                                .cornerRadius(3)
                        }
                    }

                    if let uwi = well.uwi, !uwi.isEmpty {
                        Text(uwi)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let rigName = well.rigName, !rigName.isEmpty {
                        Text(rigName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Selection checkmark
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onToggleFavorite) {
                Label(well.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: well.isFavorite ? "star.slash" : "star")
            }
            Button(action: onArchive) {
                Label(well.isArchived ? "Unarchive" : "Archive",
                      systemImage: well.isArchived ? "archivebox.fill" : "archivebox")
            }
        }
    }
}

#Preview {
    EnhancedWellPicker(
        wells: [],
        selectedWell: .constant(nil),
        selectedProject: .constant(nil),
        modelContext: try! ModelContainer(for: Well.self).mainContext
    )
}
