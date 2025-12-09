# My Voice - AAC Communicator

My Voice is an Android (and future iOS) application designed to assist non-verbal children with autism in communicating effectively. It utilizes evidence-based AAC (Augmentative and Alternative Communication) principles, specifically "Core Vocabulary" and "Motor Planning."

## 🌟 Features

* **Sentence Strip:** Allows users to build full sentences (e.g., "I want apple") before speaking.
* **Core Vocabulary:** 80% of the grid consists of high-frequency words (I, Go, Stop, Help) that remain in fixed positions to build motor memory.
* **Customization:** Parents can use the camera to create "Fringe Vocabulary" cards (specific toys, foods, people).
* **Offline Capability:** Works entirely without internet; data is stored locally.
* **Sensory Friendly:** Muted colors and simple UI to reduce cognitive load.

## 🛠 Tech Stack

* **Framework:** Flutter (Dart)
* **Text-to-Speech:** `flutter_tts`
* **Local Storage:** `shared_preferences` (JSON persistence) & `path_provider` (Image storage)
* **Camera:** `image_picker`

## 🚀 Getting Started

### Prerequisites

* Flutter SDK (3.0+)
* Android Studio / VS Code
* Android Device or Emulator

### Installation

1. Clone the repo:

    ```bash
    git clone [https://github.com/yourusername/my-voice-aac.git](https://github.com/yourusername/my-voice-aac.git)
    ```

2. Install dependencies:

    ```bash
    flutter pub get
    ```

3. Run on device:

    ```bash
    flutter run
    ```

## 🧪 Testing

The app uses `flutter_test` with mocked MethodChannels for native dependencies (TTS, File System).

Run the test suite:

```bash
flutter test
