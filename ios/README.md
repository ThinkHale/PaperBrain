# Illuminote iOS

Native SwiftUI iOS app for Illuminote — AI-powered handwritten notes.

## Requirements

- Xcode 16+ (verified with Xcode 26.5)
- iOS 17+ deployment target
- Swift 5.10+
- An active Supabase project (shared with the web app)

---

## Setup

### 1. Open the Xcode project

Open `ios/PaperBrain.xcodeproj` and select the shared `Illuminote` scheme.

The project already includes:

- All Swift source files under `ios/PaperBrain/`
- Supabase Swift SDK via Swift Package Manager
- Generated Info.plist settings
- Camera and photo library usage descriptions
- App icon assets under `Resources/Assets.xcassets`
- A shared scheme for Xcode Cloud

### 2. Configure signing

Before archiving or connecting Xcode Cloud, open the `Illuminote` target and update:

- **Team:** your Apple Developer team
- **Bundle Identifier:** currently `com.thinkhale.illuminote`

### 3. Info.plist permissions

The generated target Info settings include:

| Key | Value |
|-----|-------|
| `NSCameraUsageDescription` | `Illuminote uses the camera to photograph handwritten notes.` |
| `NSPhotoLibraryUsageDescription` | `Illuminote reads photos to import handwritten notes.` |

### 4. Verify Supabase credentials

Open `Config.swift` and confirm the URL and anon key match your Supabase project:

```swift
enum Config {
    static let supabaseURL = "https://YOUR_PROJECT.supabase.co"
    static let supabaseAnonKey = "YOUR_ANON_KEY"
}
```

### 5. Build & run

Select an iPhone simulator (or physical device) and press **⌘R**.

Command-line verification:

```sh
xcodebuild build \
  -project ios/PaperBrain.xcodeproj \
  -scheme Illuminote \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

### 6. Xcode Cloud

In App Store Connect, create a workflow using:

- **Project:** `ios/PaperBrain.xcodeproj`
- **Scheme:** `Illuminote`
- **Archive action:** Release

Make sure signing is configured for the bundle identifier before the first cloud archive.

---

## Feature Map

| Feature | Web app | iOS app |
|---------|---------|---------|
| Auth (email/password) | Supabase JS | `supabase-swift` Auth |
| Upload photos | `<input type=file>` / camera capture | `PhotosPicker` + `UIImagePickerController` |
| Import PDF | PDF.js | `PDFKit` (native) |
| AI transcription | `process-note` edge fn | Same edge function via `FunctionsClient` |
| Markdown display | marked.js | `WKWebView` + marked.js CDN |
| Annotations | Canvas 2D | `UIView`/`CGContext` draw layer |
| Relations | `find-relations` edge fn | Same edge function (fire-and-forget) |
| Mind map | D3.js force graph | SwiftUI `Canvas` + custom physics loop |
| Handwriting learning | `learn-handwriting` edge fn | Same edge function |
| Search | Client-side scored | Local string matching in `NotesViewModel` |
| Export | `.md` / `.json` download | `ShareLink` (markdown + JSON) |
| Profile / model select | localStorage + Supabase | Same Supabase `profiles` table |

All AI processing still happens **server-side** in the existing Supabase Edge Functions, so the OpenAI API key is never exposed to the device.

---

## Project structure

```
ios/PaperBrain/
├── Config.swift               — Supabase URL + anon key
├── IlluminoteApp.swift        — @main entry, injects environment objects
├── Models/
│   ├── Note.swift
│   ├── Annotation.swift
│   ├── Relation.swift
│   ├── Profile.swift
│   └── Misc.swift             — MindmapPosition, HandwritingCorrection
├── Resources/
│   └── Assets.xcassets
├── Services/
│   ├── SupabaseService.swift  — Supabase Swift SDK client + all DB CRUD
│   ├── StorageService.swift   — Image upload/download + resize/crop helpers
│   └── EdgeFunctionService.swift — process-note, find-relations, learn-handwriting
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── NotesViewModel.swift
│   ├── NoteDetailViewModel.swift
│   ├── UploadViewModel.swift
│   ├── MindMapViewModel.swift  — force simulation + graph data
│   └── ProfileViewModel.swift  — also contains ToastViewModel
└── Views/
    ├── ContentView.swift       — Root: auth gate + TabView
    ├── Auth/
    │   └── AuthView.swift
    ├── Notes/
    │   ├── NoteListView.swift  — searchable list + swipe-to-delete
    │   └── NoteDetailView.swift — tabs, images, annotations, relations
    ├── Upload/
    │   └── UploadView.swift    — photo picker, PDF import, progress overlay
    ├── Annotations/
    │   └── AnnotationCanvasView.swift — rect/ellipse/freehand over images
    ├── MindMap/
    │   └── MindMapView.swift   — Canvas force graph, pan/zoom, tag filter
    ├── Profile/
    │   └── ProfileView.swift
    └── Components/
        ├── TagChipView.swift
        ├── ToastView.swift
        ├── MarkdownView.swift  — WKWebView + marked.js
        └── ClarificationView.swift — [unclear] word correction UI
```

---

## Notes

- The Supabase database schema is unchanged — the iOS app shares the same tables and RLS policies as the web app.
- No third-party dependencies are needed beyond `supabase-swift`; PDF rendering uses `PDFKit` and Markdown rendering uses a bundled `WKWebView` with marked.js loaded from CDN (requires network).
- For offline Markdown rendering, replace the CDN `<script>` in `MarkdownView.swift` with a locally bundled `marked.min.js` added to the Xcode project.
