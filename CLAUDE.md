# CLAUDE.md - MarketWars

## Project Overview

MarketWars is a fantasy stock trading competition app built with **Flutter/Dart**. Users participate in competitive stock trading leagues, ranked matchups, and portfolio management using real stock data from the Finnhub API.

**Platforms:** Android, iOS, Web
**Dart SDK:** >=3.0.0 <4.0.0
**State Management:** Provider (ChangeNotifier pattern)
**Backend:** Firebase (Auth, Firestore, Storage, Hosting)

## Common Commands

```bash
flutter pub get              # Install dependencies
flutter analyze              # Run static analysis / linting
flutter test                 # Run tests
flutter run                  # Run on connected device/emulator
flutter run -d chrome        # Run on web (Chrome)
flutter build apk            # Build Android APK
flutter build web            # Build web app
firebase deploy              # Deploy web to Firebase Hosting
```

## Project Structure

```
lib/
├── main.dart                       # App entry point, MultiProvider setup, root widget
├── firebase_options.dart           # Auto-generated Firebase config (do not edit manually)
├── theme/
│   └── app_theme.dart              # Dark theme, colors, typography, currency formatter
├── models/
│   └── models.dart                 # All data models (23 classes) in a single file
├── services/
│   ├── i_stock_service.dart        # Abstract stock API interface
│   ├── finnhub_stock_service.dart  # Finnhub API implementation
│   └── scoring_service.dart        # Weekly league scoring engine
├── providers/                      # Business logic & state (ChangeNotifier)
│   ├── auth_provider.dart          # Firebase Auth, user profiles
│   ├── portfolio_provider.dart     # Holdings, shorts, trades, prices
│   ├── league_provider.dart        # Leagues, members, matchups, draft, chat
│   └── ranked_provider.dart        # Ranked mode, leaderboard, matchmaking
└── screens/                        # UI layer
    ├── main_shell.dart             # Bottom nav controller (IndexedStack)
    ├── auth/login_screen.dart
    ├── portfolio/portfolio_screen.dart
    ├── league/
    │   ├── league_home_screen.dart
    │   ├── league_screen.dart      # Main league view (MATCH/TEAM/PLAYERS/LEAGUE tabs)
    │   ├── draft_room_screen.dart
    │   ├── create_league_screen.dart
    │   └── invite_players_screen.dart
    ├── search/
    │   ├── search_screen.dart
    │   └── stock_detail_screen.dart
    ├── compete/compete_screen.dart
    ├── global/global_chat_screen.dart
    └── account/account_screen.dart
```

## Architecture

### State Management

Provider with `ChangeNotifier`. Providers are initialized in `MultiProvider` in `main.dart`. Screens use `Consumer` or `context.read`/`context.watch` for reactive rebuilds. Providers encapsulate all business logic; screens handle UI only.

### Data Layer

- **Firestore** is the primary database (no local caching layer)
- Batch writes used for atomicity on multi-document updates
- Real-time streams for chat, matchups, and leaderboards

### Firestore Collections

```
users/{uid}/
  holdings/{symbol}
  shorts/{symbol}
  trades/{tradeId}
leagues/{leagueId}/
  members/{uid}
  matchups/{matchupId}
  chat/{messageId}
  draft/state/picks/{pickId}
  weeks/{weekNumber}/results/{uid}
leagueCodes/{code}          # Maps invite codes to leagueId
rankedProfiles/{uid}
seasons/{seasonId}
matchmaking/{uid}
```

### Services

- `IStockService` - abstract interface for stock data APIs
- `FinnhubStockService` - concrete implementation using Finnhub REST API with 120ms rate limiting
- `ScoringService` - weekly scoring engine that ranks players by portfolio % change

### Navigation

- Bottom nav bar with `IndexedStack` (preserves screen state)
- `Navigator.push()` for screen transitions (no named routes)

## Code Conventions

### Naming

- **Files:** `snake_case.dart`
- **Classes:** `PascalCase`
- **Private members:** `_prefixed`
- **Constants:** `kConstantName` or camelCase

### Style

- Null-safe Dart (non-nullable by default)
- `const` constructors used throughout
- Section comments use `// ── SECTION ──` pattern
- Imports ordered: dart SDK, packages, relative
- `StatefulWidget` + `State` pattern for stateful screens

### Linting

Uses `package:flutter_lints/flutter.yaml` (recommended Flutter lint rules). Run `flutter analyze` to check. Suppress specific rules with `// ignore: rule_name` when necessary.

## Theme & Styling

- **Material Design 3** (`useMaterial3: true`)
- **Font:** Space Grotesk (Google Fonts)
- **Dark theme** with layered surfaces:
  - Background: `#060810`
  - Surfaces: `#0E1219`, `#141A24`, `#1C2534`
  - Primary (green): `#00FF87`
  - Error/red: `#FF4560`
  - Gold: `#FFD700`
- Currency formatting: `AppTheme.currency(value, decimals)`

## Key Data Models

All models live in `lib/models/models.dart`. Key classes:

- `UserProfile` - user with cash balance, total value (starting balance: $10,000)
- `PortfolioHolding` / `ShortPosition` - long and short positions with P&L
- `Trade` - trade history (buy, sell, short, coverShort)
- `StockQuote` / `StockResult` - Finnhub API response models
- `League` / `LeagueMember` / `Matchup` - league competition
- `DraftPick` - stock draft picks within leagues
- `ChatMessage` - league and global chat with reactions
- `RankedProfile` / `RankTier` / `Season` - ranked competitive system

## Firebase Setup

- **Auth:** Email/password
- **Firestore:** Primary data store
- **Storage:** Profile photo uploads
- **Hosting:** Web deployment (`build/web/` directory, SPA rewrite)

Firebase config is in `firebase_options.dart` (auto-generated by FlutterFire CLI).

## Testing

Tests are in `test/`. Currently minimal coverage (smoke test only). Run with `flutter test`. The app relies heavily on Firebase, so integration tests with mock services are recommended.

## Deployment

- **Web:** `flutter build web && firebase deploy`
- **Android:** `flutter build apk` (currently uses debug signing - no production keystore configured)
- **Firebase Hosting:** configured in `firebase.json`, serves `build/web/` with SPA rewrite

## Things to Know

- All models are in a single file (`models.dart`) rather than split per-model
- API keys are currently hardcoded (Finnhub key in `finnhub_stock_service.dart`, Firebase config in `firebase_options.dart`)
- No CI/CD pipeline is configured
- No `.env` or environment variable system is in place
- The `firebase_options.dart` file is auto-generated - do not edit manually
- Android build uses Java/Kotlin 17
- Trending stocks list is hardcoded (12 symbols in `portfolio_provider.dart`)
