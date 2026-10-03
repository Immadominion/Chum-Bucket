import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';

Widget buildFriendItem(
  Map<String, String> friend,
  void Function(Map<String, String> friend) onFriendSelected,
) {
  final name = friend['name'] ?? '';
  final label = friend['xLabel'] ?? name;
  final image = friend['imagePath'];
  final fallback = AppAvatar(
    initials: label.isEmpty ? '?' : label.characters.first,
    size: 64,
    backgroundColor: AppColors.primaryContainer,
    textColor: AppColors.onPrimaryContainer,
  );
  return Semantics(
    button: true,
    label: 'Open $label',
    child: InkWell(
      onTap: () => onFriendSelected(friend),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child:
                  image == null
                      ? fallback
                      : ClipOval(
                        child: Image.asset(
                          image,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => fallback,
                        ),
                      ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
