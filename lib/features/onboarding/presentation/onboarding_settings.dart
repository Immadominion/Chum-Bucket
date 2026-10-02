/// Settings rows onboarding owns (onboarding spec §6 T, §8.6): the topics
/// chosen on this phone, and where notifications stand. Settings never asks
/// for permission on its own; refused-for-good opens Android's settings only
/// when the person taps.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/services/notification_permission_coordinator.dart';
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
  const NotificationsSettingsItem({super.key, this.coordinator});

  final NotificationPermissionCoordinator? coordinator;

  @override
  State<NotificationsSettingsItem> createState() =>
      _NotificationsSettingsItemState();
}

class _NotificationsSettingsItemState extends State<NotificationsSettingsItem> {
  late final NotificationPermissionCoordinator _coordinator =
      widget.coordinator ?? NotificationPermissionCoordinator();
  NotificationSettingsState? _state;
  bool _live = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final live = await _coordinator.isPushLive();
    final state = await _coordinator.settingsState();
    if (!mounted) return;
    setState(() {
      _live = live;
      _state = state;
    });
  }

  Future<void> _tap() async {
    switch (_state) {
      case NotificationSettingsState.blocked:
        await _coordinator.openSystemSettings();
      case NotificationSettingsState.off when _live:
        await _coordinator.requestFromPrePrompt();
      default:
        break;
    }
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) return const SizedBox.shrink();
    final subtitle = switch (state) {
      NotificationSettingsState.on => OnboardingCopy.settingsNotificationsOn,
      NotificationSettingsState.blocked =>
        OnboardingCopy.settingsNotificationsOff,
      NotificationSettingsState.off =>
        _live ? 'Off' : OnboardingCopy.settingsNotificationsNotLive,
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
