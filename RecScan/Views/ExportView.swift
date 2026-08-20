import SwiftUI

/// Export options and the share entry point.
///
/// Responsibilities:
/// - Collect layout and content choices.
/// - Trigger generation and hand the finished file to `ShareLink`.
///
/// `ShareLink` is given the file URL, never in-memory `Data`: the share sheet reads
/// the file lazily and the extension that receives it may outlive this view.
struct ExportView: View {

    let receipts: [ReceiptSnapshot]

    @State private var model = ExportViewModel()
    @Environment(\.imageFileStore) private var imageFileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("export.selection.count \(receipts.count)")
                        .foregroundStyle(.secondary)
                }

                Section("export.section.layout") {
                    Picker("export.section.layout", selection: $model.options.layout) {
                        ForEach(PDFPageLayout.allCases) { layout in
                            Text(String(localized: layout.titleKey)).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    Toggle("export.option.header", isOn: $model.options.includeHeader)
                    Toggle("export.option.summary", isOn: $model.options.includeSummaryPage)
                    Toggle("export.option.searchableText", isOn: $model.options.includeSearchableText)
                } header: {
                    Text("export.section.contents")
                } footer: {
                    Text("export.option.searchableText.footer")
                }

                Section { generateOrShare }
            }
            .navigationTitle("export.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .errorAlert($model.presentedError)
            // Deliberately no cleanup on disappear. A share extension may still be
            // reading the file after this sheet closes, and deleting it mid-transfer
            // produces a corrupt or empty result on the receiving end. The file lives
            // in `temporaryDirectory`, which the system reclaims on its own; it is
            // still replaced eagerly whenever the options change or the user
            // regenerates, so a session cannot accumulate more than one stale PDF.
        }
    }

    @ViewBuilder
    private var generateOrShare: some View {
        if let url = model.generatedURL {
            ShareLink(item: url) {
                Label("export.action.share", systemImage: SystemImage.export)
            }
            Button("export.action.regenerate") {
                Task { await model.generate(receipts: receipts, fileStore: imageFileStore) }
            }
        } else if model.isGenerating {
            HStack {
                ProgressView()
                Text("export.status.generating")
                    .foregroundStyle(.secondary)
            }
        } else {
            Button("export.action.generate") {
                Task { await model.generate(receipts: receipts, fileStore: imageFileStore) }
            }
            .disabled(receipts.isEmpty)
        }
    }
}
