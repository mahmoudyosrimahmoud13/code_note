# CodeNote 🚀

**CodeNote** is a powerful, cross-platform note-taking application inspired by the simplicity of **Google Keep** and the structural flexibility of **Jupyter Notebooks**. It is designed specifically for developers, students, and thinkers who need to capture code snippets, ideas, and visual data all in one place.

## 🌟 The Vision

The core objective of CodeNote is to provide a seamless experience for managing technical notes. Whether you're on Windows, Web, or Mobile, CodeNote ensures your code is formatted correctly, your images are accessible, and your thoughts are organized.

---

## 📥 Download (Beta)

Get the latest pre-built binaries for your platform:

* **[🪟 Download for Windows (.zip)](https://github.com/mahmoudyosrimahmoud13/code_note/releases/download/beta/Release_windows_x86.zip)**
* **[📱 Download for Android (.apk)](https://github.com/mahmoudyosrimahmoud13/code_note/releases/download/beta/app-release.apk)**

> [!NOTE]
> Since this is a Beta release, you may need to "Allow from unknown sources" on Android or "Run anyway" on Windows (SmartScreen) as these binaries are not yet digitally signed.

---

## ✨ New Features

### 💬 Real-time Messaging & Collaboration
*   **Direct Chat**: Instant messaging with friends using Firebase real-time technology.
*   **Group Chats**: Create collaborative groups, manage members, and assign admins.
*   **Note Sharing**: Share any note directly into a chat with one tap.
*   **Rich Media**: Support for image messages with full-screen previews and cached loading.

### 🔄 Cloud Sync & Data Integrity
*   **Automatic Sync**: Your notes, groups, and settings are automatically synced across all your devices via Firebase Firestore.
*   **Offline First**: Comprehensive local caching using **Hive** ensure the app remains snappy and usable even without an internet connection.
*   **Smart Conflict Resolution**: Efficiently merges changes and ensures your data is always safe.

### 📝 Rich Block Editor
*   **Markdown Blocks**: Full support for Markdown rendering within your notes.
*   **Syntax Highlighting**: Optimized code blocks for various programming languages.
*   **Dynamic Layout**: Drag, reorder, and move blocks to structure your thoughts exactly how you want.

### 🔐 Secure Authentication
*   **Google Sign-In**: Instant access with your Google account.
*   **Email/Password**: Traditional secure registration and login.
*   **Profile Management**: Update your name, handle, and profile picture seamlessly.

---

## 📸 Screenshots

### 🏠 Home & Dashboard

The primary workspace featuring a masonry grid, **Pinned Notes**, and the new **Tag Cloud** for instant filtering.

<p align="center">
  <img src="screenshots/windows_home.png" width="450" alt="Windows Home"/>
  <img src="screenshots/android_home.jpg" width="220" alt="Android Home"/>
</p>

---

### 💬 Real-time Chat & Groups

Experience seamless communication and collaboration.

<p align="center">
  <img src="screenshots/android_chat_list.jpg" width="220" alt="Chat List"/>
  <img src="screenshots/android_chat_detail.jpg" width="220" alt="Chat Detail"/>
  <img src="screenshots/android_group_info.jpg" width="220" alt="Group Info"/>
</p>

---

### 🔍 Search & Live Suggestions

Advanced search logic with real-time suggestions matching titles and tags.

<p align="center">
  <img src="screenshots/windows_search.png" width="450" alt="Windows Search"/>
  <img src="screenshots/android_search.jpg" width="220" alt="Android Search"/>
</p>

---

### 📝 Note Details & Multi-Block Editing

A rich editor supporting **Text**, **Code**, **Image**, and **Markdown** blocks with syntax highlighting.

<p align="center">
  <img src="screenshots/windows_note_details.png" width="450" alt="Windows Note"/>
  <img src="screenshots/android_note_details.jpg" width="220" alt="Android Note"/>
</p>

---

### ⚙️ User Settings & Personalization

Customize your experience with **Theme Mode** (Dark/Light/System) and adjustable **Font Sizes**.

<p align="center">
  <img src="screenshots/windows_settings.png" width="450" alt="Windows Settings"/>
  <img src="screenshots/android_settings.jpg" width="220" alt="Android Settings"/>
</p>

---

## 🛠️ Built With

*   **Flutter** - UI Framework
*   **Firebase** - Cloud Firestore, Auth, Storage, and Real-time Messaging
*   **Bloc** - State Management
*   **Hive** - Fast, Lightweight Local Database
*   **GetIt** - Dependency Injection

---

## 🚀 Getting Started

1.  Clone the repository: `git clone https://github.com/mahmoudyosrimahmoud13/code_note.git`
2.  Install dependencies: `flutter pub get`
3.  Configure Firebase (Download `google-services.json` and `GoogleService-Info.plist`).
4.  Run the app: `flutter run`

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
