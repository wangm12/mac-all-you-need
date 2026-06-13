import Platform
import SwiftUI

struct TransformMenu: View {
    @Bindable var model: ClipboardDockModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(TextTransform.allCases, id: \.self) { transform in
                Button(label(for: transform)) {
                    Task {
                        await model.applyTransform(transform, saveAsNew: true)
                        isPresented = false
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func label(for transform: TextTransform) -> String {
        switch transform {
        case .lowercase: return "Lowercase"
        case .uppercase: return "Uppercase"
        case .titleCase: return "Title Case"
        case .trim: return "Trim"
        case .stripHTML: return "Strip HTML"
        case .prettyJSON: return "Pretty JSON"
        case .minifyJSON: return "Minify JSON"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .sortLines: return "Sort Lines"
        case .dedupeLines: return "Dedupe Lines"
        case .camelToSnake: return "camelCase → snake_case"
        case .snakeToCamel: return "snake_case → camelCase"
        case .timestampToDate: return "Timestamp → Date"
        case .escapeHTML: return "Escape HTML"
        case .unescapeHTML: return "Unescape HTML"
        case .md5Hash: return "MD5 Hash"
        case .reverseText: return "Reverse Text"
        }
    }
}
