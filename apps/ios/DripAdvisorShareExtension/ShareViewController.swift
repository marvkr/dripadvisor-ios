import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point for the iOS Share Extension. Accepts an image (e.g. iOS
/// screenshot) or a URL (Instagram / e-commerce link) from the Share Sheet,
/// hands off to the SwiftUI form, and stores the resulting item in the App
/// Group shared container. The main app drains the queue on next launch.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { await loadAndShow() }
    }

    @MainActor
    private func loadAndShow() async {
        let payload = await extractPayload()
        let host = UIHostingController(
            rootView: ShareFormView(
                payload: payload,
                onCancel: { [weak self] in self?.dismissExtension(complete: false) },
                onSave: { [weak self] item in
                    SharedQueue.enqueue(item)
                    self?.dismissExtension(complete: true)
                }
            )
        )
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func dismissExtension(complete: Bool) {
        if complete {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: NSError(
                domain: "DripAdvisorShareExtension", code: -1
            ))
        }
    }

    private func extractPayload() async -> SharePayload {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            return SharePayload()
        }

        var payload = SharePayload()
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let url: URL = try? await loadItem(provider, type: UTType.url.identifier) {
                    payload.url = url
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                if let image: UIImage = try? await loadImage(provider) {
                    payload.image = image
                    payload.imageData = image.jpegData(compressionQuality: 0.85)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text: String = try? await loadItem(provider, type: UTType.plainText.identifier) {
                    payload.text = text
                }
            }
        }
        return payload
    }

    private func loadItem<T: Sendable>(_ provider: NSItemProvider, type: String) async throws -> T? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { data, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: data as? T)
            }
        }
    }

    private func loadImage(_ provider: NSItemProvider) async throws -> UIImage? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { data, error in
                if let error { cont.resume(throwing: error); return }
                if let img = data as? UIImage { cont.resume(returning: img); return }
                if let url = data as? URL,
                   let raw = try? Data(contentsOf: url),
                   let img = UIImage(data: raw) {
                    cont.resume(returning: img); return
                }
                if let raw = data as? Data, let img = UIImage(data: raw) {
                    cont.resume(returning: img); return
                }
                cont.resume(returning: nil)
            }
        }
    }
}
