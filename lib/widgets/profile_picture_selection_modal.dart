import 'dart:async';

import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:flutter/material.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/features/profile/data/avatar_catalog.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';

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

  // The app's fixed avatar set (ids 1-5).
  static const List<String> _availableImages = kAvatarAssets;

  @override
  void initState() {
    super.initState();
    _selectedImageId = avatarIdForAsset(widget.currentProfilePicture);
  }

  void _selectProfilePicture(int imageId) {
    setState(() {
      _selectedImageId = imageId;
    });
  }

  /// Saves the choice to the signed-in person's own account through the BFF
  /// (`account.updateProfile`). Works the same for a wallet sign-in and a
  /// Google/X sign-in, and can only ever change the caller's own picture.
  Future<void> _saveProfilePicture() async {
    final avatarId = _selectedImageId;
    if (avatarId == null || _isLoading) return;
    final api = accountApiOf(context);
    if (api == null) {
      // Nothing to save to until there is a Chumbucket account.
      requestCallSignIn(context);
      return;
    }
    final profileProvider = context.read<ProfileProvider?>();
    final calls = context.read<CallsProvider?>();
    final wallet = context.read<MwaAuthProvider?>()?.walletAddress;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isLoading = true);
    try {
      final saved = await api.updateProfile(avatarId: avatarId);
      final asset = saved.avatarAsset;
      // Keep this device's legacy surfaces (header, wallet profile) in step.
      await profileProvider?.setUserPfp(wallet ?? saved.userId, asset);
      // And the calls directory, so the feed shows the new picture at once.
      unawaited(calls?.loadPerson(saved.userId, force: true));
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Profile picture updated'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, avatarId);
    } on CallsSignedOutException {
      if (!mounted) return;
      requestCallSignIn(context);
    } on CallsException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is CallsOfflineException
                ? 'You\'re offline. Your picture wasn\'t changed.'
                : e.message,
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Your picture wasn\'t changed. Please try again.'),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
