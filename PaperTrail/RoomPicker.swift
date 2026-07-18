import SwiftUI

/// A room selector that doubles as a custom-room entry: pick from known rooms
/// (defaults ∪ rooms already used), or add a new one inline. Whatever is chosen
/// is written back to `room`; once saved on a record it reappears as a future
/// suggestion automatically (see `RoomOptions`).
struct RoomPicker: View {
    @Binding var room: String

    /// Known rooms to offer, typically `RoomOptions.suggestions(existing:)`.
    let suggestions: [String]

    @State private var enteringCustom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                // Roomless is a first-class choice, not a cleared mistake —
                // plenty of items (phones, shoes, luggage) live nowhere.
                Button {
                    room = ""
                    enteringCustom = false
                } label: {
                    if room.isEmpty {
                        Label("No room", systemImage: "checkmark")
                    } else {
                        Text("No room")
                    }
                }
                Divider()
                ForEach(suggestions, id: \.self) { option in
                    Button {
                        room = option
                        enteringCustom = false
                    } label: {
                        if room.caseInsensitiveCompare(option) == .orderedSame {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
                Divider()
                Button {
                    enteringCustom = true
                    room = ""
                } label: {
                    Label("Add custom room…", systemImage: "plus")
                }
            } label: {
                HStack {
                    Text(room.isEmpty ? "No room" : room)
                        .foregroundStyle(room.isEmpty ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }

            if enteringCustom {
                TextField("New room name", text: $room)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
            }
        }
    }
}
