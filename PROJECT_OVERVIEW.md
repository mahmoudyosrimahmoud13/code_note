# CodeNote: Local-Only Open Source Architecture

## 🗺️ 1. Directory Architecture (Sanitized)

```text
lib/
├── injection_container.dart    # GetIt Registry: Orchestrates local-only registrations
├── main.dart                   # Global app entry; initializes Hive (Local Storage)
├── core/
│   ├── services/               # Core Singletons
│   │   ├── sharing_service.dart # Handles System Sharing (Files/Text)
│   │   └── log_service.dart    # Local system logging
│   └── util/                   # Pure functional utilities (Mappers, Helpers)
├── features/                   # Clean Architecture Modules
│   ├── notes/                  # Core Notes Engine
│   │   ├── data/               # NoteLocalDataSource (Hive only)
│   │   ├── domain/             # NoteEntity & NoteBlockEntity
│   │   └── presentation/       # BLoC (State) & UI
│   └── settings/               # Local Preferences & Profile (QR logic)
```

---

## 💉 2. Dependency Injection (GetIt)

The app uses `GetIt` as a Service Locator (`sl`) for a strictly local dependency graph:

- **Factories (`registerFactory`)**: Used for BLoCs (`NoteBloc`, `SettingsBloc`).
- **Lazy Singletons (`registerLazySingleton`)**: Used for Repositories and Local DataSources.
- **External Dependencies**: Only local instances of `HiveBox` are injected. All Firebase and remote services have been purged.

---

## 🛰️ 3. OS Integration (SharingService)

### SharingService (The Bridge)
- **Reactive Streams**: Uses `getMediaStream()` for real-time sharing of files/text from other apps.
- **Initial Intents**: Uses `getInitialMedia()` to catch "Share" events that launch the app from a cold state.
- **File Handling**: Configured as a system-wide handler for code files (`.dart`, `.py`, `.js`, etc.) on Android.

---

## 📂 4. Persistence Layer (Hive)

CodeNote operates as a **Strictly Offline** application:

- **Hive (Local Database)**:
    - `notesBox`: Stores all notes, blocks, and local metadata.
    - `settingsBox`: Stores user preferences (Theme, Font Size) and local profile data.

---

## ⛓️ 5. State Management Flow (BLoC)

### Example: Note Update Flow
1. **Event**: `UpdateNoteEvent` is dispatched from the UI.
2. **Local Commit**: `NoteBloc` instantly updates the UI state (Optimistic UI).
3. **Persistence**: `NoteRepository` saves the changes to `NoteLocalDataSource` (Hive).
4. **Reactive**: Local streams automatically emit the new list to all listeners.

---

## 🛠️ 6. Build Infrastructure (Android SDK 36)

The project uses a specialized Gradle Lifecycle Interceptor to ensure compatibility across all modules:

```gradle
// android/build.gradle
gradle.afterProject { project ->
    if (project.hasProperty('android')) {
        project.android {
            compileSdkVersion 36
            compileOptions {
                sourceCompatibility JavaVersion.VERSION_17
                targetCompatibility JavaVersion.VERSION_17
            }
            if (project.plugins.hasPlugin('kotlin-android')) {
                kotlinOptions { jvmTarget = '17' }
            }
        }
    }
}
```
**Rationale**: Forces the entire project tree (including third-party plugins) to align with **Java 17** and **Android SDK 36**.

---

## 📦 7. Optimized Dependency Stack

- **State**: `flutter_bloc` (v9.1+), `dartz` (Functional Error Handling).
- **Storage**: `hive`, `hive_flutter` (High-performance NoSQL).
- **Real-time Sharing**: `receive_sharing_intent`.
- **UI Components**: `flutter_animate`, `flutter_code_editor`, `flutter_markdown`, `qr_flutter`.
