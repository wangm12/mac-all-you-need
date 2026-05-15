import SwiftUI

struct NewListSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (String, String?) -> Void

    @State private var name: String = ""
    @State private var color: String? = "#FF8800"

    private let palette: [String] = [
        "#FF8800", "#34C759", "#007AFF", "#FF3B30",
        "#AF52DE", "#5AC8FA", "#FFCC00", "#8E8E93"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New List")
                .font(.headline)

            MAYNTextField(placeholder: "Name", text: $name, width: 280)

            HStack {
                ForEach(palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle()
                                .stroke(color == hex ? MAYNTheme.focusRing : .clear, lineWidth: 2)
                        }
                        .onTapGesture {
                            color = hex
                        }
                }
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }

                Spacer()

                Button("Create") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onCreate(trimmed, color)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

private extension Color {
    init?(hex: String) {
        let normalized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard normalized.count == 6, let value = UInt64(normalized, radix: 16) else { return nil }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
