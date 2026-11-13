import SwiftUI
import UIKit

/// 穴埋めの答えを打つ欄。iOS の入力の補完をすべて切る
/// （答えが候補に出たり、打ち間違いが勝手に直ったりすると、綴りを思い出す練習にならないため）。
///
/// SwiftUI の `TextField` ではスペルチェックとインライン予測を切れないので、`UITextField` を包む。
/// 画面に出たらすぐ打てるようフォーカスし、画面から外れるとキーボードも閉じる
struct TypingAnswerField: UIViewRepresentable {
    @Binding var text: String
    /// キーボードの確定を押したとき
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        // 補完を切る: 自動修正・候補の帯・スペルチェック・インライン予測・先頭の大文字化・記号の置き換え
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.inlinePredictionType = .no
        field.autocapitalizationType = .none
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.textContentType = nil
        // 英字のキーボード（日本語キーボードの変換候補を出さない）
        field.keyboardType = .asciiCapable
        field.returnKeyType = .done
        field.enablesReturnKeyAutomatically = true
        field.font = .preferredFont(forTextStyle: .title3)
        field.adjustsFontForContentSizeCategory = true
        field.textAlignment = .center
        field.placeholder = "英語で入力"
        field.accessibilityLabel = "空欄に入る語"
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TypingAnswerField

        init(_ parent: TypingAnswerField) {
            self.parent = parent
        }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}
