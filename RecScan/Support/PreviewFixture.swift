#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import UIKit

/// Ready-made data for SwiftUI previews.
///
/// Responsibilities:
/// - Provide an in-memory library, an isolated image directory, and receipts whose
///   images genuinely exist on disk.
///
/// ## Why previews need real files
/// `ReceiptThumbnailView` and `ReceiptDetailView` load their images through
/// `ImageFileStoring`. A preview backed by rows alone renders placeholder squares, which
/// is precisely the state you cannot judge a layout from. So the fixture writes real
/// HEIC files into a temporary directory.
///
/// ## Why everything here is synchronous
/// `#Preview` bodies are not async, and a view like `ReceiptDetailView(receipt:)` needs
/// its model *before* it can be constructed. Seeding through `ReceiptStore` would be
/// async, so the fixture builds receipts directly instead: `Receipt` initialises without
/// a context, and `ImageFileStore.write` is synchronous.
@MainActor
enum PreviewFixture {

    // MARK: - Storage

    private struct Directory: DocumentsDirectoryProviding {
        let documentsDirectory: URL
    }

    /// Isolated from the real container so previews can never touch a real library.
    static let imageFileStore: ImageFileStore = {
        let root = FileManager.default.temporaryDirectory.appending(path: "RecScanPreviews")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ImageFileStore(
            directoryProvider: Directory(documentsDirectory: root),
            thumbnailCache: ThumbnailCache()
        )
    }()

    // MARK: - Categories

    /// Names the previews are seeded with.
    static let categoryNames = ["Groceries", "Fuel", "Office", "Meals"]

    /// Stable ids so a receipt's `categoryID` resolves against the seeded container.
    static let categoryIDs: [UUID] = categoryNames.map { _ in UUID() }

    /// The category assigned to `PreviewFixture.receipt`, so the detail preview shows a
    /// populated row rather than "None".
    static var primaryCategoryID: UUID { categoryIDs[0] }

    private static func makeCategories() -> [ReceiptCategory] {
        zip(categoryIDs, categoryNames).map { ReceiptCategory(id: $0, name: $1) }
    }

    // MARK: - Library

    /// An in-memory container already holding `receiptCount` receipts.
    static let container: ModelContainer = {
        guard let container = try? ModelContainerFactory.makeInMemoryContainer() else {
            fatalError("Preview container could not be created")
        }
        let context = ModelContext(container)
        // Categories first: a receipt's categoryID has to resolve against rows that are
        // already there, or every category row in a preview reads "None".
        for category in makeCategories() { context.insert(category) }
        for receipt in makeReceipts() { context.insert(receipt) }
        try? context.save()
        return container
    }()

    static let receiptStore: any ReceiptStoring =
        ReceiptStore(modelContainer: container, fileStore: imageFileStore)

    /// A library with a long category list, for judging the picker at its height cap.
    static let crowdedContainer: ModelContainer = {
        guard let container = try? ModelContainerFactory.makeInMemoryContainer() else {
            fatalError("Preview container could not be created")
        }
        let context = ModelContext(container)
        for name in crowdedCategoryNames { context.insert(ReceiptCategory(name: name)) }
        try? context.save()
        return container
    }()

    static let crowdedStore: any ReceiptStoring =
        ReceiptStore(modelContainer: crowdedContainer, fileStore: imageFileStore)

    private static let crowdedCategoryNames = [
        "Groceries", "Fuel", "Office", "Meals", "Travel", "Hardware",
        "Software", "Utilities", "Rent", "Medical", "Books", "Gifts",
        "Parking", "Shipping"
    ]

    private static let receiptCount = 7

    // MARK: - Models

    /// One receipt with its image written to disk.
    ///
    /// - Parameter index: selects the merchant and keeps the imagery deterministic.
    static func makeReceipt(
        index: Int = 0,
        daysAgo: Int = 0,
        amount: Decimal? = Decimal(string: "42.50"),
        note: String? = nil,
        pageIndex: Int = 0,
        groupID: UUID? = nil,
        categoryID: UUID? = nil,
        needsReview: Bool = false
    ) -> Receipt {
        let id = UUID()
        let relativePath = (try? imageFileStore.write(SampleReceiptImage.make(index: index), for: id))
            ?? imageFileStore.relativePath(for: id)
        let capturedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let merchant = SampleReceiptImage.merchant(at: index)

        return Receipt(
            id: id,
            capturedAt: capturedAt,
            relativePath: relativePath,
            merchant: merchant,
            amount: amount,
            currencyCode: "ILS",
            note: note,
            groupID: groupID,
            pageIndex: pageIndex,
            categoryID: categoryID,
            needsReview: needsReview,
            searchIndex: ReceiptSearchIndex.make(merchant: merchant, note: note, ocrText: nil)
        )
    }

    /// A spread of receipts across several months, so month sectioning is visible.
    static func makeReceipts(count: Int = receiptCount) -> [Receipt] {
        // Spread across categories, with one deliberately uncategorised so previews show
        // both states side by side.
        (0..<count).map { index in
            makeReceipt(
                index: index,
                daysAgo: index * 9,
                categoryID: index == 2 ? nil : categoryIDs[index % categoryIDs.count],
                // A couple flagged, so the badge and the filter both have something to show.
                needsReview: index % 3 == 1
            )
        }
    }

    /// A single receipt, for the detail and thumbnail previews.
    static let receipt: Receipt = makeReceipt(index: 0, categoryID: primaryCategoryID)

    static func snapshots(count: Int = 4) -> [ReceiptSnapshot] {
        makeReceipts(count: count).map(ReceiptSnapshot.init)
    }

    // MARK: - View models

    static func libraryModel(selecting: Bool = false) -> LibraryViewModel {
        let model = LibraryViewModel()
        model.visibleReceipts = snapshots(count: receiptCount)
        if selecting {
            model.beginSelecting()
            model.selection = Set(model.visibleReceipts.prefix(2).map(\.id))
        }
        return model
    }
}

/// Applies the preview stores and container in one place.
///
/// Every data-backed preview needs the same three things wired up; forgetting one shows
/// an empty view rather than an error, which is the slowest kind of mistake to notice.
extension View {
    func previewLibrary(
        container: ModelContainer = PreviewFixture.container,
        store: (any ReceiptStoring)? = nil
    ) -> some View {
        environment(\.receiptStore, store ?? PreviewFixture.receiptStore)
            .environment(\.imageFileStore, PreviewFixture.imageFileStore)
            .modelContainer(container)
    }
}
#endif
