# Tip Out

A Flutter app for bartenders to calculate tip-outs for their team,
including barbacks, based on hours worked and tip percentages. Results
are Evention-ready — every line item is split into credit card tips and
service charge tips, and the lines always add back up to the shift total
to the penny.

## Features

- **Home**: start a shift, or import one a teammate shared with you
- **Tips**: enter credit card tips, service charge tips, and net sales
- **Team**: pick who worked, add and remove roster members, or flag a
  solo shift
- **Barback**: set the barback payout as a flat amount, a % of tips, or
  a % of sales
- **Hours**: split the pool equally or proportionally by hours worked
- **Results**: per-person breakdown, plus copy, share, and save to a
  running CSV tip log
- **Settings**: your name (used for your line item and the log) and an
  app-wide text size

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.0 or later
- Xcode (for iOS/macOS development)
- Android Studio (for Android development)

### Installation

```bash
# from the project root
flutter pub get
flutter run
```

Target a specific device with `flutter run -d ios`, `-d android`, or
`-d macos`.

### Tests

```bash
flutter test      # unit + widget tests
flutter analyze   # static analysis
```

## How It Works

1. **Enter Tips** — credit card and service charge tips are tracked as
   separate pools. Net sales is optional, but required if you want to
   pay the barback a percentage of sales.
2. **Add Team** — pick who worked. Roster names must be unique: the
   entire tip-out is keyed by name, so two people called Mike would
   collapse into one line item.
3. **Set the Barback Cut** — flat amount, % of tips, or % of sales.
4. **Enter Hours** — or choose an equal split.
5. **View Results** — each person's credit card and service charge
   amounts, which you can copy, share as a CSV, or append to your tip
   log.

The calculation itself is documented step by step in the class comment
on `TipCalculator`, including a worked example that the tests assert
against.

## Sharing and Importing

**Share** writes a one-shift CSV you can AirDrop or message to a
teammate. On their device, **Import Shift Data** on the home screen
previews it, warns if it's already in their log, and appends it.

The tip log (`tip_out_log.csv` in the app's documents directory) tags
every row as `Local` or `Imported`.

If you save a shift on a day you've already logged one, the app lists
the shifts you saved that day and asks whether to add this one alongside
them or redo a specific one. Replacement is scoped to the single shift
you pick — work a double, fix the evening numbers, and the afternoon is
untouched. Shifts teammates shared with you are never listed as yours to
redo and are never dropped.

## Project Structure

```
lib/
├── main.dart                    # App entry, theme, AppSettings inherited widget
├── models/
│   ├── money.dart               # Amount parsing, rounding, formatting
│   ├── pools.dart               # A line item: credit card + service charge
│   ├── person.dart              # Roster entry (immutable)
│   ├── shift_totals.dart        # Tips and sales entered for the shift
│   ├── shift_draft.dart         # The shift in progress, passed between screens
│   ├── tip_out_result.dart      # Calculated payouts
│   └── imported_shift.dart      # A shift parsed from a teammate's CSV
├── services/
│   ├── tip_calculator.dart      # The tip-out math (documented + unit tested)
│   ├── csv_export_service.dart  # Tip log read/write, share, import
│   └── settings_service.dart    # Preferences and roster persistence
├── widgets/
│   └── money_row.dart           # Shared label/amount row and warning card
└── screens/
    ├── home_screen.dart
    ├── tips_screen.dart
    ├── team_screen.dart
    ├── barback_screen.dart
    ├── hours_screen.dart
    ├── results_screen.dart
    ├── import_screen.dart
    └── settings_screen.dart
```
