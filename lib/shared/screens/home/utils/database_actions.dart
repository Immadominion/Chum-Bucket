import 'package:flutter/material.dart';
import 'package:chumbucket/shared/services/local_database_service.dart';

class DatabaseActions {
  static void showClearDatabaseDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear Database'),
            content: const Text(
              'This will delete ALL data including friends, challenges, and other records. This action cannot be undone.\n\nAre you sure?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await LocalDatabaseService.clearAllData();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Database cleared successfully!'),
                      ),
                    );
                  } catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error clearing database: $e'),
                        backgroundColor: Colors.red,
                      ),
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
