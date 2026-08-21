import SwiftData
import SwiftUI

/// Manages the category list in settings.
///
/// Responsibilities:
/// - Add, rename and delete categories.
///
/// Deleting says plainly that the receipts survive: the destructive-looking action only
/// removes the label, and that is not obvious from a swipe-to-delete gesture.
struct CategoryListView: View {

    @Query(sort: \ReceiptCategory.name) private var categories: [ReceiptCategory]
    @Environment(\.receiptStore) private var receiptStore

    @State private var newName = ""
    @State private var renaming: ReceiptCategory?
    @State private var renamedName = ""
    @State private var presentedError: PresentableError?

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: SystemImage.addCategory).foregroundStyle(.secondary)
                    TextField("category.new.placeholder", text: $newName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { Task { await create() } }
                }
            }

            Section {
                if categories.isEmpty {
                    Text("category.empty")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categories) { category in
                        Button {
                            renaming = category
                            renamedName = category.name
                        } label: {
                            LabeledContent(category.name) {
                                Image(systemName: SystemImage.chevron)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        Task { await delete(offsets) }
                    }
                }
            } footer: {
                Text("category.list.footer")
            }
        }
        .navigationTitle("settings.section.categories")
        .navigationBarTitleDisplayMode(.inline)
        .alert("category.rename.title", isPresented: isRenaming) {
            TextField("category.new.placeholder", text: $renamedName)
            Button("common.cancel", role: .cancel) { renaming = nil }
            Button("common.save") { Task { await commitRename() } }
        }
        .errorAlert($presentedError)
    }

    // MARK: - State

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    // MARK: - Actions

    private func create() async {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            _ = try await receiptStore.createCategory(named: newName)
            newName = ""
        } catch {
            presentedError = PresentableError(titleKey: "error.category.create.title", error: error)
        }
    }

    private func commitRename() async {
        guard let renaming else { return }
        do {
            try await receiptStore.renameCategory(id: renaming.id, to: renamedName)
        } catch {
            presentedError = PresentableError(titleKey: "error.category.rename.title", error: error)
        }
        self.renaming = nil
    }

    private func delete(_ offsets: IndexSet) async {
        let ids = offsets.map { categories[$0].id }
        do {
            for id in ids { try await receiptStore.deleteCategory(id: id) }
        } catch {
            presentedError = PresentableError(titleKey: "error.category.delete.title", error: error)
        }
    }
}

#if DEBUG
#Preview("Categories") {
    NavigationStack {
        CategoryListView()
    }
    .previewLibrary()
}
#endif
