import SwiftUI

/// Compact form rendered inside the Share Extension. Pre-fills from the
/// payload (URL / image / text), lets the user pick category + tag, then
/// queues a PendingWardrobeItem to the App Group container.
struct ShareFormView: View {
    let payload: SharePayload
    let onCancel: () -> Void
    let onSave: (PendingWardrobeItem) -> Void

    @State private var name: String = ""
    @State private var brand: String = ""
    @State private var category: String = "top"
    @State private var source: String

    init(
        payload: SharePayload,
        onCancel: @escaping () -> Void,
        onSave: @escaping (PendingWardrobeItem) -> Void
    ) {
        self.payload = payload
        self.onCancel = onCancel
        self.onSave = onSave
        // URL share → wishlist by default. Image → owned by default.
        _source = State(initialValue: payload.url != nil ? "wishlist" : "owned")
        _name = State(initialValue: payload.text ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !brand.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    previewBody
                    if let url = payload.url {
                        Text(url.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Section("Item") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Brand", text: $brand)
                        .textInputAutocapitalization(.words)
                    Picker("Category", selection: $category) {
                        Text("Top").tag("top")
                        Text("Bottom").tag("bottom")
                        Text("Dress").tag("dress")
                        Text("Shoes").tag("shoes")
                        Text("Outerwear").tag("outerwear")
                        Text("Accessory").tag("accessory")
                    }
                    Picker("Source", selection: $source) {
                        Text("Closet").tag("owned")
                        Text("Wishlist").tag("wishlist")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Save to DripAdvisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        if let img = payload.image {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .clipShape(.rect(cornerRadius: 12))
        } else if payload.url != nil {
            Label("Web link", systemImage: "link")
                .foregroundStyle(.secondary)
        } else {
            Text("Nothing to save")
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        let item = PendingWardrobeItem(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces),
            category: category,
            source: source,
            sourceURL: payload.url,
            imageData: payload.imageData
        )
        onSave(item)
    }
}
