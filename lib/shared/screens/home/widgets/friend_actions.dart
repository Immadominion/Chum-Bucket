/// What tapping a friend does, now that friends are about calls.
///
/// A friend used to open a SOL escrow challenge. That flow is retired (the
/// escrow program is live on mainnet, so a stake would be real SOL judged by a
/// witness, not a venue); earlier ones stay in Settings → History. Tapping a
/// friend now opens their profile: their calls, where you can back them, fade
/// them or dare them to call it, and Follow.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

/// Opens [friend] (a Friends row: `name`, `walletAddress`, `userId`).
///
/// The profile is addressed by their canonical person id (`userId`), never by
/// their wallet. A friend without one, or a build without the calls layer,
/// gets the same call-based actions as a sheet instead: make a call and send
/// it to them. [onMakeCall] opens the market list.
void openFriend(
  BuildContext context,
  Map<String, String> friend, {
  required VoidCallback onMakeCall,
}) {
  final personId = friend['userId'] ?? '';
  if (personId.isNotEmpty && context.read<CallsProvider?>() != null) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallPersonScreen(personRef: personId),
      ),
    );
    return;
  }
  final name = friend['xLabel'] ?? friend['name'] ?? 'your friend';
  showChumbucketWavySheet<void>(
    context: context,
    builder:
        (sheetContext) => FriendCallActionsSheet(
          name: name,
          onMakeCall: () {
            Navigator.of(sheetContext).pop();
            onMakeCall();
          },
        ),
  );
}

/// The call-based actions for a friend whose profile cannot be opened.
class FriendCallActionsSheet extends StatelessWidget {
  const FriendCallActionsSheet({
    super.key,
    required this.name,
    required this.onMakeCall,
  });

  final String name;
  final VoidCallback onMakeCall;

  @override
  Widget build(BuildContext context) {
    return ChumbucketWavySheet(
      title: name,
      subtitle: 'Go on record together',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Make a call on a market and send $name the link. On their '
              'calls you can back them, fade them or dare them to call it. '
              'Calls are free and no money moves.',
              style: AppTextStyles.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 16),
            ChumbucketPrimaryButton(
              label: 'Make a call',
              onPressed: onMakeCall,
            ),
          ],
        ),
      ),
    );
  }
}
