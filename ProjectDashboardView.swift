import SwiftUI
import SwiftData

struct ProjectDashboardHeaderView: View {
    @Environment(\.modelContext) private var modelContext
    var well: Well?
    @State private var pastedText: String = ""
    @State private var showParseResult: Bool = false
    @State private var lastParsed: ParsedWellInfo = ParsedWellInfo()

    var body: some View {
        Group {
            if let well = well {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Well Header") {
                        HStack {
                            Spacer()
                            Button {
                                let name = self.well?.name ?? ""
                                let uwi = self.well?.uwi ?? ""
                                let afe = self.well?.afeNumber ?? ""
                                let req = self.well?.requisitioner ?? ""
                                let summary = "Name: \(name)\nUWI: \(uwi)\nAFE: \(afe)\nRequisitioner: \(req)"
                                #if os(iOS)
                                UIPasteboard.general.string = summary
                                #elseif os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(summary, forType: .string)
                                #endif
                            } label: {
                                Label("Copy Info", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("Name:")
                                    .frame(width: 110, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("Well name", text: Binding(get: { self.well?.name ?? "" }, set: { self.well?.name = $0 }))
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("UWI:")
                                    .frame(width: 110, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("UWI", text: Binding(get: { self.well?.uwi ?? "" }, set: { self.well?.uwi = $0 }))
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("AFE:")
                                    .frame(width: 110, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("AFE Number", text: Binding(get: { self.well?.afeNumber ?? "" }, set: { self.well?.afeNumber = $0 }))
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Requisitioner:")
                                    .frame(width: 110, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("Requisitioner", text: Binding(get: { self.well?.requisitioner ?? "" }, set: { self.well?.requisitioner = $0 }))
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(8)
                    }

                    GroupBox("Paste Block → Parse") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Paste the multi-line block here and click Parse. Keys supported: Well Name, UWI, AFE/AFE Number, Requisitioner.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextEditor(text: $pastedText)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 120)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))

                            HStack {
                                Button("Parse & Apply") {
                                    let parsed = WellParsing.parse(from: pastedText)
                                    lastParsed = parsed
                                    self.well?.apply(parsed: parsed)
                                    try? modelContext.save()
                                    showParseResult = true
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Clear") {
                                    pastedText = ""
                                }
                                .buttonStyle(.bordered)

                                Spacer()
                            }

                            if showParseResult {
                                let name = lastParsed.name ?? "—"
                                let uwi = lastParsed.uwi ?? "—"
                                let afe = lastParsed.afeNumber ?? "—"
                                let req = lastParsed.requisitioner ?? "—"
                                Text("Parsed → Name: \(name) | UWI: \(uwi) | AFE: \(afe) | Req: \(req)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Well Header") {
                        Text("No well linked")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
    }
}

struct ProjectDashboardScreen: View {
    @Environment(\.modelContext) private var modelContext
    var project: ProjectState

    init(project: ProjectState) {
        self.project = project
    }

    var body: some View {
        VStack(spacing: 12) {
            GroupBox {
                ProjectDashboardHeaderView(well: project.well)
            } label: {
                HStack(spacing: 8) {
                    Label("Well", systemImage: "fuelpump")
                    Spacer()
                    Button {
                        let name = project.well?.name ?? ""
                        let uwi = project.well?.uwi ?? ""
                        let afe = project.well?.afeNumber ?? ""
                        let req = project.well?.requisitioner ?? ""
                        let summary = "Name: \(name)\nUWI: \(uwi)\nAFE: \(afe)\nRequisitioner: \(req)"
                        #if os(iOS)
                        UIPasteboard.general.string = summary
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary, forType: .string)
                        #endif
                    } label: {
                        Label("Copy Info", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
