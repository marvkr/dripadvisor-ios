import SwiftUI

/// Paste-a-URL flow for the wishlist source. User pastes an Instagram /
/// e-commerce URL; backend scrapes OG tags + schema.org product JSON-LD and
/// returns a preview. User confirms category + save.
struct AddFromWebView: View {
    @Environment(DripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dripAPI) private var api

    @State private var url = ""
    @State private var preview: DripAPI.ScrapeResponse?
    @State private var imageData: Data?
    @State private var name = ""
    @State private var brand = ""
    @State private var category: GarmentCategory = .top
    @State private var isFetching = false
    @State private var error: String?

    private var canSave: Bool {
        !name.isEmpty && !brand.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        urlField
                        if let preview {
                            previewCard(preview)
                        }
                        if preview != nil {
                            form
                            Button(action: save) {
                                Text("Save to Wishlist")
                                    .primaryButton()
                            }
                            .disabled(!canSave)
                            .opacity(canSave ? 1 : 0.4)
                        }
                        if let error {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Theme.error)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("From the web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var urlField: some View {
        VStack(spacing: 10) {
            FocusableInput(placeholder: "Paste Instagram / shop link", text: $url)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button(action: fetch) {
                Label(isFetching ? "Fetching…" : "Fetch", systemImage: "wand.and.stars")
                    .primaryButton()
            }
            .disabled(url.isEmpty || isFetching)
            .opacity(url.isEmpty ? 0.4 : 1)
        }
    }

    private func previewCard(_ p: DripAPI.ScrapeResponse) -> some View {
        VStack(spacing: 12) {
            if let img = imageData.flatMap(UIImage.init(data:)) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(.rect(cornerRadius: 16))
            }
            if let price = p.retailPrice {
                Text(formatPrice(price, currency: p.currency))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(12)
        .glassCard()
    }

    private var form: some View {
        VStack(spacing: 12) {
            FocusableInput(placeholder: "Name — e.g. Oversized Hoodie", text: $name)
            FocusableInput(placeholder: "Brand — e.g. Lululemon", text: $brand)
            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(GarmentCategory.allCases) { cat in
                            categoryChip(cat)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(20)
        .glassCard()
    }

    private func categoryChip(_ cat: GarmentCategory) -> some View {
        Button { category = cat } label: {
            Label(cat.displayName, systemImage: cat.systemImage)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(category == cat ? .white : Theme.textSecondary)
                .background {
                    if category == cat { Capsule().fill(Theme.buttonPrimary) }
                }
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(category == cat ? .clear : Theme.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func fetch() {
        guard let api else {
            error = "Sign in to scrape URLs."
            return
        }
        guard let parsedURL = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Invalid URL"
            return
        }
        isFetching = true
        error = nil
        Task {
            defer { isFetching = false }
            do {
                let resp = try await api.scrapeWardrobe(url: parsedURL.absoluteString)
                preview = resp
                if let n = resp.name { name = n }
                if let b = resp.brand { brand = b }
                if let imgURL = resp.imageUrl.flatMap(URL.init(string:)) {
                    // Backend already ran rembg server-side and cached the
                    // transparent-PNG cutout in R2/MinIO — just fetch it. On-
                    // device Vision is unreliable on commercial ecom studio
                    // shots (Lulu, Uniqlo); see CLAUDE.md.
                    let (raw, _) = try await URLSession.shared.data(from: imgURL)
                    imageData = raw
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        let parsedURL = preview?.sourceUrl.flatMap(URL.init(string:))
        let item = WardrobeItem(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            imageData: imageData,
            source: .wishlist,
            sourceURL: parsedURL,
            retailPrice: preview?.retailPrice,
            currency: preview?.currency
        )
        store.addItem(item)
        dismiss()
    }
}

private func formatPrice(_ value: Double, currency: String?) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = currency ?? "USD"
    return f.string(from: value as NSNumber) ?? String(format: "%.2f", value)
}
