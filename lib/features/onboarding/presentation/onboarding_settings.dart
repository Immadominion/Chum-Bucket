/// Settings rows onboarding owns (onboarding spec §6 T, §8.6): the topics
/// chosen on this phone, and where notifications stand. Settings never asks
/// for permission on its own; refused-for-good opens Android's settings only
/// when the person taps.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/topics_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_menu_item.dart';

class TopicsSettingsItem extends StatelessWidget {
  const TopicsSettingsItem({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<OnboardingController?>();
    if (app == null) return const SizedBox.shrink();
    return ProfileMenuItem(
      key: const ValueKey('settings-topics'),
      basilIcon: 'lightbulb-outline',
      title: OnboardingCopy.settingsTopics,
      subtitle: OnboardingCopy.settingsTopicsValue(app.topics.length),
      iconColor: AppColors.primary,
      onTap: () {
        final navigator = Navigator.of(context);
        final host = navigator.context;
        navigator.pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (host.mounted) unawaited(showTopicsSheet(host));
        });
      },
    );
  }
}

class NotificationsSettingsItem extends StatefulWidget {
  const NotificationsSettingsItem({super.key});

  @override
  State<NotificationsSettingsItem> createState() =>
      _NotificationsSettingsItemState();
}

class _NotificationsSettingsItemState extends State<NotificationsSettingsItem>
    with WidgetsBindingObserver {
  PushSettingsState? _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_read());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Android Settings: read the permission again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) unawaited(_read());
  }

  Future<void> _read() async {
    final state = await PushRegistration.settingsState(context);
    if (mounted) setState(() => _state = state);
  }

  /// Only ever on a tap: off asks the OS once; refused for good opens
  /// Android's settings for Chumbucket.
  Future<void> _tap() async {
    switch (_state) {
      case PushSettingsState.blocked:
        await PushRegistration.openSystemSettings();
      case PushSettingsState.off:
        await PushRegistration.askNow(context);
      default:
        return;
    }
    if (mounted) await _read();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    // Nothing to turn on (no pushes from this server, nobody signed in, no
    // Firebase in this build): no row, rather than one that does nothing.
    if (state == null || state == PushSettingsState.unavailable) {
      return const SizedBox.shrink();
    }
    final subtitle = switch (state) {
      PushSettingsState.on => OnboardingCopy.settingsNotificationsOn,
      PushSettingsState.off => OnboardingCopy.settingsNotificationsTapToTurnOn,
      PushSettingsState.blocked => OnboardingCopy.settingsNotificationsOff,
      PushSettingsState.unavailable => '',
    };
    return ProfileMenuItem(
      key: const ValueKey('settings-notifications'),
      basilIcon: 'notification-outline',
      title: OnboardingCopy.settingsNotifications,
      subtitle: subtitle,
      iconColor: AppColors.primary,
      onTap: () => unawaited(_tap()),
    );
  }
}
