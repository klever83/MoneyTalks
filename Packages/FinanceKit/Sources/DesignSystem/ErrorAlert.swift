import SwiftUI

public extension View {
    /// Алерт с текстом ошибки. Закрытие алерта обнуляет сообщение, чтобы следующая ошибка показалась снова.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Что-то пошло не так",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { text in
            Text(text)
        }
    }
}
