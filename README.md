# CodeNote 🚀

**CodeNote** is a powerful, cross-platform note-taking application inspired by the simplicity of **Google Keep** and the structural flexibility of **Jupyter Notebooks**. It is designed specifically for developers, students, and thinkers who need to capture code snippets, ideas, and visual data all in one place.

## 🌟 The Vision
The core objective of CodeNote is to provide a seamless experience for managing technical notes. Whether you're on Windows, Web, or Mobile, CodeNote ensures your code is formatted correctly, your images are accessible, and your thoughts are organized.

---

## ✨ Implemented Features

### 🛠️ Architecture & Core
- **Clean Architecture**: Built following TDD principles with a strict separation of Domain, Data, and Presentation layers.
- **Local-First Persistence**: Fully offline-capable using `shared_preferences` for fast and reliable local storage across all platforms.
- **Auto-Save**: Every change you make—whether it's a title, a text block, or a code snippet—is saved instantly.

### 📝 Note Management (Keep-Inspired)
- **Pinning**: Keep your most important notes at the top of your dashboard.
- **Archiving**: Swipe to hide notes from your main view without deleting them.
- **Trash System**: A dedicated trash section for deleted notes with restore and permanent delete options.
- **Search**: (Coming soon) Quickly find any note by title or content.

### 💻 Developer Experience (Jupyter-Inspired)
- **Block-Based System**: Notes are composed of dynamic blocks:
  - **Text Blocks**: For rich descriptions and ideas.
  - **Code Blocks**: Multi-language support (Python, Dart, C++, etc.) with syntax-aware organization.
  - **Image Blocks**: Attach screenshots or diagrams directly to your notes.
- **OCR (Document Scan)**: Extract text or code directly from images using Google ML Kit.

### 📱 Responsive Design
- **Cross-Platform**: Optimized for **Windows**, **Web**, **Android**, and **iOS**.
- **Adaptive UI**: 
  - **NavigationRail** for Desktop and Web.
  - **BottomNavigationBar** for Mobile.
  - **Dynamic Grid**: Automatically scales from 2 to 6 columns based on screen width.

---

## 🚀 Roadmap (Upcoming Features)

- [ ] **Cloud Sync**: Synchronize your notes across all your devices.
- [ ] **AI Snippet Explainer**: Integrated AI to explain complex code blocks or suggest optimizations.
- [ ] **Messaging & Collaboration**: Chat with other developers and share notes in real-time.
- [ ] **Public Note Sharing**: Generate public links to share your technical notes with the community.
- [ ] **Advanced Formatting**: Markdown support within text blocks.

---

## 🛠️ Tech Stack
- **Framework**: [Flutter](https://flutter.dev)
- **State Management**: [Bloc](https://pub.dev/packages/flutter_bloc)
- **Dependency Injection**: [GetIt](https://pub.dev/packages/get_it)
- **Local Storage**: [Shared Preferences](https://pub.dev/packages/shared_preferences)
- **OCR**: [Google ML Kit](https://developers.google.com/ml-kit)

---

## 🏗️ Getting Started

1. **Clone the repository**
2. **Install dependencies**:
   ```bash
   flutter pub get
   ```
3. **Run the app**:
   ```bash
   flutter run
   ```

---
Made with ❤️ for the developer community.
