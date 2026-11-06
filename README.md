# StudyDock

A calmer place for schoolwork. Native SwiftUI app for **iPhone, iPad, and Mac**.

## Download

Open [the latest release](https://github.com/EdwardWritesCodeIGuess/StudyDock/releases/latest), expand **Assets**, and download **StudyDock-macOS-AppleSilicon.zip**. Unzip it, then drag **StudyDock.app** into **Applications**. This build is for Apple silicon Macs (M1 or newer), macOS 14+.

This personal development build is ad hoc signed, not notarized by Apple. If macOS blocks opening the download, try opening it once, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. Only do this for the release from this repository. No terminal command or disabling Gatekeeper is needed.

For your iPhone, use the Xcode steps below. The Mac ZIP cannot install on an iPhone; there is no TestFlight or App Store release yet.

- **Homework → Apple Reminders.** Due dates and completion status stay up to date when edited in StudyDock.
- **Tests, quizzes, and projects → Apple Calendar.** Events include the assignment instructions and alerts one day and one hour beforehand.
- **Paste a pile.** Enter one assignment per line, optionally starting with `[Subject]`. Review detected dates and types before saving. Missing dates require confirmation.
- **Keep materials together.** Import or drag PDFs, images, text, and other files into an assignment; open them with Quick Look.
- **Know what to do before committing.** A short brief extracts instructions from notes and readable file text, labels its sources, and suggests a session plan.
- **Focus in your own time.** Choose 5–180 minutes, pause/resume, and get a local notification at the end. The timer persists through closing the app and device sleep.

## Run on Mac

Requires macOS 14 or later and Apple’s Swift command-line tools. No third-party dependencies or API keys.

```sh
./Scripts/build-mac.sh
open build/StudyDock.app
```

The script creates an ad hoc signed local app. A Developer ID and notarization are needed for normal distribution to other Macs. With full Xcode, you can instead open `StudyDock.xcodeproj`, choose the **StudyDock** scheme and **My Mac**, and Run.

If a beta command-line SDK is missing SwiftUI compiler plugins, choose a compatible installed SDK explicitly:

```sh
STUDYDOCK_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./Scripts/build-mac.sh
```

## Run on iPhone or iPad

1. Install full Xcode and open `StudyDock.xcodeproj`.
2. Select the **StudyDock** target → **Signing & Capabilities** → your Apple development team. Change the bundle identifier if your team requires it.
3. Choose an iPhone simulator, or connect your iPhone and enable Developer Mode.
4. Press Run. Minimum version: iOS/iPadOS 17.

The repository contains shared application source and a generated Xcode project. App Store/TestFlight distribution requires your Apple Developer account and signing configuration. No signing credentials are stored in this repository.

## First use

Add schoolwork with a title, subject, type, and due date/time. StudyDock requests Calendar or Reminders permission only when you first send an item to that app. It uses the default calendar/reminder list configured in Apple’s apps. You can override the destination for an individual item, or turn automatic export off in Settings.

For quizzes/tests, the selected date is the event start; the event lasts one hour. Project deadlines use a 15-minute event. Homework creates a reminder with the selected due time. Existing linked items are updated instead of creating another copy. An item stays saved locally if access is denied, with a retry action in its detail screen. Deleting an item asks whether to remove it and its linked Apple entry.

Select any item → **Start a focus session** to see the bullet brief before starting the timer. Completing a session records focused time; it does not automatically mark the assignment done. You can do that separately.

## Privacy and current limits

- All notes, copied attachments, OCR, and summary extraction stay on the device. There is no server, account, analytics, paid AI service, or network request for summaries.
- Briefs are **extractive**, not generative AI. They quote short relevant lines from your files and add a clearly labeled study plan. Always check original instructions.
- PDF text extraction uses up to 50 pages. Scanned PDFs use on-device OCR on up to 12 pages; image OCR is also supported. Extracted text is capped at 100,000 characters per attachment. Files must be 50 MB or smaller. Locked PDFs and unsupported formats remain attached with an explanation.
- **The StudyDock library is per device.** It does not yet sync tasks or attachments between iPhone and Mac. Calendar and Reminders entries can sync through their configured Apple accounts.
- Integration is **one way**: StudyDock → Calendar/Reminders. External edits and completions are not imported. Use StudyDock for changes you want to keep consistent.
- Local notifications need permission. A running timer is derived from its saved deadline, so it does not rely on background execution. Pausing cancels the pending notification.
- Data is an atomically written `library.json` plus an `Attachments` directory under the app’s Application Support directory. A corrupt or newer-version library is preserved and opened read-only, never replaced with an empty library.

## Development

```sh
swift test
swift build
# Only needed if you change project.yml:
brew install xcodegen
xcodegen generate
```

GitHub Actions tests the core module and builds both macOS and iOS Simulator targets. Full XCTest execution requires Xcode; the separate `Scripts/check-core.sh` runs core behavioral checks with command-line tools alone.

Layout:

- `Sources/StudyDockCore`: Codable models, date capture, brief extraction, deadline-based timers, atomic persistence.
- `Sources/StudyDockApp`: SwiftUI screens, EventKit integration, PDFKit/Vision import, local notifications.
- `Tests/StudyDockCoreTests`: routing, parsing, summaries, persistence, and timer regression tests.
- `Configuration`: usage descriptions, URL scheme, and sandbox entitlements.

Use `open build/StudyDock.app --args --demo` for a nonpersistent sample workspace. Demo mode never writes to Calendar or Reminders.

Apple references: [EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [creating events and reminders](https://developer.apple.com/documentation/eventkit/creating-events-and-reminders), [PDFKit](https://developer.apple.com/documentation/pdfkit), [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images).
