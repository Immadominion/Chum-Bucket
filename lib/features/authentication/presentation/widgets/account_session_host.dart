import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out_controller.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

/// Disposes the entire account-scoped provider/navigation tree during logout.
/// The next session gets fresh providers, never the preceding account's cache.
class AccountSessionHost extends StatelessWidget {
  const AccountSessionHost({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AppSignOutController(),
    child: Consumer<AppSignOutController>(
      builder: (context, account, _) {
        if (account.state == AppSignOutState.active) {
          return KeyedSubtree(
            key: ValueKey(account.generation),
            child: Builder(builder: builder),
          );
        }
        return ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, _) => MaterialApp(
                theme: AppTheme.lightTheme,
                debugShowCheckedModeBanner: false,
                home: Scaffold(
                  body: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (account.state == AppSignOutState.clearing) ...[
                              const CircularProgressIndicator(),
                              const SizedBox(height: 20),
                              const Text('Signing out…'),
                            ] else ...[
                              const Text('Couldn’t finish signing out.'),
                              const SizedBox(height: 12),
                              const Text(
                                'Your account screens are locked. Retry to finish clearing this device.',
                              ),
                              const SizedBox(height: 20),
                              ChallengeButton(
                                createNewChallenge: account.retry,
                                label: 'Retry sign-out',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        );
      },
    ),
  );
}
