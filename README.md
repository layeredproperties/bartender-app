# Bartender Tip-Out App

A Flutter mobile app for bartenders to calculate tip-outs for their team, including barbacks, based on hours worked and tip percentages.

## Features

- **Home Screen**: Quick overview and navigation
- **Tips Screen**: Enter total tips for the shift
- **Team Screen**: Add and manage team members (bartenders, servers, etc.)
- **Barback Screen**: Configure barback tip-out percentage
- **Hours Screen**: Enter hours worked by each team member
- **Results Screen**: View calculated tip-out amounts for each person

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (version 3.0 or later)
- Xcode (for iOS development)
- Android Studio (for Android development)

### Installation

1. Install Flutter if you haven't already:
   ```bash
   brew install --cask flutter
   ```

2. Clone or copy this project to your machine

3. Navigate to the project directory:
   ```bash
   cd VSCode
   ```

4. Get dependencies:
   ```bash
   flutter pub get
   ```

5. Run the app:
   ```bash
   flutter run
   ```

### Running on iOS

```bash
cd VSCode
flutter run -d ios
```

### Running on Android

```bash
cd VSCode
flutter run -d android
```

## How It Works

1. **Enter Tips**: Input the total tips collected during the shift
2. **Add Team**: Add each team member who worked the shift
3. **Set Barback %**: Configure what percentage of tips goes to the barback
4. **Enter Hours**: Record how many hours each person worked
5. **View Results**: The app calculates each person's tip-out based on their share of hours worked

## Project Structure

```
lib/
├── main.dart              # App entry point
├── models/
│   ├── person.dart        # Person data model
│   └── shift_totals.dart  # Shift totals data model
├── services/
│   └── tip_calculator.dart # Tip calculation logic
└── screens/
    ├── home_screen.dart    # Home/navigation screen
    ├── tips_screen.dart    # Tips input screen
    ├── team_screen.dart    # Team management screen
    ├── barback_screen.dart # Barback configuration screen
    ├── hours_screen.dart   # Hours input screen
    └── results_screen.dart # Results display screen