/// Settings → Privacy & data: analytics consent, export, blocked and muted
/// people, the legal documents, and account deletion — in one place.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/analytics/analytics_consent.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/trust/data/legal_links.dart';
import 'package:chumbucket/features/trust/presentation/blocked_people_screen.dart';
import 'package:chumbucket/features/trust/presentation/data_export.dart';
import 'package:chumbucket/features/trust/presentation/delete_account_screen.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class PrivacyDataScreen extends StatelessWidget {
  const PrivacyDataScreen({super.key, this.consent, this.opener});

  /// Injected by tests; otherwise the app-wide choice.
  final AnalyticsConsent? consent;
  final UrlOpener? opener;

  @override
  Widget build(BuildContext context) {
    final analytics = consent ?? AnalyticsConsent.instance;
    analytics.ensureLoaded();
    final styles = AppTextStyles.textTheme;
    void push(WidgetBuilder builder) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Privacy & data'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const _Heading('Analytics'),
          _Card(
            child: ListenableBuilder(
              listenable: analytics,
              builder:
                  (context, _) => SwitchListTile(
                    value: analytics.granted,
                    onChanged: analytics.setGranted,
                    activeTrackColor: AppColors.primary,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    title: Text(
                      'Share usage analytics',
                      style: styles.titleSmall,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Off unless you turn it on. Usage events never include '
                        'your name, wallet or theses, and today they stay on '
                        'this device. We\'ll ask again before sending them '
                        'anywhere.',
                        style: styles.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
            ),
          ),
          const _Heading('Your data'),
          _Row(
            icon: 'download-outline',
            title: 'Export my data',
            detail:
                'Your profile, calls, follows and trade records as a JSON file.',
            onTap: () => exportMyData(context),
          ),
          _Row(
            icon: 'user-block-outline',
            title: 'Blocked and muted',
            detail: 'See who you\'ve blocked or muted, and undo it.',
            onTap: () => push((_) => const BlockedPeopleScreen()),
          ),
          const _Heading('Legal'),
          _Row(
            icon: 'document-outline',
            title: 'Terms of Service',
            detail: 'Draft, pending legal review.',
            onTap:
                () =>
                    openExternalLink(context, LegalLinks.terms, opener: opener),
          ),
          _Row(
            icon: 'shield-outline',
            title: 'Privacy Policy',
            detail: 'What we collect and who receives it.',
            onTap:
                () => openExternalLink(
                  context,
                  LegalLinks.privacy,
                  opener: opener,
                ),
          ),
          const _Heading('Account'),
          _Row(
            icon: 'trash-outline',
            title: 'Delete account',
            detail: 'Permanently remove your account.',
            danger: true,
            onTap: () => push((_) => const DeleteAccountScreen()),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: AppTextStyles.textTheme.labelLarge?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.danger = false,
  });

  final String icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final color = danger ? AppColors.error : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Card(
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: BasilIcon(icon, color: color),
          title: Text(title, style: styles.titleSmall?.copyWith(color: color)),
          subtitle: Text(
            detail,
            style: styles.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          trailing: BasilIcon('arrow-right-outline', size: 20, color: color),
        ),
      ),
    );
  }
}
