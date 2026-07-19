import 'dart:async';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:ui';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';

import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:chumbucket/shared/widgets/widgets.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';
import 'package:chumbucket/shared/utils/safe_modal_utils.dart';

class AddFriendSheet extends StatefulWidget {
  final VoidCallback onFriendAdded;

  const AddFriendSheet({super.key, required this.onFriendAdded});

  @override
  State<AddFriendSheet> createState() => _AddFriendSheetState();
}

/// Validation state for address input
enum AddressValidationState { idle, validating, valid, invalid }

/// Which identifier the user is adding a friend by - a real wallet
/// address/domain (resolved immediately), or an X handle (may not have
/// joined ChumBucket yet, in which case the add is recorded as pending and
/// resolves automatically once that handle links a wallet).
enum _FriendInputMode { wallet, xHandle }

class _AddFriendSheetState extends State<AddFriendSheet> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _xHandleController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _addressFocusNode = FocusNode();
  final FocusNode _xHandleFocusNode = FocusNode();
  bool _isLoading = false;
  _FriendInputMode _inputMode = _FriendInputMode.wallet;

  // Address validation state
  AddressValidationState _addressValidation = AddressValidationState.idle;
  String? _resolvedAddress; // Cached resolved address
  Timer? _debounceTimer;

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

    _xHandleFocusNode.addListener(() {
      setState(() {}); // Update border color when focus changes
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameController.dispose();
    _addressController.dispose();
    _xHandleController.dispose();
    _nameFocusNode.dispose();
    _addressFocusNode.dispose();
    _xHandleFocusNode.dispose();
    super.dispose();
  }

  /// Validate address input with debouncing
  void _validateAddress(String value) {
    _debounceTimer?.cancel();

    final trimmed = value.trim();

    // Reset state for empty input
    if (trimmed.isEmpty) {
      setState(() {
        _addressValidation = AddressValidationState.idle;
        _resolvedAddress = null;
      });
      return;
    }

    // Check if it's already a valid base58 address
    if (AddressNameResolver.isBase58Address(trimmed)) {
      setState(() {
        _addressValidation = AddressValidationState.valid;
        _resolvedAddress = trimmed;
      });
      return;
    }

    // Check if it looks like a domain
    if (!AddressNameResolver.isSupportedDomain(trimmed)) {
      // Not a valid address format and not a domain
      setState(() {
        _addressValidation = AddressValidationState.invalid;
        _resolvedAddress = null;
      });
      return;
    }

    // It's a domain, debounce the resolution
    setState(() => _addressValidation = AddressValidationState.validating);

    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;

      try {
        final resolved = await AddressNameResolver.resolveAddress(trimmed);
        if (!mounted) return;

        if (resolved != null) {
          setState(() {
            _addressValidation = AddressValidationState.valid;
            _resolvedAddress = resolved;
          });
        } else {
          setState(() {
            _addressValidation = AddressValidationState.invalid;
            _resolvedAddress = null;
          });
        }
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _addressValidation = AddressValidationState.invalid;
          _resolvedAddress = null;
        });
      }
    });
  }

  /// Build validation indicator widget
  Widget? _buildValidationIndicator() {
    switch (_addressValidation) {
      case AddressValidationState.idle:
        return null;
      case AddressValidationState.validating:
        return SizedBox(
          width: 20.w,
          height: 20.w,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade400),
          ),
        );
      case AddressValidationState.valid:
        return BasilIcon('check-solid', color: Colors.green, size: 22.w);
      case AddressValidationState.invalid:
        return BasilIcon('cancel-solid', color: Colors.red, size: 22.w);
    }
  }

  /// Segmented control switching between adding a friend by real wallet
  /// address/domain, or by X handle (pending until that handle joins).
  Widget _buildInputModeToggle() {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildInputModeButton(
              mode: _FriendInputMode.wallet,
              label: 'Wallet',
              icon: 'wallet-outline',
            ),
          ),
          Expanded(
            child: _buildInputModeButton(
              mode: _FriendInputMode.xHandle,
              label: 'X handle',
              icon: 'twitter-outline',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputModeButton({
    required _FriendInputMode mode,
    required String label,
    required String icon,
  }) {
    final selected = _inputMode == mode;
    return GestureDetector(
      onTap: () {
        if (_inputMode == mode) return;
        setState(() => _inputMode = mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(11.r),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                  : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            BasilIcon(
              icon,
              size: 15.w,
              color:
                  selected ? const Color(0xFFFF5A76) : Colors.grey.shade500,
            ),
            SizedBox(width: 6.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color:
                    selected ? const Color(0xFFFF3355) : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFriend() async {
    if (_inputMode == _FriendInputMode.xHandle) {
      await _addFriendByHandle();
      return;
    }

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

    // Validate before submitting
    if (_addressValidation == AddressValidationState.invalid) {
      SnackBarUtils.showError(
        context,
        title: 'Invalid Address',
        subtitle: 'Please enter a valid wallet address or domain',
      );
      return;
    }

    if (_addressValidation == AddressValidationState.validating) {
      SnackBarUtils.showInfo(
        context,
        title: 'Please Wait',
        subtitle: 'Validating address...',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      final walletAddress = authProvider.walletAddress;
      if (walletAddress == null) throw Exception('User not authenticated');

      // Use cached resolved address if available, otherwise resolve
      String? friendWalletAddress = _resolvedAddress;

      if (friendWalletAddress == null) {
        // Fallback resolution (shouldn't normally reach here)
        if (AddressNameResolver.isBase58Address(addressInput)) {
          friendWalletAddress = addressInput;
        } else if (AddressNameResolver.isSupportedDomain(addressInput)) {
          friendWalletAddress = await AddressNameResolver.resolveAddress(
            addressInput,
          );
          if (friendWalletAddress == null) {
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
            subtitle: 'Enter a valid wallet address or domain (.skr, .abc, ...)',
          );
          return;
        }
      }

      // Add friend to Supabase database
      final success = await UnifiedDatabaseService.addFriend(
        userPrivyId: walletAddress,
        friendName: name,
        friendWalletAddress: friendWalletAddress,
      );

      if (success) {
        await SafeModalUtils.safeCloseAndExecute(
          context,
          mounted: mounted,
          onComplete: () {
            widget.onFriendAdded();
            if (mounted) {
              SnackBarUtils.showSuccess(
                context,
                title: '$name added as friend!',
                subtitle: 'You can now challenge them to duels',
              );
            }
          },
        );
      } else {
        if (mounted) {
          SnackBarUtils.showError(
            context,
            title: 'Failed to add friend',
            subtitle: 'Could not add $name as a friend. Please try again.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError(
          context,
          title: 'Error adding friend',
          subtitle: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Add-by-handle path: signs an `add_pending_target` proof and hands it to
  /// [ArenaProvider]. If the handle already belongs to a linked wallet, the
  /// backend resolves it immediately and this behaves like a normal
  /// add-by-wallet; otherwise it's recorded server-side as a Venmo-style
  /// pending target and resolves automatically once that handle links a
  /// wallet - the UI must never imply the target is aware of the invite yet.
  Future<void> _addFriendByHandle() async {
    final name = _nameController.text.trim();
    final handleInput = _xHandleController.text.trim();

    if (name.isEmpty || handleInput.isEmpty) {
      SnackBarUtils.showError(
        context,
        title: 'Input Error',
        subtitle: 'Please enter both name and X handle',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      final walletAddress = authProvider.walletAddress;
      if (walletAddress == null) throw Exception('User not authenticated');

      final arenaProvider = Provider.of<ArenaProvider>(context, listen: false);
      final ArenaCreatePendingTargetResult result = await arenaProvider
          .addPendingTargetByHandle(
            authProvider: authProvider,
            xHandle: handleInput,
          );

      final normalizedHandle = handleInput
          .trim()
          .replaceFirst(RegExp(r'^@+'), '')
          .toLowerCase();

      if (result.alreadyResolved && result.resolvedWalletAddress != null) {
        // Mirror the web client's guard: the resolved handle might be the
        // caller's own linked X account, which must never be addable as a
        // "friend" of yourself.
        if (result.resolvedWalletAddress == walletAddress) {
          if (mounted) {
            SnackBarUtils.showError(
              context,
              title: 'Input Error',
              subtitle: "That's your own account.",
            );
          }
          return;
        }

        // The handle already belongs to a linked wallet - add it exactly
        // like a normal wallet-address friend.
        final success = await UnifiedDatabaseService.addFriend(
          userPrivyId: walletAddress,
          friendName: name,
          friendWalletAddress: result.resolvedWalletAddress!,
        );

        if (success) {
          await SafeModalUtils.safeCloseAndExecute(
            context,
            mounted: mounted,
            onComplete: () {
              widget.onFriendAdded();
              if (mounted) {
                SnackBarUtils.showSuccess(
                  context,
                  title: '$name added as friend!',
                  subtitle: 'You can now challenge them to duels',
                );
              }
            },
          );
        } else if (mounted) {
          SnackBarUtils.showError(
            context,
            title: 'Failed to add friend',
            subtitle: 'Could not add $name as a friend. Please try again.',
          );
        }
        return;
      }

      // Not resolved yet - pending, Venmo-style. Never imply @handle knows.
      await SafeModalUtils.safeCloseAndExecute(
        context,
        mounted: mounted,
        onComplete: () {
          if (mounted) {
            SnackBarUtils.showInfo(
              context,
              title: "You'll be notified",
              subtitle:
                  "@$normalizedHandle hasn't joined ChumBucket yet. We'll "
                  "add $name automatically once they link that handle.",
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError(
          context,
          title: 'Error adding friend',
          subtitle: e.toString(),
        );
      }
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
                          FocusScope.of(context).requestFocus(
                            _inputMode == _FriendInputMode.wallet
                                ? _addressFocusNode
                                : _xHandleFocusNode,
                          );
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
                            child: BasilIcon(
                              'user-outline',
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

                      // Mode toggle: real wallet address/domain, or an X
                      // handle (may not have joined ChumBucket yet).
                      _buildInputModeToggle(),
                      SizedBox(height: 16.h),

                      if (_inputMode == _FriendInputMode.wallet) ...[
                        // Address input with validation
                        TextField(
                          controller: _addressController,
                          focusNode: _addressFocusNode,
                          onTap: () {
                            setState(
                              () {},
                            ); // Force rebuild to update border color
                          },
                          onChanged: (value) {
                            _validateAddress(value);
                          },
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                          decoration: InputDecoration(
                            hintText:
                                'Wallet address or domain (.skr, .abc, ...)',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16.sp,
                            ),
                            prefixIcon: Container(
                              width: 20.w,
                              height: 20.w,
                              alignment: Alignment.center,
                              child: BasilIcon(
                                'wallet-outline',
                                color: const Color(0xFFFF5A76),
                                size: 20.w,
                              ),
                            ),
                            suffixIcon:
                                _buildValidationIndicator() != null
                                    ? Container(
                                      width: 20.w,
                                      height: 20.w,
                                      alignment: Alignment.center,
                                      child: _buildValidationIndicator(),
                                    )
                                    : null,
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
                        // Show resolved address hint when domain is validated
                        if (_addressValidation ==
                                AddressValidationState.valid &&
                            _resolvedAddress != null &&
                            AddressNameResolver.isSupportedDomain(
                              _addressController.text.trim(),
                            ))
                          Padding(
                            padding: EdgeInsets.only(left: 8.w, top: 4.h),
                            child: Text(
                              'Resolves to: ${_resolvedAddress!.substring(0, 6)}...${_resolvedAddress!.substring(_resolvedAddress!.length - 4)}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.green.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        if (_addressValidation ==
                            AddressValidationState.invalid)
                          Padding(
                            padding: EdgeInsets.only(left: 8.w, top: 4.h),
                            child: Text(
                              'Invalid address or domain not found',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.red.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ] else ...[
                        // X handle input - no live validation: an unclaimed
                        // handle is a valid input, it just means the add
                        // resolves as pending until that handle joins.
                        TextField(
                          controller: _xHandleController,
                          focusNode: _xHandleFocusNode,
                          onTap: () {
                            setState(() {});
                          },
                          onChanged: (value) {
                            setState(() {});
                          },
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                          decoration: InputDecoration(
                            hintText: 'X handle (e.g. @username)',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16.sp,
                            ),
                            prefixIcon: Container(
                              width: 20.w,
                              height: 20.w,
                              alignment: Alignment.center,
                              child: BasilIcon(
                                'twitter-outline',
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
                        Padding(
                          padding: EdgeInsets.only(left: 8.w, top: 4.h),
                          child: Text(
                            "Haven't joined yet? We'll add them automatically "
                            'the moment they link this handle.',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],

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
              // Keyboard handling plus consistent bottom spacing
              bottom:
                  MediaQuery.of(
                    context,
                  ).viewInsets.bottom.clamp(0.0, double.infinity) +
                  (Platform.isIOS
                      ? MediaQuery.of(context).padding.bottom + 10.h
                      : MediaQuery.of(context).padding.bottom + 20.h),
            ),
            child: AddFriendSheet(onFriendAdded: onFriendAdded),
          ),
        ),
      );
    },
  );
}
