import SwiftUI

struct AddEditWorkTaskView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(NewBackendAuthService.self) private var auth
    @Environment(WorkTaskSyncService.self) private var workTaskSync
    @Environment(WorkTaskTypeSyncService.self) private var workTaskTypeSync
    @Environment(\.accessControl) private var accessControl
    @Environment(\.dismiss) private var dismiss

    let existingTask: WorkTask?

    @State private var date: Date = Date()
    @State private var taskType: String = ""
    @State private var customTaskType: String = ""
    @State private var showCustomTaskField: Bool = false
    @State private var paddockId: UUID?
    @State private var paddockName: String = ""
    @State private var durationText: String = ""
    @State private var notes: String = ""
    @State private var resources: [WorkTaskResource] = []
    @State private var showDelete: Bool = false
    @State private var showWorkerTypes: Bool = false

    init(existingTask: WorkTask? = nil) {
        self.existingTask = existingTask
    }

    private var isEditing: Bool { existingTask != nil }
    private var canDelete: Bool { accessControl?.canDelete ?? false }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var durationHours: Double {
        Double(durationText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var totalPeople: Int { resources.reduce(0) { $0 + $1.count } }

    /// Vineyard-scoped catalog merged with the built-in defaults. Drives the
    /// Task Type picker so Lovable-created custom types appear alongside the
    /// existing iOS defaults.
    private var mergedTaskTypeNames: [String] {
        let vineyardId = store.selectedVineyardId
        let scoped = store.workTaskTypes.filter { vineyardId == nil || $0.vineyardId == vineyardId }
        return WorkTaskTypeCatalog.merged(with: scoped)
    }

    private var totalCost: Double {
        resources.reduce(0.0) { $0 + ($1.hourlyRate * durationHours * Double($1.count)) }
    }

    private var costPerPerson: Double {
        guard totalPeople > 0 else { return 0 }
        return totalCost / Double(totalPeople)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    Menu {
                        ForEach(mergedTaskTypeNames, id: \.self) { t in
                            Button(t) {
                                taskType = t
                                showCustomTaskField = false
                            }
                        }
                        Divider()
                        Button {
                            showCustomTaskField = true
                            taskType = customTaskType
                        } label: {
                            Label("Custom…", systemImage: "pencil")
                        }
                    } label: {
                        HStack {
                            Text("Task Type")
                            Spacer()
                            Text(taskType.isEmpty ? "Select" : taskType)
                                .foregroundStyle(taskType.isEmpty ? .secondary : .primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if showCustomTaskField {
                        TextField("Custom task name", text: $customTaskType)
                            .onChange(of: customTaskType) { _, v in taskType = v }
                    }

                    Menu {
                        Button("All Blocks / None") {
                            paddockId = nil
                            paddockName = ""
                        }
                        Divider()
                        ForEach(store.paddocks) { p in
                            Button(p.name) {
                                paddockId = p.id
                                paddockName = p.name
                            }
                        }
                    } label: {
                        HStack {
                            Text("Block")
                            Spacer()
                            Text(paddockName.isEmpty ? "Select" : paddockName)
                                .foregroundStyle(paddockName.isEmpty ? .secondary : .primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Duration (hours)")
                        Spacer()
                        TextField("0", text: $durationText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }

                Section {
                    if resources.isEmpty {
                        Text("No workers added")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($resources) { $res in
                            resourceRow($res)
                        }
                        .onDelete { idx in
                            resources.remove(atOffsets: idx)
                        }
                    }
                    Button {
                        addResource()
                    } label: {
                        Label("Add Worker Type", systemImage: "plus.circle.fill")
                    }
                    .disabled(store.operatorCategories.isEmpty)
                    if store.operatorCategories.isEmpty {
                        Text("Add worker types in Settings → Operator Categories first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Resources")
                        Spacer()
                        Button {
                            showWorkerTypes = true
                        } label: {
                            Label("Edit", systemImage: "square.and.pencil")
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                                .textCase(nil)
                        }
                        .buttonStyle(.borderless)
                    }
                } footer: {
                    Text("Set the number of workers of each type used on this task.")
                }

                if accessControl?.canViewFinancials ?? false {
                    Section("Estimated Cost") {
                        LabeledContent("Total People") {
                            Text("\(totalPeople)")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Cost / Person") {
                            Text(costPerPerson, format: .currency(code: currencyCode))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Block Total")
                                .font(.headline)
                            Spacer()
                            Text(totalCost, format: .currency(code: currencyCode))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(VineyardTheme.leafGreen)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Section("Task Summary") {
                        LabeledContent("Total People") {
                            Text("\(totalPeople)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional notes…", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if isEditing && canDelete {
                    Section {
                        Button(role: .destructive) {
                            showDelete = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Task", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTask() }
                        .fontWeight(.semibold)
                        .disabled(taskType.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete Task", isPresented: $showDelete) {
                Button("Delete", role: .destructive) {
                    if let t = existingTask {
                        store.deleteWorkTask(t.id)
                        Task { await workTaskSync.syncForSelectedVineyard() }
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: loadIfEditing)
            .sheet(isPresented: $showWorkerTypes) {
                NavigationStack {
                    OperatorCategoriesView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showWorkerTypes = false }
                            }
                        }
                }
            }
        }
    }

    private func resourceRow(_ res: Binding<WorkTaskResource>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(store.operatorCategories) { cat in
                    Button(cat.name) {
                        res.wrappedValue.operatorCategoryId = cat.id
                        res.wrappedValue.workerTypeName = cat.name
                        res.wrappedValue.hourlyRate = cat.costPerHour
                    }
                }
            } label: {
                HStack {
                    Text(res.wrappedValue.workerTypeName.isEmpty ? "Select worker type" : res.wrappedValue.workerTypeName)
                        .foregroundStyle(res.wrappedValue.workerTypeName.isEmpty ? .secondary : .primary)
                    Spacer()
                    if accessControl?.canViewFinancials ?? false {
                        Text(res.wrappedValue.hourlyRate, format: .currency(code: currencyCode))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Count")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(value: res.count, in: 1...99) {
                    Text("\(res.wrappedValue.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                .labelsHidden()
                Text("\(res.wrappedValue.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .frame(width: 28)
            }
        }
        .padding(.vertical, 4)
    }

    private func addResource() {
        guard let first = store.operatorCategories.first else { return }
        resources.append(WorkTaskResource(
            operatorCategoryId: first.id,
            workerTypeName: first.name,
            hourlyRate: first.costPerHour,
            count: 1
        ))
    }

    private func loadIfEditing() {
        if let t = existingTask {
            date = t.date
            taskType = t.taskType
            if !mergedTaskTypeNames.contains(t.taskType) && !t.taskType.isEmpty {
                showCustomTaskField = true
                customTaskType = t.taskType
            }
            paddockId = t.paddockId
            paddockName = t.paddockName
            durationText = t.durationHours > 0 ? String(format: "%.2f", t.durationHours) : ""
            notes = t.notes
            resources = t.resources
        }
    }

    private func saveTask() {
        let trimmed = taskType.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // If the user entered a custom task type that is not in the merged
        // catalog yet, persist it to work_task_types so it syncs to other
        // devices and Lovable.
        let lower = trimmed.lowercased()
        let knownLower = Set(mergedTaskTypeNames.map { $0.lowercased() })
        if !knownLower.contains(lower), let vineyardId = store.selectedVineyardId {
            store.addWorkTaskType(WorkTaskType(
                vineyardId: vineyardId,
                name: trimmed,
                isDefault: false,
                sortOrder: 0
            ))
        }

        var task = existingTask ?? WorkTask()
        task.date = date
        task.taskType = trimmed
        task.paddockId = paddockId
        task.paddockName = paddockName
        task.durationHours = durationHours
        task.resources = resources
        task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let userName = auth.userName ?? ""
        task.createdBy = userName.isEmpty ? nil : userName

        if isEditing {
            store.updateWorkTask(task)
        } else {
            store.addWorkTask(task)
        }
        Task {
            await workTaskTypeSync.syncForSelectedVineyard()
            await workTaskSync.syncForSelectedVineyard()
        }
        dismiss()
    }
}
