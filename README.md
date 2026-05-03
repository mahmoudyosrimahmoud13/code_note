# CodeNote 🚀

**CodeNote** is a professional, developer-centric productivity suite that bridges the gap between note-taking and system-wide coding utilities. 

> [!IMPORTANT]
> **Source Code Notice**: The code in this repository represents the **Community Edition (Local-Only)**. It is a strictly offline, privacy-first version designed for open-source contribution. For the complete experience with Cloud Sync and Messaging, please use the download links below.

---

## 📥 Download (Full Version)

The **Full Version** includes all features listed below, including real-time messaging and cloud synchronization.

*   **[📱 Download for Android (.apk)](https://github.com/mahmoudyosrimahmoud13/code_note/releases/download/v1.1.0/app-release.apk)**
*   **[🪟 Download for Windows (.zip)](https://github.com/mahmoudyosrimahmoud13/code_note/releases/download/v1.1.0/Release_windows_x86.zip)**

---

## ✨ Full Feature Suite

### 🛠️ Android OS Power User Features
-   **"Open With" Support**: Open source files directly from your file manager into CodeNote.
    -   **Supported Extensions**: `.dart`, `.py`, `.js`, `.ts`, `.cpp`, `.cxx`, `.h`, `.hpp`, `.cs`, `.go`, `.java`, `.php`, `.ino`, `.sh`, `.kt`, `.sql`, `.json`, `.html`, `.css`, `.md`, `.txt`.
-   **Automated Note Parsing**: The app automatically reads shared files, detects the programming language, and creates a formatted code note instantly.
-   **System Share Target**: Share text, snippets, or files from any app (Chrome, WhatsApp, GitHub, File Manager) directly to CodeNote.

### 💬 Professional Messaging (Full Version Only)
-   **Real-time Collaboration**: Powered by Firestore with sub-millisecond sync for messages and reactions.
-   **Clickable Links**: All URLs in chat are automatically linkified and open in your external system browser.
-   **Group Management**: Full control over group members, admin permissions, and rich media sharing.

### 📝 Developer-First Editor
-   **Rich Block Architecture**: Mix Text, Markdown, and Code blocks in a single note.
-   **Syntax Highlighting**: Industry-standard highlighting for **20+ languages**:
    -   *Python, C#, Dart, Go, Java, JavaScript, TypeScript, C++, PHP, Arduino, ARM/x86 Assembly, Bash, Django, HTML, CSS, Docker, Kotlin, SQL, PostgreSQL, JSON.*
-   **OCR Integration**: Extract code or text from images using Google ML Kit.

### 🔐 Security & Persistence
-   **Offline-First Architecture**: Powered by **Hive**, ensuring your data is accessible even without an internet connection.
-   **Cloud Sync (Full Version Only)**: Automatic reconciliation between local storage and Firebase Cloud for multi-device access (Android, Windows, Web).
-   **QR Profile Sync**: Save and share high-resolution profile QR codes to connect with other developers instantly.
-   **Privacy Focused**: Disable Android Auto-Backup and manually clear all local/cloud data at any time.

---

## 🏗️ Technical Architecture (Community Edition)

The open-source codebase is built on **Clean Architecture** principles, optimized for a local-only environment.

-   **State Management**: BLoC (Business Logic Component).
-   **Dependency Injection**: GetIt (Service Locator).
-   **Local Database**: Hive (High-performance NoSQL).
-   **UI UX**: Flutter Animate, Custom Block Factory.

> [!TIP]
> For a deep-dive into the local-only architecture and build infrastructure, check out our **[Technical Overview](PROJECT_OVERVIEW.md)**.

---

## 🚀 Getting Started (Developers)

1.  **Clone**: `git clone https://github.com/mahmoudyosrimahmoud13/code_note.git`
2.  **Environment**: Ensure you have **Flutter 3.22+** and **JDK 17** installed.
3.  **Setup**: Run `flutter pub get` to install dependencies.
4.  **Build**: 
    ```powershell
    # Generate the release APK (Community Edition)
    flutter build apk --release
    ```

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
