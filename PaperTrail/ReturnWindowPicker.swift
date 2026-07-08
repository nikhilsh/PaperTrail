import SwiftUI

/// A return-window selector: pick a common duration, enter a custom day count,
/// or "None". Mirrors `RoomPicker`'s menu-plus-inline-entry pattern so it drops
/// into both the themed Draft form and the plain system-styled Edit form.
struct ReturnWindowPicker: View {
    @Binding var returnWindowDays: Int?

    static let presets = [7, 14, 30, 60, 90]

    @State private var enteringCustom = false
    @State private var customText = ""

    private var label: String {
        guard let days = returnWindowDays else { return "None" }
        return "\(days) day\(days == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                Button {
                    returnWindowDays = nil
                    enteringCustom = false
                } label: {
                    if returnWindowDays == nil { Label("None", systemImage: "checkmark") } else { Text("None") }
                }
                ForEach(Self.presets, id: \.self) { days in
                    Button {
                        returnWindowDays = days
                        enteringCustom = false
                    } label: {
                        if returnWindowDays == days { Label("\(days) days", systemImage: "checkmark") } else { Text("\(days) days") }
                    }
                }
                Divider()
                Button {
                    enteringCustom = true
                    customText = returnWindowDays.map(String.init) ?? ""
                } label: {
                    Label("Custom…", systemImage: "pencil")
                }
            } label: {
                HStack {
                    Text(enteringCustom ? "Custom" : label)
                        .foregroundStyle(returnWindowDays == nil && !enteringCustom ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }

            if enteringCustom {
                TextField("Number of days", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .submitLabel(.done)
                    .onChange(of: customText) { _, newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue { customText = digits }
                        returnWindowDays = Int(digits)
                    }
            }
        }
        .onAppear {
            if let days = returnWindowDays, !Self.presets.contains(days) {
                enteringCustom = true
                customText = String(days)
            }
        }
    }
}
