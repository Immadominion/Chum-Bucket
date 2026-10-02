import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:flutter/material.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';

class ProfilePictureSelectionModal extends StatefulWidget {
  final String? currentProfilePicture;

  const ProfilePictureSelectionModal({super.key, this.currentProfilePicture});

  static Future<int?> show(
    BuildContext context, {
    String? currentProfilePicture,
  }) async {
    return showChumbucketWavySheet<int>(
      context: context,
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
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      final profileProvider = Provider.of<ProfileProvider>(
        context,
        listen: false,
      );
      final walletAddress = authProvider.walletAddress;

      if (walletAddress != null) {
        final imagePath = _availableImages[_selectedImageId! - 1];
        final success = await profileProvider.setUserPfp(
          walletAddress,
          imagePath,
        );

        if (success && mounted) {
          // Force deep state refresh by re-fetching user profile with new PFP
          // This will cause all dependent widgets to rebuild with new profile picture
          await profileProvider.fetchUserProfileWithPfp(walletAddress);
          if (!mounted) return;

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
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Choose Your Avatar',
    subtitle: 'Select from our collection',
    canDismiss: !_isLoading,
    onClose: _cancelSelection,
    body: _buildProfilePictureGrid(),
    footer: _buildActionButtons(),
  );

  Widget _buildProfilePictureGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
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
                            color: const Color(
                              0xFFFF5A76,
                            ).withValues(alpha: 0.2),
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
                                child: BasilIcon(
                                  'check-outline',
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The sheet's call to action and its text-only secondary, shared
          // with every other sheet. Real buttons, so screen readers announce
          // them (the hand-rolled GestureDetectors here were silent).
          ChumbucketPrimaryButton(
            label: 'Save Profile Picture',
            busy: _isLoading,
            onPressed: _selectedImageId == null ? null : _saveProfilePicture,
          ),
          const SizedBox(height: 4),
          ChumbucketTextAction(
            label: 'Cancel',
            onPressed: _isLoading ? null : _cancelSelection,
          ),
        ],
      ),
    );
  }
}
