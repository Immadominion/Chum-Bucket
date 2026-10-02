import 'package:chumbucket/core/services/app_lifecycle_service.dart';
import 'package:chumbucket/core/services/fcm_token_service.dart';
import 'package:chumbucket/core/services/realtime_service.dart';
import 'package:chumbucket/features/authentication/continuity/session_continuity.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/app_session_persistence.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out_controller.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/services/efficient_sync_service.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Platform effects are injectable so logout tests never contact a provider.
class AppSignOutEffects {
  AppSignOutEffects({
    Future<void> Function()? detachRealtime,
    Future<void> Function()? forgetNotifications,
    VoidCallback? clearSharedState,
  }) : detachRealtime = detachRealtime ?? RealtimeService.instance.unsubscribe,
       forgetNotifications =
           forgetNotifications ?? FcmTokenService.clearForSignOut,
       clearSharedState = clearSharedState ?? _clearSharedState;

  final Future<void> Function() detachRealtime;
  final Future<void> Function() forgetNotifications;
  final VoidCallback clearSharedState;

  static void _clearSharedState() {
    AppLifecycleService.onNavigateToChallenge = null;
    AppLifecycleService.instance.dispose();
    ChallengeStateProvider.instance.clear();
    EfficientSyncService.clearAllCaches();
  }
}

/// Used by BOTH Profile Settings and the call sign-in sheet. Capture references
/// before the controller disposes the account tree. Do not navigate using the
/// old screen's BuildContext after awaiting cleanup.
Future<void> signOutOfChumbucket(BuildContext context) {
  final account = context.read<AppSignOutController>();
  final google = context.read<ChumbucketSession>();
  final wallet = context.read<MwaAuthProvider>();
  final effects = context.read<AppSignOutEffects>();
  final persistence = AppSessionPersistence.current;
  // The Block Store copy of the session goes too: an explicit sign-out must
  // not come back signed in after a reinstall. (On-phone wallet keys stay —
  // deleting the only copy of a key can destroy its funds.)
  final continuity = context.read<SessionContinuity?>();
  return account.signOut([
    () async {
      effects.clearSharedState();
    },
    google.signOut,
    wallet.forgetSession,
    () async {
      await persistence?.clearForSignOut();
    },
    () async {
      await continuity?.clearSession();
    },
    effects.detachRealtime,
    effects.forgetNotifications,
    // The draft call and follows chosen before sign-in belonged to that
    // sign-in; topics and onboarding progress stay with the phone.
    const OnboardingStore().clearForSignOut,
  ]);
}
