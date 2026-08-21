import SwiftData
import SwiftUI

/// Chooses a category, and creates one without leaving the form.
///
/// Responsibilities:
/// - Show the current category and let it be changed.
/// - Create a new category from a name typed in place.
///
/// ## Why this is not a `Menu`
/// SwiftUI's `Menu` cannot host a working `TextField` — its content is rendered by the
/// system menu, which does not accept text input. A popover carrying a real list is the
/// only way to type a new name in the same gesture that picks an existing one.
///
/// The field takes focus as the popover opens, so typing a new category needs no extra
/// tap. Focus is requested after a short hop rather than in `onAppear`: until the
/// presentation animation finishes the field is not yet in the window, and a focus
/// request that lands early is silently dropped.
struct CategoryPicker: View {

    @Binding var selection: UUID?

    @Query(sort: \ReceiptCategory.name) private var categories: [ReceiptCategory]
    @Environment(\.receiptStore) private var receiptStore

    @State private var isPresented = false
    @State private var newName = ""
    @State private var presentedError: PresentableError?
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            LabeledContent("detail.field.category") {
                Text(selectedName)
                    .foregroundStyle(selection == nil ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            content
                .frame(minWidth: LayoutMetrics.CategoryPicker.minimumWidth)
                .presentationCompactAdaptation(.popover)
        }
        .errorAlert($presentedError)
    }

    // MARK: - Popover

    private var content: some View {
        List {
            Section {
                HStack {
                    Image(systemName: SystemImage.addCategory)
                        .foregroundStyle(.secondary)
                    TextField("category.new.placeholder", text: $newName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isNameFieldFocused)
                        .onSubmit { Task { await create() } }
                }
            }

            Section {
                Button {
                    selection = nil
                    isPresented = false
                } label: {
                    row(title: Text("category.none"), isSelected: selection == nil, isMuted: true)
                }
                .buttonStyle(.plain)

                ForEach(categories) { category in
                    Button {
                        selection = category.id
                        isPresented = false
                    } label: {
                        row(title: Text(category.name), isSelected: selection == category.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .task {
            try? await Task.sleep(for: .milliseconds(AppConstants.Interaction.focusDelayMilliseconds))
            isNameFieldFocused = true
        }
    }

    private func row(title: Text, isSelected: Bool, isMuted: Bool = false) -> some View {
        LabeledContent {
            if isSelected {
                Image(systemName: SystemImage.checkmark).foregroundStyle(Color.accentColor)
            }
        } label: {
            title.foregroundStyle(isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }

    // MARK: - Derived

    private var selectedName: String {
        guard let selection, let match = categories.first(where: { $0.id == selection }) else {
            return String(localized: "category.none")
        }
        return match.name
    }

    // MARK: - Actions

    /// Creates the typed category and selects it.
    ///
    /// A name matching an existing category selects that one instead of adding a twin —
    /// the store decides, so the rule holds wherever categories are created.
    private func create() async {
        let name = newName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            selection = try await receiptStore.createCategory(named: name)
            newName = ""
            isNameFieldFocused = false
            isPresented = false
        } catch {
            presentedError = PresentableError(titleKey: "error.category.create.title", error: error)
        }
    }
}

#if DEBUG
#Preview("Category picker — populated") {
    @Previewable @State var selection: UUID? = PreviewFixture.primaryCategoryID
    return Form {
        CategoryPicker(selection: $selection)
    }
    .previewLibrary()
}

#Preview("Category picker — none selected") {
    @Previewable @State var selection: UUID?
    return Form {
        CategoryPicker(selection: $selection)
    }
    .previewLibrary()
}
#endif
