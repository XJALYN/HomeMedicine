import SwiftUI
import SwiftData

struct AddMedicineView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var quotaStore: UsageQuotaStore
    @Query private var allMedicines: [Medicine]

    var editingMedicine: Medicine?
    var onSaved: (() -> Void)?

    @State private var name = ""
    @State private var nameEn = ""
    @State private var specification = ""
    @State private var unit = MedicineUnits.defaultStorageValue
    @State private var initialQuantity = 1
    @State private var quantity = 1
    @State private var expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var purchaseDate = Date()
    @State private var hasPurchaseDate = false
    @State private var symptoms = ""
    @State private var storageLocation = ""
    @State private var usage = ""
    @State private var notes = ""
    @State private var selectedTags: Set<String> = []
    @State private var manufacturer = ""
    @State private var approvalNumber = ""
    @State private var isOTC = true
    @State private var batchNumber = ""
    @State private var barcode = ""
    @State private var expiryNotifyEnabled = true
    @State private var showBoxScan = false
    @State private var showOCR = false
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var paywallTrigger: PaywallTrigger?
    @State private var boxPhotos: [UIImage?] = Array(repeating: nil, count: MedicineBoxFace.count)
    @State private var savedPhotoPaths: [String?] = Array(repeating: nil, count: MedicineBoxFace.count)
    @State private var draftMedicineId = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    scanButton
                    if hasBoxPhotos {
                        boxPhotosSection
                    }
                    divider
                    basicSection
                    quantitySection
                    dateSection
                    optionalSection
                    tagsSection
                    notifyToggle
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .background(AppTheme.background)
            .navigationTitle(editingMedicine == nil
                ? L10n.t("add.title", locale: localizationManager.locale)
                : L10n.t("edit.title", locale: localizationManager.locale))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { saveBar }
            .sheet(isPresented: $showBoxScan) {
                MedicineBoxScanView { result, photos in
                    if let result {
                        applyRecognitionResult(result, photos: photos)
                    } else {
                        applyPhotosOnly(photos)
                    }
                }
            }
            .sheet(item: $paywallTrigger) { trigger in
                PaywallView(trigger: trigger)
            }
            .sheet(isPresented: $showOCR) {
                ExpiryOCRView { date in
                    expiryDate = date
                }
            }
            .alert(L10n.t("validation.title", locale: localizationManager.locale), isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button(L10n.t("action.ok", locale: localizationManager.locale), role: .cancel) {}
            } message: {
                Text(validationMessage ?? "")
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .onAppear(perform: loadEditingData)
        }
        .preferredColorScheme(.light)
    }

    private var hasBoxPhotos: Bool {
        boxPhotos.contains { $0 != nil }
    }

    private var boxPhotosSection: some View {
        FormSection(title: L10n.t("section.box_photos", locale: localizationManager.locale), required: false) {
            MedicineBoxPhotosEditorView(photos: $boxPhotos)
        }
    }

    private func applyPhotosOnly(_ photos: [UIImage?]) {
        boxPhotos = normalizedPhotos(photos)
    }

    private func applyRecognitionResult(_ result: MedicineRecognitionResult, photos: [UIImage?]) {
        boxPhotos = normalizedPhotos(photos)
        name = result.name
        specification = result.specification
        manufacturer = result.manufacturer ?? ""
        approvalNumber = result.approvalNumber ?? ""
        batchNumber = result.batchNumber ?? ""
        barcode = result.barcode ?? ""
        usage = result.usage ?? ""
        symptoms = result.symptoms ?? ""
        isOTC = result.isOTC
        if let unit = result.unit, MedicineUnits.contains(storageValue: unit) {
            self.unit = unit
        }
        if let qty = result.quantity, qty > 0 {
            initialQuantity = qty
            if editingMedicine == nil { quantity = qty }
        }
        if let expiry = result.expiryDate {
            expiryDate = expiry
        }
        if !result.tags.isEmpty {
            selectedTags = Set(result.tags)
        }
    }

    private func normalizedPhotos(_ photos: [UIImage?]) -> [UIImage?] {
        var result = Array(repeating: UIImage?.none, count: MedicineBoxFace.count)
        for index in 0..<min(photos.count, MedicineBoxFace.count) {
            result[index] = photos[index]
        }
        return result
    }

    private var medicineIdForPhotos: UUID {
        editingMedicine?.id ?? draftMedicineId
    }

    private var scanButton: some View {
        Button { showBoxScan = true } label: {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay { Image(systemName: "camera.viewfinder").foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("add.scan_box", locale: localizationManager.locale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(L10n.t("add.scan_box_hint", locale: localizationManager.locale))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
            .background(LinearGradient(colors: [AppTheme.primary, AppTheme.primaryDark], startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .shadow(color: AppTheme.primary.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var divider: some View {
        HStack {
            Rectangle().fill(AppTheme.border).frame(height: 1)
            Text(L10n.t("add.or_manual", locale: localizationManager.locale))
                .font(.caption)
                .foregroundStyle(AppTheme.textMuted)
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private var basicSection: some View {
        FormSection(title: L10n.t("section.basic", locale: localizationManager.locale), required: false) {
            voiceField(L10n.t("field.name", locale: localizationManager.locale) + " *", text: $name)
            voiceField(L10n.t("field.specification", locale: localizationManager.locale), text: $specification)
            Picker(L10n.t("field.unit", locale: localizationManager.locale), selection: $unit) {
                ForEach(MedicineUnits.all, id: \.self) { unitId in
                    Text(L10n.t("unit.\(unitId)", locale: localizationManager.locale))
                        .tag(MedicineUnits.storageValue(for: unitId))
                }
            }
            voiceField(L10n.t("field.symptoms", locale: localizationManager.locale), text: $symptoms)
            voiceField(L10n.t("field.storage_location", locale: localizationManager.locale), text: $storageLocation)
        }
    }

    private func voiceField(_ title: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VoiceInputField(title: title, text: text, locale: localizationManager.locale, axis: axis)
    }

    private var quantitySection: some View {
        FormSection(title: L10n.t("section.quantity", locale: localizationManager.locale), required: false) {
            Stepper(L10n.t("field.initial_quantity", locale: localizationManager.locale) + ": \(initialQuantity)", value: $initialQuantity, in: 1...999)
                .onChange(of: initialQuantity) { _, newValue in
                    if editingMedicine == nil { quantity = newValue }
                }
            if editingMedicine != nil {
                Stepper(L10n.t("field.remaining_quantity", locale: localizationManager.locale) + ": \(quantity)", value: $quantity, in: 0...999)
            }
        }
    }

    private var dateSection: some View {
        FormSection(title: L10n.t("section.dates", locale: localizationManager.locale), required: true) {
            DatePicker(L10n.t("field.expiry_date", locale: localizationManager.locale) + " *", selection: $expiryDate, displayedComponents: .date)
            HStack {
                Text(L10n.t("status.days_left", locale: localizationManager.locale, days: MedicineStatusCalculator.daysUntilExpiry(from: Date(), expiryDate: expiryDate)))
                    .font(.caption)
                    .foregroundStyle(AppTheme.primary)
                Spacer()
                Button(L10n.t("ocr.title", locale: localizationManager.locale)) { showOCR = true }
                    .font(.caption)
                    .foregroundStyle(AppTheme.primary)
            }
            Toggle(L10n.t("field.has_purchase_date", locale: localizationManager.locale), isOn: $hasPurchaseDate)
            if hasPurchaseDate {
                DatePicker(L10n.t("field.purchase_date", locale: localizationManager.locale), selection: $purchaseDate, displayedComponents: .date)
            }
        }
    }

    private var optionalSection: some View {
        FormSection(title: L10n.t("section.optional", locale: localizationManager.locale), required: false) {
            voiceField(L10n.t("field.usage", locale: localizationManager.locale), text: $usage)
            voiceField(L10n.t("field.notes", locale: localizationManager.locale), text: $notes, axis: .vertical)
            voiceField(L10n.t("field.manufacturer", locale: localizationManager.locale), text: $manufacturer)
            voiceField(L10n.t("field.approval_number", locale: localizationManager.locale), text: $approvalNumber)
            voiceField(L10n.t("field.batch_number", locale: localizationManager.locale), text: $batchNumber)
            Toggle(L10n.t("field.is_otc", locale: localizationManager.locale), isOn: $isOTC)
        }
    }

    private var tagsSection: some View {
        FormSection(title: L10n.t("section.tags", locale: localizationManager.locale), required: false) {
            FlowLayout(spacing: 8) {
                ForEach(MedicineTags.all, id: \.self) { tag in
                    TagChip(
                        title: L10n.t("tag.\(tag)", locale: localizationManager.locale),
                        isSelected: selectedTags.contains(tag)
                    ) {
                        if selectedTags.contains(tag) { selectedTags.remove(tag) }
                        else { selectedTags.insert(tag) }
                    }
                }
            }
        }
    }

    private var notifyToggle: some View {
        FormSection(title: L10n.t("section.notifications", locale: localizationManager.locale), required: false) {
            Toggle(L10n.t("field.expiry_notify", locale: localizationManager.locale), isOn: $expiryNotifyEnabled)
            Text(L10n.t("field.expiry_notify_hint", locale: localizationManager.locale))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var saveBar: some View {
        Button(action: save) {
            Text(L10n.t("action.save", locale: localizationManager.locale))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.minTouchTarget)
                .background(AppTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    private func loadEditingData() {
        guard let medicine = editingMedicine else { return }
        name = medicine.name
        nameEn = medicine.nameEn ?? ""
        specification = medicine.specification
        unit = medicine.unit
        initialQuantity = medicine.initialQuantity
        quantity = medicine.quantity
        expiryDate = medicine.expiryDate
        if let pd = medicine.purchaseDate {
            hasPurchaseDate = true
            purchaseDate = pd
        }
        symptoms = medicine.symptoms
        storageLocation = medicine.storageLocation
        usage = medicine.usage ?? ""
        notes = medicine.notes ?? ""
        selectedTags = Set(medicine.tags)
        manufacturer = medicine.manufacturer ?? ""
        approvalNumber = medicine.approvalNumber ?? ""
        isOTC = medicine.isOTC
        batchNumber = medicine.batchNumber ?? ""
        barcode = medicine.barcode ?? ""
        expiryNotifyEnabled = medicine.expiryNotifyEnabled
        savedPhotoPaths = medicine.boxPhotoPaths
        boxPhotos = MedicineBoxPhotoStore.loadPhotos(for: medicine, context: modelContext)
        draftMedicineId = medicine.id
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = L10n.t("validation.name_required", locale: localizationManager.locale)
            return
        }

        if editingMedicine == nil {
            let activeCount = EntitlementChecker.activeMedicineCount(
                in: allMedicines,
                thresholdDays: settingsStore.expiringThresholdDays
            )
            guard EntitlementChecker.canAddMedicine(currentCount: activeCount, tier: subscriptionManager.tier) else {
                paywallTrigger = .medicineLimit
                return
            }
        }

        isSaving = true
        defer { isSaving = false }

        if let medicine = editingMedicine {
            medicine.name = name
            medicine.nameEn = nameEn.isEmpty ? nil : nameEn
            medicine.specification = specification
            medicine.unit = unit
            medicine.initialQuantity = initialQuantity
            medicine.quantity = quantity
            medicine.expiryDate = expiryDate
            medicine.purchaseDate = hasPurchaseDate ? purchaseDate : nil
            medicine.symptoms = symptoms
            medicine.storageLocation = storageLocation
            medicine.usage = usage.isEmpty ? nil : usage
            medicine.notes = notes.isEmpty ? nil : notes
            medicine.tags = Array(selectedTags)
            medicine.manufacturer = manufacturer.isEmpty ? nil : manufacturer
            medicine.approvalNumber = approvalNumber.isEmpty ? nil : approvalNumber
            medicine.isOTC = isOTC
            medicine.batchNumber = batchNumber.isEmpty ? nil : batchNumber
            medicine.barcode = barcode.isEmpty ? nil : barcode
            medicine.expiryNotifyEnabled = expiryNotifyEnabled
            medicine.boxPhotoPaths = persistBoxPhotos(for: medicine)
            if quantity > 0 { medicine.archiveReason = nil; medicine.archivedAt = nil }
            medicine.touch()
            MedicineActionService.syncReminderStates(for: medicine, thresholdDays: settingsStore.expiringThresholdDays)
        } else {
            let medicine = Medicine(
                id: draftMedicineId,
                name: name,
                nameEn: nameEn.isEmpty ? nil : nameEn,
                specification: specification,
                unit: unit,
                initialQuantity: initialQuantity,
                quantity: initialQuantity,
                expiryDate: expiryDate,
                purchaseDate: hasPurchaseDate ? purchaseDate : nil,
                symptoms: symptoms,
                storageLocation: storageLocation,
                usage: usage.isEmpty ? nil : usage,
                notes: notes.isEmpty ? nil : notes,
                tags: Array(selectedTags),
                manufacturer: manufacturer.isEmpty ? nil : manufacturer,
                approvalNumber: approvalNumber.isEmpty ? nil : approvalNumber,
                isOTC: isOTC,
                batchNumber: batchNumber.isEmpty ? nil : batchNumber,
                barcode: barcode.isEmpty ? nil : barcode,
                expiryNotifyEnabled: expiryNotifyEnabled
            )
            modelContext.insert(medicine)
            let record = UsageRecord(type: .stockIn, dosage: "\(initialQuantity) \(unit)", medicine: medicine)
            modelContext.insert(record)
            persistBoxPhotos(for: medicine)
            let defaultCabinetName = L10n.t("sharing.default_cabinet_name", locale: localizationManager.locale)
            medicine.cabinet = try? CloudKitSyncService.ensureDefaultCabinet(in: modelContext, defaultName: defaultCabinetName)
        }

        try? modelContext.save()
        NotificationCenter.default.post(name: .scheduleNotifications, object: nil)
        if editingMedicine == nil {
            resetForm()
        }
        onSaved?()
    }

    private func resetForm() {
        name = ""
        nameEn = ""
        specification = ""
        unit = MedicineUnits.defaultStorageValue
        initialQuantity = 1
        quantity = 1
        expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        purchaseDate = Date()
        hasPurchaseDate = false
        symptoms = ""
        storageLocation = ""
        usage = ""
        notes = ""
        selectedTags = []
        manufacturer = ""
        approvalNumber = ""
        isOTC = true
        batchNumber = ""
        barcode = ""
        expiryNotifyEnabled = true
        boxPhotos = Array(repeating: nil, count: MedicineBoxFace.count)
        savedPhotoPaths = Array(repeating: nil, count: MedicineBoxFace.count)
        draftMedicineId = UUID()
        validationMessage = nil
    }

    private func persistBoxPhotos(for medicine: Medicine) -> [String?] {
        let images = hasBoxPhotos
            ? boxPhotos
            : Array(repeating: nil as UIImage?, count: MedicineBoxFace.count)
        try? MedicineBoxPhotoStore.syncPhotos(medicine: medicine, images: images, context: modelContext)
        return medicine.boxPhotoPaths
    }
}

struct FormSection<Content: View>: View {
    let title: String
    let required: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(AppTheme.primary).frame(width: 6, height: 16)
                Text(title).font(.subheadline.weight(.semibold))
                if required {
                    Text("*")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.expired)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.expired.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            VStack(spacing: 12) { content }
                .padding(16)
                .cardStyle()
        }
    }
}

struct FormField: View {
    let title: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(AppTheme.textSecondary)
            if axis == .vertical {
                TextField(title, text: $text, axis: .vertical).lineLimit(3...6)
            } else {
                TextField(title, text: $text)
            }
        }
    }
}

struct TagChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.primary : AppTheme.searchBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
