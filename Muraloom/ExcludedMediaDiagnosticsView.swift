import SwiftUI

struct ExcludedMediaDiagnosticsView: View {
    let diagnostics: AlbumScanDiagnostics
    let albumName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedStage: ExclusionStage = .wallpaperFilters
    @State private var selectedReason: ExclusionReason?

    private var stageItems: [ExcludedMediaItem] {
        diagnostics
            .exclusions(for: selectedStage)
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private var reasonCounts: [(reason: ExclusionReason, count: Int)] {
        let counts = Dictionary(grouping: stageItems, by: \.reason).mapValues(\.count)
        return counts
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.reason.label < rhs.reason.label
                }
                return lhs.count > rhs.count
            }
    }

    private var filteredItems: [ExcludedMediaItem] {
        guard let selectedReason else { return stageItems }
        return stageItems.filter { $0.reason == selectedReason }
    }

    private func stageLabel(_ stage: ExclusionStage) -> String {
        "\(stage.displayName) (\(diagnostics.exclusions(for: stage).count))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Excluded Photos (Last Full Scan)")
                        .font(.title3.weight(.semibold))
                    if let albumName, albumName.isEmpty == false {
                        Text(albumName)
                            .foregroundStyle(.secondary)
                    }
                    Text("Scanned \(diagnostics.scannedAt, style: .relative)")
                        .foregroundStyle(.secondary)
                        .font(.system(.caption))
                }

                Spacer()

                Button("Done") { dismiss() }
            }

            Picker("Excluded category", selection: $selectedStage) {
                ForEach(ExclusionStage.allCases) { stage in
                    Text(stageLabel(stage)).tag(stage)
                }
            }
            .pickerStyle(.segmented)

            if stageItems.isEmpty {
                Text("No excluded media in this category for the latest scan.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("All (\(stageItems.count))") {
                            selectedReason = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(selectedReason == nil ? .accentColor : .gray.opacity(0.25))

                        ForEach(Array(reasonCounts.enumerated()), id: \.offset) { _, entry in
                            Button("\(entry.reason.label) (\(entry.count))") {
                                selectedReason = entry.reason
                            }
                            .buttonStyle(.bordered)
                            .tint(selectedReason == entry.reason ? .accentColor : .gray.opacity(0.25))
                        }
                    }
                    .padding(.vertical, 2)
                }

                List(Array(filteredItems.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 12) {
                        if let url = item.webUrl {
                            Link(item.name, destination: url)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text(item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 8)

                        Text(item.reason.label)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .frame(minWidth: 740, minHeight: 520)
        .onAppear {
            if diagnostics.wallpaperFilterExclusions.isEmpty, diagnostics.nonUsableExclusions.isEmpty == false {
                selectedStage = .notUsableMedia
            }
        }
        .onChange(of: selectedStage) { _, _ in
            selectedReason = nil
        }
    }
}
