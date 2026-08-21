import SwiftUI

/// Reports what an import actually changed.
///
/// A merge that only says "done" is untrustworthy — the interesting numbers are the ones
/// it skipped and the images it could not find.
struct ArchiveImportSummaryView: View {

    let result: ArchiveImportResult

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                row("archive.import.inserted", value: result.inserted)
                row("archive.import.updated", value: result.updated)
                row("archive.import.skipped", value: result.skipped)
                if result.missingImages > 0 {
                    row("archive.import.missingImages", value: result.missingImages)
                }

                Section {
                    Text(result.changedAnything
                         ? "archive.import.summary.changed"
                         : "archive.import.summary.unchanged")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                }
            }
            .navigationTitle("archive.import.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }

    private func row(_ key: LocalizedStringKey, value: Int) -> some View {
        LabeledContent {
            Text(value.formatted()).monospacedDigit()
        } label: {
            Text(key)
        }
    }
}
