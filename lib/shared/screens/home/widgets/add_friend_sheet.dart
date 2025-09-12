import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:ui';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';

import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/widgets/widgets.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';

class AddFriendSheet extends StatefulWidget {
  final VoidCallback onFriendAdded;

  const AddFriendSheet({super.key, required this.onFriendAdded});

  @override
  State<AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<AddFriendSheet> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _addressFocusNode = FocusNode();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    // Add focus listeners to update border colors
    _nameFocusNode.addListener(() {
      setState(() {}); // Update border color when focus changes
    });

    _addressFocusNode.addListener(() {
      setState(() {}); // Update border color when focus changes
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _nameFocusNode.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    final name = _nameController.text.trim();
    final addressInput = _addressController.text.trim();

    if (name.isEmpty || addressInput.isEmpty) {
      SnackBarUtils.showError(
        context,
        title: 'Input Error',
        subtitle: 'Please enter both name and wallet address/domain',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Normalize to wallet address only
      String? walletAddress;
      if (AddressNameResolver.isBase58Address(addressInput)) {
        walletAddress = addressInput;
      } else if (AddressNameResolver.isSolDomain(addressInput)) {
        walletAddress = await AddressNameResolver.resolveAddress(addressInput);
        if (walletAddress == null) {
          SnackBarUtils.showError(
            context,
            title: 'Resolution Error',
            subtitle: 'Could not resolve $addressInput to a wallet',
          );
          return;
        }
      } else {
        SnackBarUtils.showError(
          context,
          title: 'Input Error',
          subtitle: 'Enter a valid wallet or .sol domain',
        );
        return;
      }

      // Add friend to Supabase database
      final success = await UnifiedDatabaseService.addFriend(
        userPrivyId: currentUser.id,
        friendName: name,
        friendWalletAddress: walletAddress,
      );

      if (success) {
        widget.onFriendAdded();
        if (mounted) Navigator.pop(context);

        SnackBarUtils.showSuccess(
          context,
          title: '$name added as friend!',
          subtitle: 'You can now challenge them to duels',
        );
      } else {
        SnackBarUtils.showError(
          context,
          title: 'Failed to add friend',
          subtitle: 'Could not add $name as a friend. Please try again.',
        );
      }
    } catch (e) {
      SnackBarUtils.showError(
        context,
        title: 'Error adding friend',
        subtitle: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate responsive height with keyboard consideration
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = screenHeight * 0.85; // Max 85% of screen height
    final minHeight = 320.h;
    final preferredHeight = 480.h; // Appropriate height for form
    final finalHeight = preferredHeight.clamp(minHeight, maxHeight);

    return Padding(
      padding: EdgeInsets.only(top: 100.h, bottom: keyboardHeight * 0.15),
      child: Container(
        height: finalHeight,
        margin: EdgeInsets.symmetric(horizontal: 12.w),
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
        child: Column(
          children: [
            // Top section with gradient background
            Container(
              height: 180.h.clamp(140.h, maxHeight * 0.4),
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(43.r),
                  topRight: Radius.circular(43.r),
                ),
              ),
              child: Stack(
                children: [
                  // Header content
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 0),
                      child: Column(
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
                          SizedBox(height: 24.h),
                          Text(
                            'Add New Friend',
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            'Enter your friend\'s details to start challenging them',
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // White wavy bottom section
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ClipPath(
                      clipper: DetailedWaveClipper(),
                      child: Container(height: 40.h, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom section with form
            Expanded(
              child: Container(
                padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 24.h),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Name input
                      TextField(
                        controller: _nameController,
                        focusNode: _nameFocusNode,
                        onTap: () {
                          setState(
                            () {},
                          ); // Force rebuild to update border color
                        },
                        onChanged: (value) {
                          setState(() {}); // Force rebuild for validation
                        },
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) {
                          FocusScope.of(
                            context,
                          ).requestFocus(_addressFocusNode);
                        },
                        decoration: InputDecoration(
                          hintText: 'Friend\'s name',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 16.sp,
                          ),
                          prefixIcon: Container(
                            width: 20.w,
                            height: 20.w,
                            alignment: Alignment.center,
                            child: PhosphorIcon(
                              PhosphorIconsRegular.user,
                              color: const Color(0xFFFF5A76),
                              size: 20.w,
                            ),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16.w,
                            vertical: 16.h,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 16.h),

                      // Address input
                      TextField(
                        controller: _addressController,
                        focusNode: _addressFocusNode,
                        onTap: () {
                          setState(
                            () {},
                          ); // Force rebuild to update border color
                        },
                        onChanged: (value) {
                          setState(() {}); // Force rebuild for validation
                        },
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        decoration: InputDecoration(
                          hintText: 'Wallet address or .sol domain',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 16.sp,
                          ),
                          prefixIcon: Container(
                            width: 20.w,
                            height: 20.w,
                            alignment: Alignment.center,
                            child: PhosphorIcon(
                              PhosphorIconsRegular.wallet,
                              color: const Color(0xFFFF5A76),
                              size: 20.w,
                            ),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16.w,
                            vertical: 16.h,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      SizedBox(height: 20.h),

                      // Action buttons
                      ChallengeButton(
                        createNewChallenge: _isLoading ? () {} : _addFriend,
                        label: 'Add Friend',
                        enabled: !_isLoading,
                        isLoading: _isLoading,
                        blurRadius: false,
                      ),
                      SizedBox(height: 8.h),
                      // Cancel button styled like "Failed to complete"
                      TertiaryActionButton(
                        text: 'Cancel',
                        onPressed:
                            _isLoading ? null : () => Navigator.pop(context),
                        textColor: const Color(0xFFFF5A76),
                      ),
                      SizedBox(height: 20.h), // Extra padding at bottom
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

Future<void> showAddFriendSheet(
  BuildContext context, {
  required VoidCallback onFriendAdded,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.5),
    elevation: 0,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              // Ensure padding is never negative
              bottom: MediaQuery.of(
                context,
              ).viewInsets.bottom.clamp(0.0, double.infinity),
            ),
            child: AddFriendSheet(onFriendAdded: onFriendAdded),
          ),
        ),
      );
    },
  );
}
