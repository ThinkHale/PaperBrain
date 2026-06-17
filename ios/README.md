# PaperBrain iOS

Native SwiftUI iOS app for PaperBrain — AI-powered handwritten notes.

## Requirements

- Xcode 16+
- iOS 17+ deployment target
- Swift 5.10+
- An active Supabase project (shared with the web app)

---

## Setup

### 1. Create the Xcode project

1. Open Xcode → **File → New → Project**
2. Choose **iOS → App**
3. Set:
   - **Product Name:** `PaperBrain`
   - **Bundle Identifier:** `com.yourname.paperbrain`
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Minimum Deployment:** iOS 17.0
4. Save it **inside** the `ios/` folder of this repo

### 2. Add all Swift source files

Drag the entire `ios/PaperBrain/` folder into the Xcode project navigator (choose **"Add files to PaperBrain"**, tick **"Copy items if needed"** = OFF, **"Create groups"** = ON).

Make sure these groups are present in the project:
```
PaperBrain/
├── Config.swift
├── PaperBrainApp.swift
├── Models/
├── Services/
├── ViewModels/
└── Views/
    ├── Auth/
    ├── Notes/
    ├── Upload/
    ├── Annotations/
    ├── MindMap/
    ├── Profile/
    └── Components/
```

### 3. Add the Supabase Swift SDK

1. **File → Add Package Dependencies…**
2. Enter: `https://github.com/supabase/supabase-swift.git`
3. Version rule: **Up to Next Major → 2.0.0**
4. Add product: **Supabase** → target: **PaperBrain**

### 4. Configure Info.plist permissions

Open `Info.plist` (or the target's **Info** tab) and add these keys:

| Key | Value |
|-----|-------|
| `NSCameraUsageDescription` | `PaperBrain uses the camera to photograph handwritten notes.` |
| `NSPhotoLibraryUsageDescription` | `PaperBrain reads photos to import handwritten notes.` |

### 5. Verify Supabase credentials

Open `Config.swift` and confirm the URL and anon key match your Supabase project:

```swift
enum Config {
    static let supabaseURL = "https://YOUR_PROJECT.supabase.co"
    static let supabaseAnonKey = "YOUR_ANON_KEY"
}
```

### 6. Build & run

Select an iPhone simulator (or physical device) and press **⌘R**.

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
├── PaperBrainApp.swift        — @main entry, injects environment objects
├── Models/
│   ├── Note.swift
│   ├── NoteImage.swift
│   ├── Annotation.swift
│   ├── Relation.swift
│   ├── Profile.swift
│   └── Misc.swift             — MindmapPosition, HandwritingCorrection
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
