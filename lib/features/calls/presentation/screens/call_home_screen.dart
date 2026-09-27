import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_feed_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_markets_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/shared/screens/splash/mwa_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The social product's entry point. Legacy wallet/escrow access remains
/// available explicitly, but cannot gate reading or Google sign-in.
class CallHomeScreen extends StatefulWidget {
  const CallHomeScreen({super.key});

  @override
  State<CallHomeScreen> createState() => _CallHomeScreenState();
}

class _CallHomeScreenState extends State<CallHomeScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          'chumbucket',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Your account',
            onPressed: () => setState(() => _selected = 2),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selected,
        children: [
          CallFeedScreen(
            showHeader: false,
            onBrowseMarkets: () => setState(() => _selected = 1),
          ),
          const CallMarketsScreen(),
          const _AccountScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: (index) => setState(() => _selected = index),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryContainer,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            label: 'Calls',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Markets'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'You'),
        ],
      ),
    );
  }
}

class _AccountScreen extends StatelessWidget {
  const _AccountScreen();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession>();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const CallSessionPanel(),
        if (session.isReady) ...[
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder:
                        (_) => CallPersonScreen(
                          personRef: session.userId!,
                          allowArenaProfileLink: false,
                        ),
                  ),
                ),
            child: const Text('My calls and receipts'),
          ),
        ],
        const SizedBox(height: 36),
        const Divider(),
        TextButton(
          onPressed:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MwaSplashScreen(),
                ),
              ),
          child: const Text('Legacy wallet and challenges'),
        ),
      ],
    );
  }
}
