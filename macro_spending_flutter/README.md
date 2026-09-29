# Macro Spending — Flutter

Android and iOS rewrite of the SwiftUI app in the neighboring
`macroSpendingAnalyzer-main` directory. The Swift source is unchanged.

## Implemented

- Overview with recorded balance, current-month totals, and recent activity.
- Manual expenses and income with validated USD amounts and transaction dates.
- Camera/gallery receipts with on-device Latin-script text recognition.
  Merchant and total are suggestions; review them, select a category, and confirm
  the receipt date before saving. Dates are intentionally entered manually.
- Full history and year-to-date category spending bars (categories grouped
  case-insensitively; previously used categories are suggested while typing).
- Tap a transaction to edit it; swipe left to delete, with undo. Monthly-rule
  entries keep their due date when edited.
- Light and dark themes following the system setting.
- Monthly income/expense rules, month-end clamping, and stopping future entries.
- Local SQLite persistence (schema v2, with migrations), integer cents, empty
  initial database, error/retry UI.
- Android interrupted-image-picker recovery.

Monthly transactions are generated on launch, resume, refresh, and after saving.
They are not background notifications or bank transactions. The database enforces
one entry per rule and due date. Historical start dates create historical entries.
Future one-off entries appear as scheduled in History and do not count toward
today's balance or recent activity. Deletes are soft (`entries.deleted`) so a
deleted monthly entry is not posted again.
Balance is the net of entries in this app, not a connected bank balance.

## Run

Created with Flutter 3.47.5 / Dart 3.13.4. Install Flutter stable and the Android
SDK, or use the workspace-local SDK at `../.tooling/flutter` on this machine.

```powershell
..\.tooling\flutter\bin\flutter.bat pub get
..\.tooling\flutter\bin\flutter.bat analyze
..\.tooling\flutter\bin\flutter.bat test
..\.tooling\flutter\bin\flutter.bat run
```

Android requires an emulator or connected phone. Complete outstanding SDK license
prompts yourself using `flutter doctor --android-licenses`.

For iOS, use a Mac with Xcode and CocoaPods. Run `flutter pub get`, then
`cd ios && pod install`, and open `Runner.xcworkspace`. Choose your signing team
and an iPhone simulator/device. Minimum iOS target is 15.5; camera testing needs
a real device. Camera and photo-library purpose strings are configured.

## Validation and release work

`flutter analyze` and `flutter build apk --debug` pass. The Android APK is at
`build/app/outputs/flutter-apk/app-debug.apk`. Fifteen tests pass covering currency
parsing, month-end schedules, OCR totals, SQLite recurrence idempotency, stopping
rules, historical receipts, edit/delete/restore, the v1→v2 migration, overview
and statistics rendering, and invalid-form behavior. Native camera/OCR flows need device testing
on both platforms; iOS compilation requires macOS and has not been verified here.

This first implementation uses USD, starter icons, and a new local database.
It does not yet import the Swift app's SQLite data, sync devices, or provide
backups. Existing iOS users need an explicit data
migration before replacing the original app. Store identifiers, production
signing, branding, device/accessibility QA, and store submissions remain.
The generated Android release configuration currently uses a development key.

## Source map

- `lib/main.dart`: screens, navigation, and entry form.
- `lib/models.dart`: models, exact amount parsing, recurrence dates.
- `lib/store.dart`: SQLite schema, migrations (bump `SpendingStore.version` and
  add a step to `migrate`), and persistence.
- `lib/receipt_scanner.dart`: image capture, OCR, receipt-total suggestions.
- `test/`: domain, database, and form regression tests.

Plugin documentation: [sqflite](https://pub.dev/packages/sqflite),
[image_picker](https://pub.dev/packages/image_picker), and
[ML Kit text recognition](https://pub.dev/packages/google_mlkit_text_recognition).
