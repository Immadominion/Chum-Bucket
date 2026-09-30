import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';

class DatabaseActions {
  static void showClearDatabaseDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Clear Database'),
            content: const Text(
              'This will delete ALL data including friends, challenges, and other records. This action cannot be undone.\n\nAre you sure?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await UnifiedDatabaseService.clearAllData();
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (!context.mounted) return;
                    SnackBarUtils.showInfo(
                      context,
                      title: 'Success',
                      subtitle: 'Database cleared successfully!',
                    );
                  } catch (e) {
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (!context.mounted) return;
                    SnackBarUtils.showError(
                      context,
                      title: 'Error',
                      subtitle: 'Failed to clear database: $e',
                    );
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Clear Database'),
              ),
            ],
          ),
    );
  }
}
