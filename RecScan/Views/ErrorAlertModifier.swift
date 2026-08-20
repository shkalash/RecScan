import SwiftUI

/// Presents a `PresentableError` as a standard alert.
///
/// Responsibilities:
/// - Turn an optional error into alert presentation state.
///
/// Why a modifier: three screens surface errors the same way, and duplicating the
/// binding gymnastics in each of them is how they drift apart.
private struct ErrorAlertModifier: ViewModifier {

    @Binding var error: PresentableError?

    func body(content: Content) -> some View {
        content.alert(
            error.map { String(localized: $0.titleKey) } ?? String(localized: "error.generic.title"),
            isPresented: isPresented,
            presenting: error
        ) { _ in
            Button("common.ok", role: .cancel) {}
        } message: { presented in
            Text(presented.message)
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { error != nil },
            set: { presented in
                guard !presented else { return }
                error = nil
            }
        )
    }
}

extension View {
    func errorAlert(_ error: Binding<PresentableError?>) -> some View {
        modifier(ErrorAlertModifier(error: error))
    }
}
