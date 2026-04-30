import SwiftUI
import UniformTypeIdentifiers

struct BlocksHubView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(BackendAccessControl.self) private var accessControl
    @State private var showAddPaddock: Bool = false
    @State private var paddockToEdit: Paddock?
    @State private var shareURL: ShareURL?
    @State private var showImporter: Bool = false
    @State private var importSummary: PaddockJSONService.ImportSummary?
    @State private var importErrorMessage: String?

    var body: some View {
        Group {
            if store.paddocks.isEmpty {
                VineyardEmptyStateView(
                    icon: "square.grid.2x2",
                    title: "No paddocks yet",
                    message: "Create your first block to start mapping rows.",
                    actionTitle: accessControl.canCreateOperationalRecords ? "Add Paddock" : nil,
                    action: accessControl.canCreateOperationalRecords ? { showAddPaddock = true } : nil as (() -> Void)?
                )
            } else {
                paddockList
            }
        }
        .navigationTitle("Blocks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if accessControl.canCreateOperationalRecords {
                        Button {
                            showAddPaddock = true
                        } label: {
                            Label("Add Paddock", systemImage: "plus")
                        }
                    }
                    if accessControl.canExport && !store.paddocks.isEmpty {
                        Button {
                            exportPaddocks()
                        } label: {
                            Label("Export Blocks (JSON)", systemImage: "square.and.arrow.up")
                        }
                    }
                    if accessControl.canChangeSettings {
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import Blocks (JSON)", systemImage: "square.and.arrow.down")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddPaddock) {
            EditPaddockSheet(paddock: nil)
        }
        .sheet(item: $paddockToEdit) { paddock in
            EditPaddockSheet(paddock: paddock)
        }
        .sheet(item: $shareURL) { wrapper in
            ShareSheet(items: [wrapper.url])
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json, UTType(filenameExtension: "json") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .alert("Import Complete", isPresented: importSummaryBinding, presenting: importSummary) { _ in
            Button("OK", role: .cancel) { importSummary = nil }
        } message: { summary in
            var lines: [String] = [
                "Created: \(summary.created)",
                "Updated: \(summary.updated)",
                "Skipped: \(summary.skipped)"
            ]
            if !summary.errors.isEmpty {
                lines.append("")
                lines.append(contentsOf: summary.errors.prefix(5))
                if summary.errors.count > 5 {
                    lines.append("…and \(summary.errors.count - 5) more")
                }
            }
            return Text(lines.joined(separator: "\n"))
        }
        .alert("Import Failed", isPresented: importErrorBinding, presenting: importErrorMessage) { _ in
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var importSummaryBinding: Binding<Bool> {
        Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(get: { importErrorMessage != nil }, set: { if !$0 { importErrorMessage = nil } })
    }

    private var paddockList: some View {
        List {
            ForEach(store.paddocks) { paddock in
                Button {
                    paddockToEdit = paddock
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(VineyardTheme.leafGreen.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "square.grid.2x2.fill")
                                .foregroundStyle(VineyardTheme.leafGreen)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paddock.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("\(paddock.rows.count) rows")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete { offsets in
                guard accessControl.canDeleteOperationalRecords else { return }
                deletePaddocks(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deletePaddocks(at offsets: IndexSet) {
        for index in offsets {
            let paddock = store.paddocks[index]
            store.deletePaddock(paddock.id)
        }
    }

    // MARK: - Import / Export

    private func exportPaddocks() {
        let data = PaddockJSONService.generateJSON(paddocks: store.paddocks, vineyardId: store.selectedVineyardId)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        let vineyardName = store.selectedVineyard?.name ?? "Vineyard"
        let safeName = vineyardName.replacingOccurrences(of: " ", with: "_")
        let url = PaddockJSONService.saveJSONToTemp(data: data, fileName: "\(safeName)_blocks_\(dateString).json")
        shareURL = ShareURL(url: url)
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importPaddocks(from: url)
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func importPaddocks(from url: URL) {
        guard let vineyardId = store.selectedVineyardId else {
            importErrorMessage = "Select a vineyard before importing."
            return
        }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let existing = store.paddocks
            let result = try PaddockJSONService.parseJSON(data: data, vineyardId: vineyardId, existing: existing)
            let existingIds = Set(existing.map(\.id))
            for paddock in result.paddocks {
                if existingIds.contains(paddock.id) {
                    store.updatePaddock(paddock)
                } else {
                    store.addPaddock(paddock)
                }
            }
            importSummary = result.summary
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}
