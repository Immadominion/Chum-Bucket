import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/local_database_service.dart';
import '../services/unified_database_service.dart';

class DatabaseTestScreen extends StatefulWidget {
  const DatabaseTestScreen({Key? key}) : super(key: key);

  @override
  State<DatabaseTestScreen> createState() => _DatabaseTestScreenState();
}

class _DatabaseTestScreenState extends State<DatabaseTestScreen> {
  String _status = 'Ready';
  Map<String, int> _stats = {};

  Future<void> _testLocalDatabase() async {
    setState(() {
      _status = 'Testing local database...';
    });

    try {
      // Configure unified database service for local mode
      UnifiedDatabaseService.configure(
        mode: DatabaseMode.local,
        supabase: null,
      );

      // Test creating a challenge
      final challenge = await UnifiedDatabaseService.createChallenge(
        title: 'Test Challenge',
        description: 'This is a test challenge for local SQLite database',
        amountInSol: 1.0,
        creatorId: 'test_user_123',
        member1Address: 'test_address_1',
        member2Address: 'test_address_2',
        platformFee: 0.01,
        winnerAmount: 0.99,
      );

      // Get database stats
      final stats = await LocalDatabaseService.getDatabaseStats();

      setState(() {
        _status =
            'Database test successful!\nChallenge ID: ${challenge.id}\nTitle: ${challenge.title}';
        _stats = stats;
      });
    } catch (e) {
      setState(() {
        _status = 'Database test failed: $e';
      });
    }
  }

  Future<void> _clearDatabase() async {
    setState(() {
      _status = 'Clearing database...';
    });

    try {
      await LocalDatabaseService.clearAllData();
      final stats = await LocalDatabaseService.getDatabaseStats();

      setState(() {
        _status = 'Database cleared successfully!';
        _stats = stats;
      });
    } catch (e) {
      setState(() {
        _status = 'Clear database failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Database Test'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Database Mode: ${UnifiedDatabaseService.currentMode}',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text('Status: $_status', style: TextStyle(fontSize: 14.sp)),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16.h),
            if (_stats.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Database Statistics',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      ..._stats.entries.map(
                        (entry) => Text(
                          '${entry.key}: ${entry.value}',
                          style: TextStyle(fontSize: 14.sp),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16.h),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _testLocalDatabase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                    ),
                    child: Text(
                      'Test Database',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _clearDatabase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                    ),
                    child: Text(
                      'Clear Database',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20.h),
            Expanded(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Local Database Benefits:',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        '• No internet required for development\n'
                        '• Instant database changes\n'
                        '• Full control over schema\n'
                        '• No API rate limits\n'
                        '• Perfect for testing and debugging\n'
                        '• Automatically syncs when ready',
                        style: TextStyle(fontSize: 14.sp),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
