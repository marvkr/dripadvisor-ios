# DripAdvisorShareExtension

iOS Share Extension target — accepts an image (screenshot), URL (Instagram /
e-commerce), or text from the system Share Sheet and enqueues a
`PendingWardrobeItem` to the App Group container. The main app drains the
queue on launch and POSTs to `/v1/wardrobe`.

## Files (already written, ready to wire)

- `ShareViewController.swift` — extension principal class, hosts the SwiftUI form
- `ShareFormView.swift` — compact form (name / brand / category / source toggle)
- `SharePayload.swift` — input/output models
- `SharedQueue.swift` — JSONL-backed queue inside `group.com.dripadvisor.shared`
- `Info.plist` — declares the extension as `com.apple.share-services` w/ image + URL + text activation rules
- `DripAdvisorShareExtension.entitlements` — App Group + Keychain access group

## Manual Xcode wiring (one-time)

Building this target through raw `project.pbxproj` edits is brittle. Add via
Xcode UI:

1. `open DripAdvisor.xcodeproj`
2. **File → New → Target… → Share Extension** (iOS)
3. Product Name: `DripAdvisorShareExtension`
4. Bundle Identifier: `com.dripadvisor.DripAdvisor.share`
5. Deployment target: iOS 18.0 (matches main app)
6. When Xcode generates the boilerplate, **replace** the auto-created
   `ShareViewController.swift` + `Info.plist` with the files in this directory.
7. Add the other Swift files (`ShareFormView.swift`, `SharePayload.swift`,
   `SharedQueue.swift`) to the new target only.
8. Set `Code Signing Entitlements` build setting →
   `DripAdvisorShareExtension/DripAdvisorShareExtension.entitlements`
9. Enable capability: **App Groups** → check `group.com.dripadvisor.shared` on
   both the main app target *and* the extension target.
10. Add the same App Group to the main app's `DripAdvisor.entitlements`
    (currently only declares `com.apple.developer.applesignin`).

## Main app drain hook

In `DripAdvisorApp.swift` (already imports the `SharedQueue` shape via the
shared `PendingWardrobeItem` Codable struct):

```swift
.task {
    let pending = SharedQueue.drain()
    for item in pending {
        // POST /v1/wardrobe via DripAPI + ingest locally
    }
}
```

Pending items contain base64 image + URL + category. POST to the existing
`/v1/wardrobe` endpoint. For URL-only items, optionally enrich first via
`/v1/wardrobe/scrape` before insert.
