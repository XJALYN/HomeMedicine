# Home Medicine (家药管家) — iOS App

Native SwiftUI app for family medicine cabinet management.

## Requirements

- macOS with Xcode 15+ (tested on Xcode 26.3)
- iOS 17.0+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (optional, for regenerating the project)
- [DashScope API Key](https://help.aliyun.com/zh/model-studio/) (optional, for AI medicine-box recognition)

## API Key Setup

Copy the example config and add your key (do **not** commit `BailianConfig.plist`):

```bash
cp HomeMedicine/Resources/BailianConfig.example.plist \
   HomeMedicine/Resources/BailianConfig.plist
# Edit DASHSCOPE_API_KEY in BailianConfig.plist
```

Alternatively set the `DASHSCOPE_API_KEY` environment variable in your Xcode Scheme.

## Project Location

```
ios/HomeMedicine/
├── HomeMedicine.xcodeproj
├── project.yml              # XcodeGen spec
├── HomeMedicine/            # App sources
│   ├── App/
│   ├── Models/
│   ├── Services/
│   ├── Views/
│   ├── Theme/
│   └── Resources/
│       ├── Assets.xcassets
│       └── Localizations/   # 26 × .lproj
├── HomeMedicineTests/
├── HomeMedicineUITests/
└── Scripts/
    └── generate_localizations.py
```

## Build & Run

### Open in Xcode

```bash
open ios/HomeMedicine/HomeMedicine.xcodeproj
```

Select an iPhone simulator and press **Run** (⌘R).

### Command Line

```bash
cd ios/HomeMedicine

# Regenerate project (after editing project.yml)
xcodegen generate

# Build
xcodebuild -scheme HomeMedicine \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Unit tests
xcodebuild test -scheme HomeMedicine \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:HomeMedicineTests

# UI tests
xcodebuild test -scheme HomeMedicine \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:HomeMedicineUITests
```

## Features

| Module | Description |
|--------|-------------|
| **药品** | Search, filter chips, status-colored cards, detail navigation |
| **添加** | Barcode scan (AVFoundation), OCR expiry assist, full PRD v1.1 form |
| **提醒** | Today's intake timeline, confirm intake, expiring warnings, add reminder |
| **我的** | Settings, language picker, members, expired cleanup, depleted archive |

## Architecture

- **UI**: SwiftUI, fixed light theme (`.preferredColorScheme(.light)`)
- **Persistence**: SwiftData (Medicine, UsageRecord, Reminder, Member, MedicineCabinet, MedicineBoxPhoto)
- **Cloud sync**: CloudKit via SwiftData; box photos use `@Attribute(.externalStorage)` (synced as CKAssets)
- **Business logic**: `MedicineStatusCalculator`, `MedicineFilterService`, `IntakeService`, `NotificationScheduler`
- **Notifications**: `UNUserNotificationCenter` local scheduling; reschedules on app launch, settings/medicine/reminder changes
- **i18n**: 26 fully translated `Localizable.strings` bundles; override in Profile → Language

## Localization

**Workflow when adding new UI strings:**

1. Add the key to `STRINGS` in `Scripts/generate_localizations.py` (English source of truth)
2. Add Simplified Chinese override in `ZH_HANS` (and Traditional in `ZH_HANT` if applicable)
3. Regenerate all locales with full translation (do **not** rely on sync-only for new keys):

```bash
cd ios/HomeMedicine
python3 Scripts/generate_localizations.py --full-translate
```

Sync-only (without `--full-translate`) only fills missing keys with English and must not be used after adding new features.

Audit coverage:

```bash
python3 Scripts/audit_localizations.py
python3 Scripts/audit_localizations.py --strict
```

English and Simplified Chinese are hand-maintained in `generate_localizations.py`; all other locales are batch-translated via DeepSeek (`~/.cursor/skills/deepseek-translate`).

## Barcode Lookup Database

The app ships a bundled `medicine_barcodes.json` with **verified** Chinese OTC EAN-13 barcodes sourced from public drug packaging listings (39.net / 315jiage.cn). Scanning fills name, specification, manufacturer, and approval number — **expiry must be entered manually or via OCR**.

Regenerate the database after editing `Scripts/build_medicine_barcodes.py`:

```bash
python3 ios/HomeMedicine/Scripts/build_medicine_barcodes.py
```

### Sample barcodes for testing

| Barcode | Product |
|---------|---------|
| `6901339913419` | 感冒灵颗粒 (999) |
| `6913991300322` | 布洛芬缓释胶囊 (芬必得) |
| `6936292120055` | 阿莫西林胶囊 (石药) |
| `6920855052105` | 连花清瘟胶囊 |
| `6932833600109` | 蒙脱石散 (思密达) |
| `6901234567892` | 阿莫西林胶囊 (simulator test code) |

If a barcode is not recognized, the Add Medicine form shows **「未识别，请手动填写」** and offers to submit the barcode for future database updates.

Public online APIs (e.g. nocode medical barcode API) require registration and were not integrated; lookup is offline-first via the bundled JSON.

## Signing

Set your **Development Team** in Xcode → HomeMedicine target → Signing & Capabilities before running on a physical device.

## CloudKit Setup

Container identifier: `iCloud.com.homemedicine.app`

### Apple Developer (one-time)

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → `com.homemedicine.app` → enable **iCloud** → **CloudKit** → add container `iCloud.com.homemedicine.app`
2. Xcode → HomeMedicine target → **Signing & Capabilities** → confirm **iCloud** + **CloudKit** + **Remote notifications**
3. Run on a device signed into iCloud (simulator iCloud is limited)

### CloudKit Dashboard schema checklist

Open [CloudKit Dashboard](https://icloud.developer.apple.com) → container `iCloud.com.homemedicine.app`.

| Step | Action |
|------|--------|
| 1 | Run the app once on a **Development** build so SwiftData creates the schema |
| 2 | **Schema → Record Types** — verify these types exist (SwiftData uses `CD_` prefix): |
| | `CD_MedicineCabinet`, `CD_Medicine`, `CD_MedicineBoxPhoto`, `CD_Member`, `CD_Reminder`, `CD_UsageRecord` |
| 3 | Confirm each type has `CD_id` (UUID/string) marked **Queryable** |
| 4 | `CD_MedicineBoxPhoto` must include `CD_imageData` as **Asset** (from `@Attribute(.externalStorage)`) |
| 5 | Check relationships: `CD_Medicine` ↔ `CD_MedicineBoxPhoto`, `CD_MedicineCabinet` ↔ `CD_Medicine` / `CD_Member` |
| 6 | **Deploy Schema Changes** → Development → Production **before App Store release** |
| 7 | Test private sync: same Apple ID on two devices, add a medicine, wait ~1 min |
| 8 | Test family share: **Profile → Family Sharing → Invite** (Family subscription), accept link on second Apple ID |
| 9 | Test photo sync: add box photos on device A, confirm they appear on device B after CloudKit sync |

### Common issues

| Symptom | Fix |
|---------|-----|
| Schema not appearing | Run on physical device with iCloud signed in; check entitlements |
| Share fails / record not synced | Wait for initial CloudKit export; keep app foreground briefly |
| Photos missing on other device | Confirm `CD_MedicineBoxPhoto.CD_imageData` is Asset type in Dashboard |
| Production upload rejected | Deploy schema Development → Production in Dashboard |
