import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/portfolio_provider.dart';
import '../providers/league_provider.dart';
import '../providers/ranked_provider.dart';
import 'portfolio/portfolio_screen.dart';
import 'compete/compete_screen.dart';
import 'league/league_screen.dart';
import 'search/search_screen.dart';
import 'global/global_chat_screen.dart';
import 'account/account_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    PortfolioScreen(),
    CompeteScreen(),
    LeagueScreen(),
    SearchScreen(),
    AccountScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PortfolioProvider>().loadPortfolio();
      context.read<LeagueProvider>().loadLeagues();
      context.read<RankedProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      floatingActionButton: SizedBox(
        width: 44,
        height: 44,
        child: FloatingActionButton(
          backgroundColor: AppTheme.green,
          shape: const CircleBorder(),
          elevation: 4,
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const GlobalChatScreen())),
          child: const Icon(Icons.chat_bubble_rounded,
              color: Colors.black, size: 20),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppTheme.bg,
          selectedItemColor: AppTheme.green,
          unselectedItemColor: AppTheme.textMuted,
          selectedFontSize: 10,
          unselectedFontSize: 10,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.work_rounded),           label: 'Portfolio'),
            BottomNavigationBarItem(icon: Icon(Icons.sports_esports_rounded),  label: 'Compete'),
            BottomNavigationBarItem(icon: Icon(Icons.sports_football_rounded), label: 'League'),
            BottomNavigationBarItem(icon: Icon(Icons.search_rounded),          label: 'Search'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded),          label: 'Account'),
          ],
        ),
      ),
    );
  }
}
