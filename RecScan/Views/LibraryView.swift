import PhotosUI
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
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, phase in
            // Drained on becoming active rather than at launch: a share happens while the
            // app is already backgrounded, and waiting for a cold start would leave
            // receipts sitting in the inbox indefinitely.
            guard phase == .active else { return }
            Task { await model.drainSharedInbox(using: receiptStore) }
        }
        .task {
            #if DEBUG
            if let count = DebugSampleData.requestedCount {
                await DebugSampleData.seed(count: count, store: receiptStore)
            }
            #endif
        }
        .fullScreenCover(isPresented: $model.isPresentingScanner) { scannerCover }
        .sheet(isPresented: $model.isPresentingFilter) {
            FilterView(filter: $model.filter)
        }
        .sheet(isPresented: $model.isPresentingExport) {
            ExportView(receipts: model.selectedReceipts)
        }
        .sheet(isPresented: isReviewing) {
            ReceiptReviewSheet(receipts: model.pendingReview)
        }
        .sheet(isPresented: $model.isPresentingSettings) {
            SettingsView()
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
        .fileImporter(
            isPresented: $model.isPresentingFileImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true
        ) { outcome in
            guard case .success(let urls) = outcome else { return }
            Task { await model.importFiles(at: urls, using: receiptStore) }
        }
        .photosPicker(
            isPresented: $model.isPresentingPhotoPicker,
            selection: $model.photoSelection,
            maxSelectionCount: nil,
            matching: .images
        )
        .onChange(of: model.photoSelection) { _, selection in
            Task { await model.importPickedPhotos(selection, using: receiptStore) }
        }
        .onOpenURL { url in
            // Called once per file, so this queues rather than imports: five shared files
            // must become one review sheet, not five that overwrite each other.
            model.acceptHandoff(of: url, using: receiptStore)
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

    /// Driven by the queue rather than a separate flag, so the two cannot disagree about
    /// whether there is anything to review.
    private var isReviewing: Binding<Bool> {
        Binding(
            get: { !model.pendingReview.isEmpty },
            set: { presented in
                guard !presented else { return }
                model.pendingReview = []
            }
        )
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
                        model.isPresentingPhotoPicker = true
                    } label: {
                        Label("library.action.importPhotos", systemImage: SystemImage.photos)
                    }
                    Button {
                        model.isPresentingFileImporter = true
                    } label: {
                        Label("library.action.importFiles", systemImage: SystemImage.files)
                    }
                    Divider()
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
                    Divider()
                    Button {
                        model.isPresentingSettings = true
                    } label: {
                        Label("settings.title", systemImage: SystemImage.settings)
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

#if DEBUG
#Preview("Library") {
    LibraryView().previewLibrary()
}
#endif
