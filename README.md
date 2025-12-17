# Collaborative-Quiz-App

# Collaborative Quiz Rooms 📱🤝

A real-time multiplayer quiz application built with **Flutter** and **Firebase**. This app allows users to create private rooms, invite friends, and collaboratively generate quiz content on the fly.

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)

---

## 🚀 Features

* **Real-Time Lobby:** Create a room and share the 6-digit code with friends. Watch them join instantly!
* **Dynamic Content Creation:** The host creates questions and answers *inside the lobby* just before the game starts.
* **Live Sync:** Game state, current question, and scores are synchronized across all devices using Firebase Streams.
* **Anonymous Login:** No sign-up required. Just enter a nickname and play.
* **Cross-Platform:** Works on both Android and iOS.

## 📸 Screenshots

| Home Screen | Lobby (Host) | Gameplay | Scoreboard |
|:---:|:---:|:---:|:---:|
| <img src="screenshots/home.png" width="200"> | <img src="screenshots/lobby.png" width="200"> | <img src="screenshots/game.png" width="200"> | <img src="screenshots/score.png" width="200"> |

> *Note: Upload your screenshots to a `screenshots` folder in your repo to make them appear here.*

## 🛠️ Tech Stack

* **Frontend:** Flutter (Dart)
* **Backend:** Firebase Firestore (NoSQL Database)
* **Auth:** Firebase Anonymous Authentication
* **State Management:** `StreamBuilder` & `setState`

## ⚙️ Installation & Setup

1.  **Clone the Repo**
    ```bash
    git clone [https://github.com/your-username/collaborative-quiz-rooms.git](https://github.com/your-username/collaborative-quiz-rooms.git)
    cd collaborative-quiz-rooms
    ```

2.  **Install Dependencies**
    ```bash
    flutter pub get
    ```

3.  **Firebase Configuration**
    * Create a project on the [Firebase Console](https://console.firebase.google.com/).
    * Add an **Android** and **iOS** app to your Firebase project.
    * Download `google-services.json` (for Android) and put it in `android/app/`.
    * Download `GoogleService-Info.plist` (for iOS) and put it in `ios/Runner/`.
    * Enable **Firestore Database** and **Anonymous Authentication** in the Firebase Console.

4.  **Run the App**
    ```bash
    flutter run
    ```

## 📂 Project Structure
