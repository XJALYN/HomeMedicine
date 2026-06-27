import SwiftUI
import SwiftData

struct MedicineListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Query(sort: \Medicine.updatedAt, order: .reverse) private var medicines: [Medicine]

    @State private var searchText = ""
    @State private var selectedFilter: MedicineFilter = .all
    @State private var showAddMedicine = false

    private var snapshots: [MedicineSnapshot] {
        medicines.map { $0.snapshot(thresholdDays: settingsStore.expiringThresholdDays) }
    }

    private var filtered: [MedicineSnapshot] {
        MedicineFilterService.filter(medicines: snapshots, filter: selectedFilter, searchText: searchText)
    }

    private var counts: [MedicineFilter: Int] {
        MedicineFilterService.counts(for: snapshots)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    searchBar
                    filterChips
                    medicineCards
                }
            }
            .background(AppTheme.background)
            .navigationTitle(L10n.t("app.title", locale: localizationManager.locale))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddMedicine = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.primary)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(L10n.t("add.title", locale: localizationManager.locale))
                }
            }
        }
        .sheet(isPresented: $showAddMedicine) {
            AddMedicineView(onSaved: { showAddMedicine = false })
        }
        .preferredColorScheme(.light)
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("app.subtitle", locale: localizationManager.locale))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.textMuted)
                TextField(L10n.t("search.placeholder", locale: localizationManager.locale), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.searchBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.white)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MedicineFilter.allCases) { filter in
                    FilterChip(
                        title: filterTitle(filter),
                        count: counts[filter] ?? 0,
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.white)
    }

    private var medicineCards: some View {
        LazyVStack(spacing: 12) {
            if filtered.isEmpty {
                emptyState
            } else {
                ForEach(filtered) { snapshot in
                    if let medicine = medicines.first(where: { $0.id == snapshot.id }) {
                        NavigationLink {
                            MedicineDetailView(medicine: medicine)
                        } label: {
                            MedicineCardView(
                                snapshot: snapshot,
                                medicine: medicine,
                                locale: localizationManager.locale
                            )
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cross.case")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.textMuted)
            Text(L10n.t("list.empty", locale: localizationManager.locale))
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func filterTitle(_ filter: MedicineFilter) -> String {
        switch filter {
        case .all: return L10n.t("filter.all", locale: localizationManager.locale)
        case .expiring: return L10n.t("filter.expiring", locale: localizationManager.locale)
        case .expired: return L10n.t("filter.expired", locale: localizationManager.locale)
        case .normal: return L10n.t("filter.normal", locale: localizationManager.locale)
        }
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(title) (\(count))")
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.primary : Color.white)
                .clipShape(Capsule())
                .overlay {
                    if !isSelected {
                        Capsule().stroke(AppTheme.border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

struct MedicineCardView: View {
    let snapshot: MedicineSnapshot
    let medicine: Medicine
    let locale: Locale

    private var statusColor: Color {
        switch snapshot.status {
        case .normal: return AppTheme.normal
        case .expiring: return AppTheme.expiring
        case .expired: return AppTheme.expired
        case .depleted: return AppTheme.depleted
        }
    }

    private var borderColor: Color {
        switch snapshot.status {
        case .expired: return AppTheme.expired.opacity(0.3)
        case .expiring: return AppTheme.expiring.opacity(0.3)
        default: return AppTheme.border
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            MedicineCoverThumbnail(
                medicine: medicine,
                size: 56,
                placeholderColor: statusColor
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(snapshot.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    StatusBadge(status: snapshot.status, locale: locale)
                }
                Text(snapshot.symptoms)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                HStack {
                    Text(L10n.t("list.remaining", locale: locale) + ": \(snapshot.quantity)\(MedicineUnits.localized(snapshot.unit, locale: locale))")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textMuted)
                    Spacer()
                    expiryLabel
                }
            }
        }
        .padding(16)
        .cardStyle(borderColor: borderColor)
    }

    @ViewBuilder
    private var expiryLabel: some View {
        if snapshot.status == .expired {
            Text(L10n.t("status.expired_on", locale: locale) + ": \(snapshot.expiryDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.expired)
        } else if snapshot.status == .expiring {
            Text(L10n.t("status.days_left", locale: locale, days: snapshot.daysUntilExpiry))
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.expiring)
        } else {
            Text(snapshot.expiryDate.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(AppTheme.textMuted)
        }
    }
}

struct StatusBadge: View {
    let status: MedicineStatus
    let locale: Locale

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(Capsule())
    }

    private var title: String {
        switch status {
        case .normal: return L10n.t("status.normal", locale: locale)
        case .expiring: return L10n.t("status.expiring", locale: locale)
        case .expired: return L10n.t("status.expired", locale: locale)
        case .depleted: return L10n.t("status.depleted", locale: locale)
        }
    }

    private var foreground: Color {
        switch status {
        case .normal: return AppTheme.normal
        case .expiring: return AppTheme.amber
        case .expired: return AppTheme.expired
        case .depleted: return AppTheme.depleted
        }
    }

    private var background: Color { foreground.opacity(0.15) }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
