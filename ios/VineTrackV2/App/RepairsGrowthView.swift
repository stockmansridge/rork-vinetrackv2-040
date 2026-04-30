import SwiftUI
import CoreLocation

struct RepairsGrowthView: View {
    enum Tab: Int, Hashable { case repairs = 0, growth = 1 }

    @Environment(MigratedDataStore.self) private var store
    @Environment(NewBackendAuthService.self) private var auth
    @Environment(LocationService.self) private var locationService
    @Environment(BackendAccessControl.self) private var accessControl

    @State private var selection: Tab
    @State private var showEditButtons: Bool = false
    @State private var showGrowthPicker: Bool = false
    @State private var lastGrowthStage: GrowthStage?
    @State private var errorMessage: String?
    @State private var pinToast: PinDroppedToastInfo?
    @State private var pendingPhotoPinId: UUID?
    @State private var showPhotoPicker: Bool = false

    init(initial: Tab = .repairs) {
        _selection = State(initialValue: initial)
    }

    private var canCreate: Bool { accessControl.canCreateOperationalRecords }
    private var canEdit: Bool { accessControl.canChangeSettings }

    /// All non-growth-stage repair buttons sorted by index.
    private var repairButtons: [ButtonConfig] {
        store.repairButtons
            .filter { !$0.isGrowthStageButton }
            .sorted { $0.index < $1.index }
    }

    /// All non-growth-stage growth observation buttons sorted by index.
    private var growthButtons: [ButtonConfig] {
        store.growthButtons
            .filter { !$0.isGrowthStageButton }
            .sorted { $0.index < $1.index }
    }

    private func leftHalf(_ buttons: [ButtonConfig]) -> [ButtonConfig] {
        let half = max(buttons.count / 2, 0)
        return Array(buttons.prefix(half))
    }

    private func rightHalf(_ buttons: [ButtonConfig]) -> [ButtonConfig] {
        let half = max(buttons.count / 2, 0)
        return buttons.count > half ? Array(buttons.dropFirst(half)) : []
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentHeader
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 6)

            TabView(selection: $selection) {
                repairsPage
                    .tag(Tab.repairs)
                growthPage
                    .tag(Tab.growth)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: selection)

            if let errorMessage {
                FeedbackBar(message: errorMessage, kind: .destructive)
                    .padding(.bottom, 8)
            }
        }
        .background(VineyardTheme.appBackground)
        .pinDroppedToast($pinToast)
        .navigationTitle(store.selectedVineyard?.name ?? "Vineyard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEditButtons = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditButtons) {
            EditButtonsSheet(mode: selection == .repairs ? .repairs : .growth)
        }
        .sheet(isPresented: $showGrowthPicker) {
            GrowthStagePickerSheet { stage in
                lastGrowthStage = stage
                handleGrowthStageSelected(stage)
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            CameraImagePicker { data in
                attachPhoto(data: data)
            }
            .ignoresSafeArea()
        }
    }

    private func attachPhoto(data: Data?) {
        defer { pendingPhotoPinId = nil }
        guard let data, let pinId = pendingPhotoPinId else { return }
        guard var pin = store.pins.first(where: { $0.id == pinId }) else { return }
        pin.photoData = data
        store.updatePin(pin)
    }

    // MARK: - Segmented header

    private var segmentHeader: some View {
        HStack(spacing: 8) {
            segmentButton(title: "Repairs", tab: .repairs) {
                Image(systemName: "wrench.fill")
                    .font(.subheadline.weight(.bold))
            }
            segmentButton(title: "Growth", tab: .growth) {
                GrapeLeafIcon(size: 18, color: selection == .growth ? .white : .primary)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private func segmentButton<Icon: View>(title: String, tab: Tab, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selection = tab }
        } label: {
            HStack(spacing: 6) {
                icon()
                Text(title)
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(selection == tab ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                selection == tab ? VineyardTheme.primary : Color.clear,
                in: .rect(cornerRadius: 9)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Repairs page

    private var repairsPage: some View {
        VStack(spacing: 0) {
            if !canCreate { PermissionRow().padding(.bottom, 6) }
            if repairButtons.isEmpty {
                EmptyButtonsState(canEdit: canEdit, showEditButtons: $showEditButtons)
                    .padding(.horizontal)
                    .padding(.top, 12)
                Spacer()
            } else {
                leftRightButtonGrid(buttons: repairButtons)
            }
        }
    }

    // MARK: - Growth page

    private var growthPage: some View {
        VStack(spacing: 10) {
            if !canCreate { PermissionRow() }
            growthStageBar
                .padding(.horizontal)

            if growthButtons.isEmpty {
                EmptyButtonsState(canEdit: canEdit, showEditButtons: $showEditButtons)
                    .padding(.horizontal)
                Spacer()
            } else {
                leftRightButtonGrid(buttons: growthButtons)
            }
        }
        .padding(.top, 4)
    }

    private var growthStageBar: some View {
        Button {
            guard canCreate else { return }
            showGrowthPicker = true
        } label: {
            HStack(spacing: 12) {
                GrapeLeafIcon(size: 22, color: .white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Growth Stage")
                        .font(.headline.weight(.bold))
                    if let stage = lastGrowthStage {
                        Text("EL \(stage.code) — \(stage.description)")
                            .font(.caption)
                            .lineLimit(1)
                            .opacity(0.9)
                    } else {
                        Text("Tap to select current E-L stage")
                            .font(.caption)
                            .opacity(0.9)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.18, green: 0.55, blue: 0.28), Color(red: 0.12, green: 0.42, blue: 0.20)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: .rect(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canCreate)
    }

    // MARK: - Left/Right grid

    private func leftRightButtonGrid(buttons: [ButtonConfig]) -> some View {
        let left = leftHalf(buttons)
        let right = rightHalf(buttons)
        let rowCount = max(left.count, right.count)
        return VStack(spacing: 8) {
            HStack {
                Text("LEFT")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Text("RIGHT")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)

            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 10) {
                    ForEach(left) { btn in
                        FillingActionTile(button: btn, canCreate: canCreate) {
                            handleButtonTap(button: btn, side: .left)
                        }
                    }
                    ForEach(0..<max(rowCount - left.count, 0), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 10) {
                    ForEach(right) { btn in
                        FillingActionTile(button: btn, canCreate: canCreate) {
                            handleButtonTap(button: btn, side: .right)
                        }
                    }
                    ForEach(0..<max(rowCount - right.count, 0), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .padding(.top, 6)
    }

    // MARK: - Actions

    private func handleButtonTap(button: ButtonConfig, side: PinSide) {
        guard canCreate else { return }
        guard let coord = locationService.location?.coordinate else {
            showError("Location unavailable \u{2014} enable location services to drop a pin.")
            return
        }
        let heading = locationService.heading?.trueHeading ?? 0
        let pin = store.createPinFromButton(
            button: button,
            coordinate: coord,
            heading: heading,
            side: side,
            paddockId: nil,
            rowNumber: nil,
            createdBy: auth.userName
        )
        guard let createdPin = pin else {
            showError("Could not create pin \u{2014} no vineyard selected.")
            return
        }
        let sideLabel = side == .left ? "Left" : "Right"
        showPinToast(title: "\(button.name) pin dropped", subtitle: "\(sideLabel) side")
        if store.settings.autoPhotoPrompt {
            pendingPhotoPinId = createdPin.id
            showPhotoPicker = true
        }
    }

    private func handleGrowthStageSelected(_ stage: GrowthStage) {
        guard canCreate else { return }
        guard let coord = locationService.location?.coordinate else {
            showError("Location unavailable \u{2014} enable location services to drop a pin.")
            return
        }
        let heading = locationService.heading?.trueHeading ?? 0
        let pin = store.createGrowthStagePin(
            stageCode: stage.code,
            stageDescription: stage.description,
            coordinate: coord,
            heading: heading,
            side: .right,
            paddockId: nil,
            rowNumber: nil,
            createdBy: auth.userName
        )
        guard let createdPin = pin else {
            showError("Could not create pin \u{2014} no vineyard selected.")
            return
        }
        showPinToast(title: "Growth stage recorded", subtitle: "EL \(stage.code) \u{2022} \(stage.description)")
        if store.settings.autoPhotoPrompt {
            pendingPhotoPinId = createdPin.id
            showPhotoPicker = true
        }
    }

    private func showPinToast(title: String, subtitle: String) {
        pinToast = PinDroppedToastInfo(title: title, subtitle: subtitle)
        errorMessage = nil
    }

    private func showError(_ message: String) {
        errorMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if errorMessage == message { errorMessage = nil }
        }
    }
}

// MARK: - Filling tile (uses contextual icon)

struct FillingActionTile: View {
    let button: ButtonConfig
    let canCreate: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: "mappin")
                    .font(.title2.weight(.semibold))
                Text(button.name)
                    .font(.headline.weight(.heavy))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.fromString(button.color), Color.fromString(button.color).opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: .rect(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.black.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!canCreate)
        .opacity(canCreate ? 1 : 0.55)
    }

    private var foreground: Color {
        let isLightColor = ["yellow", "white", "cyan"].contains(button.color.lowercased())
        return isLightColor ? .black : .white
    }
}
