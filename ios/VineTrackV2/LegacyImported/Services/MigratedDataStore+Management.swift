import Foundation

extension MigratedDataStore {

    // MARK: - Persistence keys (mirrors private keys in MigratedDataStore.swift)

    private enum MgmtKeys {
        static let paddocks = "vinetrack_paddocks"
        static let tractors = "vinetrack_tractors"
        static let fuelPurchases = "vinetrack_fuel_purchases"
        static let operatorCategories = "vinetrack_operator_categories"
        static let buttonTemplates = "vinetrack_button_templates"
        static let grapeVarieties = "vinetrack_grape_varieties"
    }

    private var persistenceStore: PersistenceStore { .shared }

    // MARK: - Spray Equipment

    func addSprayEquipment(_ item: SprayEquipmentItem) {
        guard let vineyardId = selectedVineyardId else { return }
        var entry = item
        entry.vineyardId = vineyardId
        sprayEquipment.append(entry)
        sprayRepo.saveEquipmentSlice(sprayEquipment, for: vineyardId)
        onSprayEquipmentChanged?(entry.id)
    }

    func updateSprayEquipment(_ item: SprayEquipmentItem) {
        guard let vineyardId = selectedVineyardId else { return }
        guard let idx = sprayEquipment.firstIndex(where: { $0.id == item.id }) else { return }
        sprayEquipment[idx] = item
        sprayRepo.saveEquipmentSlice(sprayEquipment, for: vineyardId)
        onSprayEquipmentChanged?(item.id)
    }

    func deleteSprayEquipment(_ item: SprayEquipmentItem) {
        guard let vineyardId = selectedVineyardId else { return }
        sprayEquipment.removeAll { $0.id == item.id }
        sprayRepo.saveEquipmentSlice(sprayEquipment, for: vineyardId)
        onSprayEquipmentDeleted?(item.id)
    }

    func applyRemoteSprayEquipmentUpsert(_ item: SprayEquipmentItem) {
        if selectedVineyardId == item.vineyardId {
            if let idx = sprayEquipment.firstIndex(where: { $0.id == item.id }) {
                sprayEquipment[idx] = item
            } else {
                sprayEquipment.append(item)
            }
            sprayRepo.saveEquipmentSlice(sprayEquipment, for: item.vineyardId)
        } else {
            var all = sprayRepo.loadAllEquipment()
            if let idx = all.firstIndex(where: { $0.id == item.id }) {
                all[idx] = item
            } else {
                all.append(item)
            }
            sprayRepo.replaceEquipment(all.filter { $0.vineyardId == item.vineyardId }, for: item.vineyardId)
        }
    }

    func applyRemoteSprayEquipmentDelete(_ id: UUID) {
        if let vineyardId = selectedVineyardId {
            sprayEquipment.removeAll { $0.id == id }
            sprayRepo.saveEquipmentSlice(sprayEquipment, for: vineyardId)
        }
        var all = sprayRepo.loadAllEquipment()
        if let removed = all.first(where: { $0.id == id }) {
            all.removeAll { $0.id == id }
            sprayRepo.replaceEquipment(all.filter { $0.vineyardId == removed.vineyardId }, for: removed.vineyardId)
        }
    }

    // MARK: - Tractors

    private func saveTractorsToDisk() {
        guard let vineyardId = selectedVineyardId else { return }
        var all: [Tractor] = persistenceStore.load(key: MgmtKeys.tractors) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: tractors.filter { $0.vineyardId == vineyardId })
        persistenceStore.save(all, key: MgmtKeys.tractors)
    }

    func addTractor(_ tractor: Tractor) {
        guard let vineyardId = selectedVineyardId else { return }
        var entry = tractor
        entry.vineyardId = vineyardId
        tractors.append(entry)
        saveTractorsToDisk()
        onTractorChanged?(entry.id)
    }

    func updateTractor(_ tractor: Tractor) {
        guard let idx = tractors.firstIndex(where: { $0.id == tractor.id }) else { return }
        tractors[idx] = tractor
        saveTractorsToDisk()
        onTractorChanged?(tractor.id)
    }

    func deleteTractor(_ tractor: Tractor) {
        tractors.removeAll { $0.id == tractor.id }
        saveTractorsToDisk()
        onTractorDeleted?(tractor.id)
    }

    func applyRemoteTractorUpsert(_ tractor: Tractor) {
        if let idx = tractors.firstIndex(where: { $0.id == tractor.id }) {
            tractors[idx] = tractor
        } else {
            tractors.append(tractor)
        }
        var all: [Tractor] = persistenceStore.load(key: MgmtKeys.tractors) ?? []
        if let idx = all.firstIndex(where: { $0.id == tractor.id }) {
            all[idx] = tractor
        } else {
            all.append(tractor)
        }
        persistenceStore.save(all, key: MgmtKeys.tractors)
    }

    func applyRemoteTractorDelete(_ id: UUID) {
        tractors.removeAll { $0.id == id }
        var all: [Tractor] = persistenceStore.load(key: MgmtKeys.tractors) ?? []
        all.removeAll { $0.id == id }
        persistenceStore.save(all, key: MgmtKeys.tractors)
    }

    // MARK: - Fuel Purchases

    private func saveFuelPurchasesToDisk() {
        guard let vineyardId = selectedVineyardId else { return }
        var all: [FuelPurchase] = persistenceStore.load(key: MgmtKeys.fuelPurchases) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: fuelPurchases.filter { $0.vineyardId == vineyardId })
        persistenceStore.save(all, key: MgmtKeys.fuelPurchases)
    }

    func addFuelPurchase(_ purchase: FuelPurchase) {
        guard let vineyardId = selectedVineyardId else { return }
        var entry = purchase
        entry.vineyardId = vineyardId
        fuelPurchases.append(entry)
        saveFuelPurchasesToDisk()
        onFuelPurchaseChanged?(entry.id)
    }

    func updateFuelPurchase(_ purchase: FuelPurchase) {
        guard let idx = fuelPurchases.firstIndex(where: { $0.id == purchase.id }) else { return }
        fuelPurchases[idx] = purchase
        saveFuelPurchasesToDisk()
        onFuelPurchaseChanged?(purchase.id)
    }

    func deleteFuelPurchase(_ purchase: FuelPurchase) {
        fuelPurchases.removeAll { $0.id == purchase.id }
        saveFuelPurchasesToDisk()
        onFuelPurchaseDeleted?(purchase.id)
    }

    func applyRemoteFuelPurchaseUpsert(_ purchase: FuelPurchase) {
        if let idx = fuelPurchases.firstIndex(where: { $0.id == purchase.id }) {
            fuelPurchases[idx] = purchase
        } else {
            fuelPurchases.append(purchase)
        }
        var all: [FuelPurchase] = persistenceStore.load(key: MgmtKeys.fuelPurchases) ?? []
        if let idx = all.firstIndex(where: { $0.id == purchase.id }) {
            all[idx] = purchase
        } else {
            all.append(purchase)
        }
        persistenceStore.save(all, key: MgmtKeys.fuelPurchases)
    }

    func applyRemoteFuelPurchaseDelete(_ id: UUID) {
        fuelPurchases.removeAll { $0.id == id }
        var all: [FuelPurchase] = persistenceStore.load(key: MgmtKeys.fuelPurchases) ?? []
        all.removeAll { $0.id == id }
        persistenceStore.save(all, key: MgmtKeys.fuelPurchases)
    }

    // MARK: - Operator Categories

    private func saveOperatorCategoriesToDisk() {
        guard let vineyardId = selectedVineyardId else { return }
        var all: [OperatorCategory] = persistenceStore.load(key: MgmtKeys.operatorCategories) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: operatorCategories.filter { $0.vineyardId == vineyardId })
        persistenceStore.save(all, key: MgmtKeys.operatorCategories)
    }

    func addOperatorCategory(_ category: OperatorCategory) {
        guard let vineyardId = selectedVineyardId else { return }
        var entry = category
        entry.vineyardId = vineyardId
        operatorCategories.append(entry)
        saveOperatorCategoriesToDisk()
        onOperatorCategoryChanged?(entry.id)
    }

    func updateOperatorCategory(_ category: OperatorCategory) {
        guard let idx = operatorCategories.firstIndex(where: { $0.id == category.id }) else { return }
        operatorCategories[idx] = category
        saveOperatorCategoriesToDisk()
        onOperatorCategoryChanged?(category.id)
    }

    func deleteOperatorCategory(_ category: OperatorCategory) {
        operatorCategories.removeAll { $0.id == category.id }
        saveOperatorCategoriesToDisk()
        onOperatorCategoryDeleted?(category.id)
    }

    func applyRemoteOperatorCategoryUpsert(_ category: OperatorCategory) {
        if let idx = operatorCategories.firstIndex(where: { $0.id == category.id }) {
            operatorCategories[idx] = category
        } else {
            operatorCategories.append(category)
        }
        var all: [OperatorCategory] = persistenceStore.load(key: MgmtKeys.operatorCategories) ?? []
        if let idx = all.firstIndex(where: { $0.id == category.id }) {
            all[idx] = category
        } else {
            all.append(category)
        }
        persistenceStore.save(all, key: MgmtKeys.operatorCategories)
    }

    func applyRemoteOperatorCategoryDelete(_ id: UUID) {
        operatorCategories.removeAll { $0.id == id }
        var all: [OperatorCategory] = persistenceStore.load(key: MgmtKeys.operatorCategories) ?? []
        all.removeAll { $0.id == id }
        persistenceStore.save(all, key: MgmtKeys.operatorCategories)
    }

    // MARK: - Work Task Types

    func addWorkTaskType(_ type: WorkTaskType) {
        guard let vineyardId = selectedVineyardId else { return }
        var entry = type
        entry.vineyardId = vineyardId
        // Case-insensitive de-dupe within the current vineyard.
        let trimmed = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if workTaskTypes.contains(where: {
            $0.vineyardId == vineyardId &&
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased()
        }) { return }
        workTaskTypes.append(entry)
        workTaskTypeRepo.saveSlice(workTaskTypes, for: vineyardId)
        onWorkTaskTypeChanged?(entry.id)
    }

    func updateWorkTaskType(_ type: WorkTaskType) {
        guard let vineyardId = selectedVineyardId else { return }
        guard let idx = workTaskTypes.firstIndex(where: { $0.id == type.id }) else { return }
        workTaskTypes[idx] = type
        workTaskTypeRepo.saveSlice(workTaskTypes, for: vineyardId)
        onWorkTaskTypeChanged?(type.id)
    }

    func deleteWorkTaskType(_ type: WorkTaskType) {
        guard let vineyardId = selectedVineyardId else { return }
        workTaskTypes.removeAll { $0.id == type.id }
        workTaskTypeRepo.saveSlice(workTaskTypes, for: vineyardId)
        onWorkTaskTypeDeleted?(type.id)
    }

    func applyRemoteWorkTaskTypeUpsert(_ type: WorkTaskType) {
        if selectedVineyardId == type.vineyardId {
            if let idx = workTaskTypes.firstIndex(where: { $0.id == type.id }) {
                workTaskTypes[idx] = type
            } else {
                workTaskTypes.append(type)
            }
            workTaskTypeRepo.saveSlice(workTaskTypes, for: type.vineyardId)
        } else {
            var all = workTaskTypeRepo.loadAll()
            if let idx = all.firstIndex(where: { $0.id == type.id }) {
                all[idx] = type
            } else {
                all.append(type)
            }
            workTaskTypeRepo.saveSlice(all.filter { $0.vineyardId == type.vineyardId }, for: type.vineyardId)
        }
    }

    func applyRemoteWorkTaskTypeDelete(_ id: UUID) {
        if selectedVineyardId != nil {
            workTaskTypes.removeAll { $0.id == id }
        }
        var all = workTaskTypeRepo.loadAll()
        if let removed = all.first(where: { $0.id == id }) {
            all.removeAll { $0.id == id }
            workTaskTypeRepo.saveSlice(all.filter { $0.vineyardId == removed.vineyardId }, for: removed.vineyardId)
        }
    }

    // MARK: - Equipment Items ("Other" maintenance assets)

    func addEquipmentItem(_ item: EquipmentItem) {
        guard let vineyardId = selectedVineyardId else { return }
        var entry = item
        entry.vineyardId = vineyardId
        let trimmed = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if equipmentItems.contains(where: {
            $0.vineyardId == vineyardId &&
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased()
        }) { return }
        equipmentItems.append(entry)
        equipmentItemRepo.saveSlice(equipmentItems, for: vineyardId)
        onEquipmentItemChanged?(entry.id)
    }

    func updateEquipmentItem(_ item: EquipmentItem) {
        guard let vineyardId = selectedVineyardId else { return }
        guard let idx = equipmentItems.firstIndex(where: { $0.id == item.id }) else { return }
        equipmentItems[idx] = item
        equipmentItemRepo.saveSlice(equipmentItems, for: vineyardId)
        onEquipmentItemChanged?(item.id)
    }

    func deleteEquipmentItem(_ item: EquipmentItem) {
        guard let vineyardId = selectedVineyardId else { return }
        equipmentItems.removeAll { $0.id == item.id }
        equipmentItemRepo.saveSlice(equipmentItems, for: vineyardId)
        onEquipmentItemDeleted?(item.id)
    }

    func applyRemoteEquipmentItemUpsert(_ item: EquipmentItem) {
        if selectedVineyardId == item.vineyardId {
            if let idx = equipmentItems.firstIndex(where: { $0.id == item.id }) {
                equipmentItems[idx] = item
            } else {
                equipmentItems.append(item)
            }
            equipmentItemRepo.saveSlice(equipmentItems, for: item.vineyardId)
        } else {
            var all = equipmentItemRepo.loadAll()
            if let idx = all.firstIndex(where: { $0.id == item.id }) {
                all[idx] = item
            } else {
                all.append(item)
            }
            equipmentItemRepo.saveSlice(all.filter { $0.vineyardId == item.vineyardId }, for: item.vineyardId)
        }
    }

    func applyRemoteEquipmentItemDelete(_ id: UUID) {
        if selectedVineyardId != nil {
            equipmentItems.removeAll { $0.id == id }
        }
        var all = equipmentItemRepo.loadAll()
        if let removed = all.first(where: { $0.id == id }) {
            all.removeAll { $0.id == id }
            equipmentItemRepo.saveSlice(all.filter { $0.vineyardId == removed.vineyardId }, for: removed.vineyardId)
        }
    }

    @discardableResult
    func deduplicateOperatorCategories() -> Int {
        guard let vineyardId = selectedVineyardId else { return 0 }
        var seen: [String: OperatorCategory] = [:]
        var keptOrder: [OperatorCategory] = []
        var duplicateIdToKeptId: [UUID: UUID] = [:]

        for cat in operatorCategories {
            let key = cat.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let existing = seen[key] {
                let winner = (cat.costPerHour > existing.costPerHour) ? cat : existing
                let loser = (winner.id == cat.id) ? existing : cat
                if winner.id != existing.id {
                    if let idx = keptOrder.firstIndex(where: { $0.id == existing.id }) {
                        keptOrder[idx] = winner
                    }
                    seen[key] = winner
                }
                duplicateIdToKeptId[loser.id] = winner.id
            } else {
                seen[key] = cat
                keptOrder.append(cat)
            }
        }

        let removedCount = operatorCategories.count - keptOrder.count
        guard removedCount > 0 else { return 0 }

        operatorCategories = keptOrder
        saveOperatorCategoriesToDisk()

        if let vineyardIndex = vineyards.firstIndex(where: { $0.id == vineyardId }) {
            var updated = vineyards[vineyardIndex]
            var changed = false
            for i in updated.users.indices {
                if let cid = updated.users[i].operatorCategoryId, let newId = duplicateIdToKeptId[cid] {
                    updated.users[i].operatorCategoryId = newId
                    changed = true
                }
            }
            if changed {
                updateVineyard(updated)
            }
        }

        for (dupId, _) in duplicateIdToKeptId {
            onOperatorCategoryDeleted?(dupId)
        }

        return removedCount
    }

    // MARK: - Grape Varieties (CRUD)

    private func saveGrapeVarietiesToDisk() {
        guard let vineyardId = selectedVineyardId else { return }
        var all: [GrapeVariety] = persistenceStore.load(key: MgmtKeys.grapeVarieties) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: grapeVarieties.filter { $0.vineyardId == vineyardId })
        persistenceStore.save(all, key: MgmtKeys.grapeVarieties)
    }

    func addGrapeVariety(_ variety: GrapeVariety) {
        guard let vineyardId = selectedVineyardId else { return }
        var entry = variety
        entry.vineyardId = vineyardId
        grapeVarieties.append(entry)
        saveGrapeVarietiesToDisk()
    }

    func updateGrapeVariety(_ variety: GrapeVariety) {
        guard let idx = grapeVarieties.firstIndex(where: { $0.id == variety.id }) else { return }
        grapeVarieties[idx] = variety
        saveGrapeVarietiesToDisk()
    }

    func deleteGrapeVariety(_ variety: GrapeVariety) {
        grapeVarieties.removeAll { $0.id == variety.id }
        saveGrapeVarietiesToDisk()
    }

    // MARK: - Button Templates

    private func saveButtonTemplatesToDisk() {
        guard let vineyardId = selectedVineyardId else { return }
        var all: [ButtonTemplate] = persistenceStore.load(key: MgmtKeys.buttonTemplates) ?? []
        all.removeAll { $0.vineyardId == vineyardId }
        all.append(contentsOf: buttonTemplates.filter { $0.vineyardId == vineyardId })
        persistenceStore.save(all, key: MgmtKeys.buttonTemplates)
    }

    func buttonTemplates(for mode: PinMode) -> [ButtonTemplate] {
        buttonTemplates.filter { $0.mode == mode }
    }

    func addButtonTemplate(_ template: ButtonTemplate) {
        guard let vineyardId = selectedVineyardId else { return }
        var entry = template
        entry.vineyardId = vineyardId
        buttonTemplates.append(entry)
        saveButtonTemplatesToDisk()
    }

    func updateButtonTemplate(_ template: ButtonTemplate) {
        guard let idx = buttonTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        buttonTemplates[idx] = template
        saveButtonTemplatesToDisk()
    }

    func deleteButtonTemplate(_ template: ButtonTemplate) {
        buttonTemplates.removeAll { $0.id == template.id }
        saveButtonTemplatesToDisk()
    }

    /// Apply a template to the active button set for its mode, replacing existing buttons.
    func applyButtonTemplate(_ template: ButtonTemplate) {
        guard let vineyardId = selectedVineyardId else { return }
        let configs = template.toButtonConfigs(for: vineyardId)
        switch template.mode {
        case .repairs:
            updateRepairButtons(configs)
        case .growth:
            updateGrowthButtons(configs)
        }
    }

    // MARK: - Vineyard update (used by operator-category user assignment)

    func updateVineyard(_ vineyard: Vineyard) {
        vineyards = vineyardRepo.upsert(vineyard)
    }
}
