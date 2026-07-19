# Touch Blocker 🛡️

A high-performance Android screen lock and touch blocker utility. Functioning similarly to iOS Guided Access or Assistive Touch, it displays a floating native overlay over specific target applications (e.g., TikTok, YouTube) and intercepts/blocks touch inputs to prevent accidental operations.

---

## 🏗️ Architecture: Hybrid Separation of Concerns

The project strictly follows a **Hybrid (Flutter + Kotlin Native)** architecture to guarantee zero background CPU loops, high battery efficiency, and clean memory management:

```
┌─────────────────────────────────┐
│     Control Panel (Flutter)     │ ◄── UI & Settings configuration
└────────────────┬────────────────┘
                 │ (MethodChannel IPC Bridge)
                 ▼
┌─────────────────────────────────┐
│    Background Engine (Kotlin)   │
├─────────────────────────────────┤
│ 1. AccessibilityService         │ ◄── Event-driven foreground app detector
│ 2. WindowManager Overlay        │ ◄── Seamless touch blocker bubble
└─────────────────────────────────┘
```

1. **Frontend / Control Panel (Flutter)**: Handles UI representation, configurations, target app selection, and permissions status monitoring.
2. **Background Engine (Kotlin Native)**: Listens to event-driven OS window changes, evaluates active applications, and draws/manages the native overlay.
3. **IPC Bridge (MethodChannel)**: The communications API between Flutter and Kotlin.

---

## 🛠️ Features & Technical Mechanics

### 1. Event-Driven App Detector (Kotlin)
*   Implemented via `AccessibilityService` listening to `TYPE_WINDOW_STATE_CHANGED` and `TYPE_WINDOW_CONTENT_CHANGED`.
*   Uses a **thread-safe, in-memory `HashSet` lookup** for $O(1)$ verification of foreground packages.
*   **Zero Polling**: Never uses CPU loops or Timers to check the foreground application.

### 2. Seamless Single-Bubble Overlay UI (`OverlayManager`)
*   **Zero Obstructive UI**: No dark filters, locked text screens, or massive unlock buttons.
*   **Bubble Visual States**:
    *   **IDLE State**: Bubble exhibits an open lock icon (`ic_lock_open`) and `0.6f` opacity.
    *   **LOCKED State**: Bubble switches to a closed lock (`ic_lock`), drops opacity to a highly unobtrusive `0.3f`, and stretches the window layout parameters to `MATCH_PARENT` to capture and discard all touches on the underlying screen.
*   **Poros Gravity Fix**: Uses `Gravity.TOP or Gravity.START` layout properties. This allows a 1:1 mapping of layout offsets directly with screen coordinates.
*   **Coordinate Offset Recovery**:
    *   When transitioning to `LOCKED` (window expands to `MATCH_PARENT`), the bubble is shifted programmatically via `view.x = lastIdleX` and `view.y = lastIdleY` to stay in place.
    *   When transitioning back to `IDLE` (window shrinks to `WRAP_CONTENT`), the bubble offsets are reset to `0f` inside the window, and layout params `x` and `y` are restored to `lastIdleX` and `lastIdleY`.
*   **Drag & Drop**: Bubble can be dragged and repositioned smoothly at 60fps in the `IDLE` state.
*   **Anti-Accidental Unlock (Double-Tap)**:
    *   Single tap in `IDLE` locks the screen.
    *   Unlocking from `LOCKED` requires a **Double Tap** (within 300ms) on the bubble to prevent accidental inputs if the user falls asleep.

### 3. Hydration & State Persistence
*   Target applications are saved in Android `SharedPreferences` as a `StringSet`. The accessibility engine hydrates this cache on service start (`onServiceConnected`), ensuring monitoring survives application kills.
*   The master service state (`KEY_SERVICE_ACTIVE`) is persisted and queried dynamically by Flutter on app launch and resume via `WidgetsBindingObserver` to keep the UI switch correctly synchronized.
*   **In-Memory Client Caching**: App list querying uses static caching inside `AppFetcherService` to avoid slow platform channel re-fetches during page transitions.

---

## 🔌 IPC Bridge Method Contract

All communication passes through `LockMethodChannel` using the following contract constants:

| Method Name | Payload | Returns | Description |
|---|---|---|---|
| `setTargetPackages` | `List<String>` | `void` | Updates Kotlin package HashSet and persists to SharedPreferences. |
| `getTargetPackages` | *None* | `List<String>` | Reads target packages from SharedPreferences to populate Dart UI checkbox state. |
| `startLockService` | *None* | `void` | Signals Kotlin to set the service state to active. |
| `stopLockService` | *None* | `void` | Signals Kotlin to set the service state to inactive. |
| `isLockServiceActive` | *None* | `bool` | Queries the persisted service active state. |
| `isOverlayGranted` | *None* | `bool` | Checks `Settings.canDrawOverlays`. |
| `isAccessibilityGranted`| *None* | `bool` | Scans enabled accessibility services to verify service binding status. |
| `requestOverlayPermission`| *None* | `void` | Directs user to the Overlay system settings page. |
| `requestAccessibilityPermission`| *None* | `void` | Directs user to the Accessibility system settings page. |

## 🌐 Localization (l10n) & Translation Support

The project is localized in both **Indonesian (`id`)** and **English (`en`)**. It utilizes Flutter's standard localization tool configured via l10n.yaml:

*   **Configured Output**: Generated Dart localizations are placed directly inside `lib/l10n/` (`synthetic-child: false`, `output-dir: lib/l10n`) rather than in `.dart_tool/` to keep project structure clean and visible.
*   **Formatters & Placeholders**: ARB bundles (`app_en.arb`, `app_id.arb`) support pluralization and integer formatting (e.g. `{count} dipilih` / `{count} selected`) to format numbers correctly per locale.

---

## 📁 Project Structure

```
lib/
├── core/
│   ├── channels/
│   │   └── lock_method_channel.dart      # Flutter IPC Wrapper
│   └── constants/
│       └── channel_constants.dart        # Method Channel Keys Spec
├── features/
│   ├── app_selector/
│   │   ├── models/
│   │   │   └── app_item.dart             # Lightweight application metadata DTO
│   │   ├── screens/
│   │   │   └── selector_screen.dart      # Selector panel UI with in-memory search
│   │   └── services/
│   │       └── app_fetcher_service.dart  # Caching OS application list fetcher
│   └── dashboard/
│       └── screens/
│           └── home_screen.dart          # Main dashboard & permissions status
└── l10n/
    ├── app_en.arb                        # English ARB translations source
    ├── app_id.arb                        # Indonesian ARB translations source
    └── app_localizations.dart            # Auto-generated localization classes
```

---

## 🚀 Getting Started & Build Instructions

### Prerequisites
*   Flutter SDK (3.x or higher)
*   Android SDK (API Level 23 or higher)
*   Physical Android Device (Accessibility Services and Overlays cannot be fully tested on standard Emulators)

### Permissions Required
The application uses two critical Android permissions configured in `AndroidManifest.xml`:
1.  **Display Over Other Apps (`SYSTEM_ALERT_WINDOW`)**: Needed to draw the overlay block window.
2.  **Accessibility Service (`BIND_ACCESSIBILITY_SERVICE`)**: Needed to monitor foreground app state changes event-driven.
3.  **Query All Packages (`QUERY_ALL_PACKAGES`)**: Needed to list user-installed apps.

### Setup and Running
1.  Clone the repository and run `pub get`:
    ```bash
    flutter pub get
    ```
2.  Generate the localization files manually or let the build trigger it:
    ```bash
    flutter gen-l10n
    ```
3.  Run static analysis to ensure a clean codebase:
    ```bash
    flutter analyze
    ```
4.  Run on your connected Android device:
    ```bash
    flutter run
    ```
5.  Give the required permission flags in the Home Dashboard screen to activate the lock engine overlay.

---

## App Preview

| Dashboard | Overlay Active |
| :---: | :---: |
| <img width="720" height="988" alt="Image" src="https://github.com/user-attachments/assets/739c0270-2639-42da-aeb7-c676c986a35f" /> | <img width="720" height="988" alt="Image" src="https://github.com/user-attachments/assets/c9707b50-1a2a-4838-b6e8-bc839ead1880" /> |

---

## 🔒 Privacy Policy & Security
This application uses AccessibilityService solely to detect the foreground application for the purpose of touch blocking. No data, keystrokes, or personal information is ever collected, logged, or transmitted. All processing happens locally on-device.

---

## ⚠️ Disclaimer
This project is provided for educational and utility purposes only. The author is not responsible for any misuse, device issues, or unintended consequences resulting from the use of this software. By using this app, you acknowledge that you are responsible for managing your own device permissions.
