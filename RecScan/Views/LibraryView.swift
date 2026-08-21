import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// The app's root screen: a filtered grid of every captured receipt.
///
/// Responsibilities:
/// - Host the grid, the scanner, the filter sheet and the export sheet.
/// - Own selection mode and its bulk actions.
struct LibraryView: View {

    @State private var model = LibraryViewModel()
    @Environment(\.receiptStore) private var receiptStore

    var body: some View {
        NavigationStack {
            ReceiptGridView(filter: model.filter, model: model)
                // Keyed on the filter so a predicate change rebuilds the query rather
                // than mutating a live one.
                .id(model.filter)
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .navigationDestination(for: Receipt.self) { receipt in
                    ReceiptDetailView(receipt: receipt)
                }
                .overlay { importProgress }
        }
        .fullScreenCover(isPresented: $model.isPresentingScanner) { scannerCover }
        .sheet(isPresented: $model.isPresentingFilter) {
            FilterView(filter: $model.filter)
        }
        .sheet(isPresented: $model.isPresentingExport) {
            ExportView(receipts: model.selectedReceipts)
        }
        .sheet(isPresented: $model.isPresentingArchiveExport) {
            ArchiveExportView(selection: model.selectedReceipts)
        }
        .sheet(item: $model.importResult) { result in
            ArchiveImportSummaryView(result: result)
        }
        .fileImporter(
            isPresented: $model.isPresentingArchiveImporter,
            allowedContentTypes: [.zip]
        ) { outcome in
            guard case .success(let url) = outcome else { return }
            Task { await model.importArchive(at: url, using: receiptStore) }
        }
        .onOpenURL { url in
            // AirDrop and "Open with" copy the file into Documents/Inbox and hand us
            // the copy, so it is ours to delete once merged.
            guard model.canHandle(url) else { return }
            Task { await model.importArchive(at: url, using: receiptStore, isInbox: true) }
        }
        .confirmationDialog(
            "library.delete.confirm.title",
            isPresented: $model.isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("library.delete.confirm.action", role: .destructive) {
                Task { await model.deleteSelectedReceipts(using: receiptStore) }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("library.delete.confirm.message \(model.selection.count)")
        }
        .errorAlert($model.presentedError)
    }

    // MARK: - Title

    private var navigationTitle: Text {
        model.isSelecting
            ? Text("library.selection.count \(model.selection.count)")
            : Text("library.title")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.isSelecting {
                Button("common.cancel") { model.endSelecting() }
            } else {
                Button("library.action.select") { model.beginSelecting() }
                    .disabled(model.visibleReceipts.isEmpty)
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.isSelecting {
                Button(model.isEverythingSelected ? "library.action.deselectAll" : "library.action.selectAll") {
                    model.toggleSelectAll()
                }
            } else {
                Button {
                    model.isPresentingFilter = true
                } label: {
                    Label(
                        "library.action.filter",
                        systemImage: model.filter.isActive ? SystemImage.filterActive : SystemImage.filter
                    )
                }

                Button {
                    model.isPresentingScanner = true
                } label: {
                    Label("library.action.scan", systemImage: SystemImage.scan)
                }
                .disabled(!VNDocumentCameraViewController.isSupported)

                Menu {
                    Button {
                        model.isPresentingArchiveExport = true
                    } label: {
                        Label("archive.action.export", systemImage: SystemImage.archiveExport)
                    }
                    Button {
                        model.isPresentingArchiveImporter = true
                    } label: {
                        Label("archive.action.import", systemImage: SystemImage.archiveImport)
                    }
                } label: {
                    Label("library.action.more", systemImage: SystemImage.more)
                }
            }
        }

        if model.isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    model.isPresentingExport = true
                } label: {
                    Label("library.action.export", systemImage: SystemImage.export)
                }
                .disabled(!model.hasSelection)

                Spacer()

                Button(role: .destructive) {
                    model.isConfirmingDeletion = true
                } label: {
                    Label("library.action.delete", systemImage: SystemImage.delete)
                }
                .disabled(!model.hasSelection)
            }
        }
    }

    // MARK: - Scanner

    private var scannerCover: some View {
        DocumentScanner(
            onScan: { pages in
                model.isPresentingScanner = false
                Task { await model.importScannedPages(pages, using: receiptStore) }
            },
            onFinish: { error in
                model.isPresentingScanner = false
                guard let error else { return }
                model.presentedError = PresentableError(titleKey: "error.scan.title", error: error)
            }
        )
        .ignoresSafeArea()
    }

    // MARK: - Progress

    @ViewBuilder
    private var importProgress: some View {
        if model.isImporting {
            // Blocks interaction while HEIC encoding runs, which is brief but must not
            // race a second scan session.
            ProgressView("library.import.progress")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LayoutMetrics.Detail.imageCornerRadius))
        }
    }
}

#Preview {
    LibraryView()
        .modelContainer(ModelContainerFactory.preview)
}
