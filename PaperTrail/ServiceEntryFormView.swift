import SwiftUI

/// "+ LOG A REPAIR OR SERVICE" entry sheet (docs/design-v3/V3_BRIEF.md §4):
/// date, actor picker, title, optional cost/job ref. Presented from
/// `RecordDetailView`'s Service tab; appends a `ServiceEntry` to
/// `record.serviceEntries` on save.
struct ServiceEntryFormView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ServiceEntry) -> Void

    @State private var date: Date = .now
    @State private var actor: ServiceActorKind = .selfServiced
    @State private var title: String = ""
    @State private var costText: String = ""
    @State private var jobRef: String = ""

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Serviced by", selection: $actor) {
                        ForEach(ServiceActorKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                }
                Section {
                    TextField("What happened", text: $title, axis: .vertical)
                } header: {
                    Text("Title")
                }
                Section {
                    TextField("Cost (optional)", text: $costText)
                        .keyboardType(.decimalPad)
                        .ptKeyboardDoneToolbar()
                    TextField("Job reference (optional)", text: $jobRef)
                }
            }
            .navigationTitle("Log a repair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedJobRef = jobRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = ServiceEntry(
            date: date,
            actor: actor.rawValue,
            title: trimmedTitle,
            cost: parsedCost,
            jobRef: trimmedJobRef.isEmpty ? nil : trimmedJobRef
        )
        onSave(entry)
        dismiss()
    }

    /// Parses the free-text cost field via `Decimal(string:)` (locale-aware
    /// decimal separator). Empty or unparseable input just means "no cost
    /// recorded" — the field is optional, never blocks save.
    private var parsedCost: Decimal? {
        let trimmed = costText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: .current)
    }
}

#Preview {
    ServiceEntryFormView(onSave: { _ in })
}
