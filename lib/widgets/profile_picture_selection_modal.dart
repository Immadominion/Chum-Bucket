import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';

class ProfilePictureSelectionModal extends StatefulWidget {
  final String? currentProfilePicture;

  const ProfilePictureSelectionModal({super.key, this.currentProfilePicture});

  static Future<int?> show(
    BuildContext context, {
    String? currentProfilePicture,
  }) async {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => ProfilePictureSelectionModal(
            currentProfilePicture: currentProfilePicture,
          ),
    );
  }

  @override
  State<ProfilePictureSelectionModal> createState() =>
      _ProfilePictureSelectionModalState();
}

class _ProfilePictureSelectionModalState
    extends State<ProfilePictureSelectionModal> {
  bool _isLoading = false;
  int? _selectedImageId;

  // Available profile images (1-5)
  static const List<String> _availableImages = [
    'assets/images/ai_gen/profile_images/1.png',
    'assets/images/ai_gen/profile_images/2.png',
    'assets/images/ai_gen/profile_images/3.png',
    'assets/images/ai_gen/profile_images/4.png',
    'assets/images/ai_gen/profile_images/5.png',
  ];

  @override
  void initState() {
    super.initState();
    // Set current selection based on current profile picture
    if (widget.currentProfilePicture != null) {
      final currentIndex = _availableImages.indexOf(
        widget.currentProfilePicture!,
      );
      if (currentIndex != -1) {
        _selectedImageId = currentIndex + 1;
      }
    }
  }

  void _selectProfilePicture(int imageId) {
    setState(() {
      _selectedImageId = imageId;
    });
  }

  Future<void> _saveProfilePicture() async {
    if (_selectedImageId == null) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final profileProvider = Provider.of<ProfileProvider>(
        context,
        listen: false,
      );
      final privyId = authProvider.currentUser?.id;

      if (privyId != null) {
        final imagePath = _availableImages[_selectedImageId! - 1];
        final success = await profileProvider.setUserPfp(privyId, imagePath);

        if (success && mounted) {
          // Force deep state refresh by re-fetching user profile with new PFP
          // This will cause all dependent widgets to rebuild with new profile picture
          await profileProvider.fetchUserProfileWithPfp(privyId);

          // Show success feedback
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Profile picture updated successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );

          // Close modal and return to trigger any parent refreshes
          Navigator.pop(context, _selectedImageId);

          // Navigate back to home to ensure full app refresh
          // This ensures all profile images across the app update immediately
          if (Navigator.canPop(context)) {
            Navigator.popUntil(context, (route) => route.isFirst);
          }
        } else if (mounted) {
          // Show error feedback
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Failed to update profile picture. Please try again.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _cancelSelection() {
    Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    // Calculate responsive height
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.85;
    final minHeight = 400.h;
    final preferredHeight = 580.h;
    final finalHeight = preferredHeight.clamp(minHeight, maxHeight);

    return Container(
      height: finalHeight,
      margin: EdgeInsets.only(left: 12.w, right: 12.w, bottom: 36.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(43.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(43.r),
        child: Column(
          children: [
            // Header with gradient background
            _buildHeader(),
            // Profile picture grid
            Expanded(child: _buildProfilePictureGrid()),
            // Action buttons
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 140.h,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 20.h),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Handle bar
              Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(height: 16.h),
              // Title
              Text(
                'Choose Your Avatar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Select from our collection',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfilePictureGrid() {
    return Padding(
      padding: EdgeInsets.all(24.w),
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 16.w,
                mainAxisSpacing: 16.h,
                childAspectRatio: 1,
              ),
              itemCount: _availableImages.length,
              itemBuilder: (context, index) {
                final imageId = index + 1;
                final imagePath = _availableImages[index];
                final isSelected = _selectedImageId == imageId;

                return GestureDetector(
                  onTap: () => _selectProfilePicture(imageId),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20.r),
                      border: Border.all(
                        color:
                            isSelected
                                ? const Color(0xFFFF5A76)
                                : Colors.grey[300]!,
                        width: isSelected ? 3 : 1,
                      ),
                      boxShadow: [
                        if (isSelected)
                          BoxShadow(
                            color: const Color(0xFFFF5A76).withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18.r),
                      child: Stack(
                        children: [
                          // Profile image
                          Positioned.fill(
                            child: Image.asset(imagePath, fit: BoxFit.cover),
                          ),
                          // Selected indicator
                          if (isSelected)
                            Positioned(
                              top: 8.r,
                              right: 8.r,
                              child: Container(
                                width: 24.r,
                                height: 24.r,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF5A76),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.check,
                                  size: 16.r,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Primary action button - Save (following ChallengeButton pattern)
          GestureDetector(
            onTap:
                (_isLoading || _selectedImageId == null)
                    ? null
                    : _saveProfilePicture,
            child: Container(
              height: 56.h,
              decoration: BoxDecoration(
                gradient:
                    (_selectedImageId != null && !_isLoading)
                        ? const LinearGradient(
                          colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                        : null,
                color:
                    (_selectedImageId == null || _isLoading)
                        ? Colors.grey[300]
                        : null,
                borderRadius: BorderRadius.circular(28.r),
                boxShadow:
                    (_selectedImageId != null && !_isLoading)
                        ? [
                          BoxShadow(
                            color: const Color(0xFFFF5A76).withOpacity(0.3),
                            offset: const Offset(0, 4),
                            blurRadius: 12,
                          ),
                        ]
                        : null,
              ),
              child: Center(
                child:
                    _isLoading
                        ? SizedBox(
                          width: 24.r,
                          height: 24.r,
                          child: const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                            strokeWidth: 2.5,
                          ),
                        )
                        : Text(
                          'Save Profile Picture',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w700,
                            color:
                                (_selectedImageId != null && !_isLoading)
                                    ? Colors.white
                                    : Colors.grey[600],
                          ),
                        ),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          // Secondary action - Cancel (following TertiaryActionButton pattern)
          GestureDetector(
            onTap: _isLoading ? null : _cancelSelection,
            child: Container(
              height: 44.h,
              child: Center(
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color:
                        _isLoading ? Colors.grey[400] : const Color(0xFFFF5A76),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
