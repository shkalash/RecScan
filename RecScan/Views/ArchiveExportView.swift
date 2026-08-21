import SwiftUI

/// Creates a portable archive and hands it to the share sheet.
struct ArchiveExportView: View {

    let selection: [ReceiptSnapshot]

    @State private var model = ArchiveExportViewModel()
    @Environment(\.receiptStore) private var receiptStore
    @Environment(\.imageFileStore) private var imageFileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("archive.section.scope", selection: $model.scope) {
                        ForEach(ArchiveScope.allCases) { scope in
                            Text(String(localized: scope.titleKey)).tag(scope)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("archive.section.scope")
                } footer: {
                    Text("archive.scope.footer")
                }

                if model.scope == .currentSelection {
                    Section {
                        Text("export.selection.count \(selection.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section { generateOrShare } footer: {
                    Text("archive.export.footer")
                }
            }
            .navigationTitle("archive.export.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .errorAlert($model.presentedError)
        }
    }

    @ViewBuilder
    private var generateOrShare: some View {
        if let url = model.generatedURL {
            ShareLink(item: url) {
                Label("archive.action.share", systemImage: SystemImage.export)
            }
            Button("archive.action.regenerate") { Task { await generate() } }
        } else if model.isGenerating {
            HStack {
                ProgressView()
                Text("archive.status.generating").foregroundStyle(.secondary)
            }
        } else {
            Button("archive.action.create") { Task { await generate() } }
                .disabled(model.scope == .currentSelection && selection.isEmpty)
        }
    }

    private func generate() async {
        await model.generate(selection: selection, store: receiptStore, fileStore: imageFileStore)
    }
}

#if DEBUG
#Preview("Archive export") {
    ArchiveExportView(selection: PreviewFixture.snapshots(count: 12))
        .previewLibrary()
}
#endif
