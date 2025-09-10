import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/widgets/friend_avatar.dart';
import 'package:chumbucket/widgets/wavy_container.dart';

class ChallengeDetailsScreen extends StatefulWidget {
  final String friendName;
  final String friendAvatarColor;
  final String userAvatarColor;
  final String description;
  final double amount;
  final bool isActive;

  const ChallengeDetailsScreen({
    super.key,
    required this.friendName,
    required this.friendAvatarColor,
    required this.userAvatarColor,
    required this.description,
    required this.amount,
    this.isActive = true,
  });

  @override
  State<ChallengeDetailsScreen> createState() => _ChallengeDetailsScreenState();
}

class _ChallengeDetailsScreenState extends State<ChallengeDetailsScreen> {
  bool _isProcessing = false;

  Future<void> _markAsCompleted() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // Here you would call your wallet provider to complete the challenge
      // and release the funds
      await Future.delayed(const Duration(seconds: 2)); // Simulate API call

      if (mounted) {
        Navigator.pop(context, {'status': 'completed'});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _markAsFailed() async {
    try {
      // Here you would call your wallet provider to mark the challenge as failed
      // This might release funds back to participants or handle according to rules

      if (mounted) {
        Navigator.pop(context, {'status': 'failed'});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [_buildHeader(), Expanded(child: _buildChallengeDetails())],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 16.w),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, size: 24.sp),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          Text(
            'Challenge Details',
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          SizedBox(width: 24.w), // For balance in the header
        ],
      ),
    );
  }

  Widget _buildChallengeDetails() {
    return Stack(
      children: [
        // Background color
        Container(color: Colors.grey[100]),

        // Challenge card
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              children: [
                _buildChallengeCard(),
                SizedBox(height: 20.h),
                if (widget.isActive) _buildActionButtons(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChallengeCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pink header with amount
          _buildAmountHeader(),

          // Avatars
          _buildAvatarsSection(),

          // Challenge description
          _buildDescriptionSection(),

          SizedBox(height: 20.h),
        ],
      ),
    );
  }

  Widget _buildAmountHeader() {
    return WavyContainer(
      height: 160.h,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Bet Amount',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              '\$${widget.amount.toStringAsFixed(1)}',
              style: TextStyle(
                color: Colors.white,
                fontSize: 40.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarsSection() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              FriendAvatar(
                name: 'You',
                colorHex: widget.userAvatarColor,
                onTap: () {},
                size: 50,
              ),
              SizedBox(height: 8.h),
              Text(
                'You',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          SizedBox(width: 40.w),
          Column(
            children: [
              FriendAvatar(
                name: widget.friendName,
                colorHex: widget.friendAvatarColor,
                onTap: () {},
                size: 50,
              ),
              SizedBox(height: 8.h),
              Text(
                widget.friendName,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Text(
        widget.description,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _markAsCompleted,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30.r),
              ),
              padding: EdgeInsets.symmetric(vertical: 16.h),
              disabledBackgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withAlpha(150),
            ),
            child:
                _isProcessing
                    ? SizedBox(
                      height: 20.h,
                      width: 20.h,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                    : Text(
                      'Challenge Completed',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
          ),
        ),
        SizedBox(height: 16.h),
        TextButton(
          onPressed: _markAsFailed,
          child: Text(
            'Failed to complete',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
