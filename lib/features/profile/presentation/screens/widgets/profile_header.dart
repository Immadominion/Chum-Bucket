import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// The existing identity, on the white half of the joined profile surface.
class ProfileHeader extends StatelessWidget {
  final String username;
  final String bio;
  final String? profileImagePath;
  final VoidCallback onEditProfile;
  final String? handle;
  final bool canEdit;
  final Widget? footer;
  final VoidCallback? onEditAvatar;

  const ProfileHeader({
    super.key,
    required this.username,
    required this.bio,
    this.profileImagePath,
    required this.onEditProfile,
    this.handle,
    this.canEdit = true,
    this.footer,
    this.onEditAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final name = username.trim().isEmpty ? 'Your profile' : username;
    final initials = name.trim().characters.first;
    final image = profileImagePath;
    final fallback = AppAvatar(
      initials: initials,
      size: 68,
      backgroundColor: AppColors.primaryContainer,
      textColor: AppColors.onPrimaryContainer,
    );
    final avatar =
        image != null && image.startsWith('assets/')
            ? ClipOval(
              child: Image.asset(
                image,
                width: 68,
                height: 68,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
            )
            : AppAvatar(
              initials: initials,
              imageUrl: image,
              size: 68,
              backgroundColor: AppColors.primaryContainer,
              textColor: AppColors.onPrimaryContainer,
            );
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: styles.headlineSmall),
        if (handle != null && handle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '@${handle!.replaceFirst(RegExp(r'^@'), '')}',
            style: styles.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(24) > 32;
              final portrait =
                  canEdit && onEditAvatar != null
                      ? Semantics(
                        button: true,
                        label: 'Edit profile picture',
                        child: InkWell(
                          onTap: onEditAvatar,
                          borderRadius: BorderRadius.circular(40),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: avatar,
                          ),
                        ),
                      )
                      : avatar;
              final edit =
                  canEdit
                      ? IconButton(
                        tooltip: 'Edit profile',
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        onPressed: onEditProfile,
                        icon: const BasilIcon(
                          'edit-outline',
                          color: AppColors.textPrimary,
                        ),
                      )
                      : const SizedBox.shrink();
              if (largeText) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [portrait, const Spacer(), edit]),
                    const SizedBox(height: 12),
                    identity,
                  ],
                );
              }
              return Row(
                children: [
                  portrait,
                  const SizedBox(width: 12),
                  Expanded(child: identity),
                  edit,
                ],
              );
            },
          ),
          if (bio.trim().isNotEmpty && bio != 'null') ...[
            const SizedBox(height: 16),
            Text(bio, style: styles.bodyMedium?.copyWith(height: 1.6)),
          ],
          if (footer != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.divider),
            footer!,
          ],
        ],
      ),
    );
  }
}
