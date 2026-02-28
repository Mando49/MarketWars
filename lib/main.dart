import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/portfolio_provider.dart';
import 'providers/league_provider.dart';
import 'providers/ranked_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MarketWarsApp());
}

class MarketWarsApp extends StatelessWidget {
  const MarketWarsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PortfolioProvider()),
        ChangeNotifierProvider(create: (_) => LeagueProvider()),
        ChangeNotifierProvider(create: (_) => RankedProvider()),
      ],
      child: MaterialApp(
        title: 'MarketWars',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const AppRoot(),
      ),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF060810),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF00FF87))),
      );
    }
    return auth.isLoggedIn ? const MainShell() : const LoginScreen();
  }
}
