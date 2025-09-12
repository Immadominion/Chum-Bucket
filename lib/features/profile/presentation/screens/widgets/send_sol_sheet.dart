import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/widgets/widgets.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/features/wallet/presentation/screens/sol_transfer_result_screen.dart';
import 'dart:ui';

class SendSolSheet extends StatefulWidget {
  const SendSolSheet({super.key});

  @override
  State<SendSolSheet> createState() => _SendSolSheetState();
}

class _SendSolSheetState extends State<SendSolSheet> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  final FocusNode _addressFocusNode = FocusNode();

  bool _isTransferring = false;
  double _maxAmount = 0.0;

  @override
  void initState() {
    super.initState();

    // Add focus listeners to update border colors
    _amountFocusNode.addListener(() {
      setState(() {}); // Update border color when focus changes
    });

    _addressFocusNode.addListener(() {
      setState(() {}); // Update border color when focus changes
    });

    // Get current balance for max amount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      setState(() {
        _maxAmount = walletProvider.balance;
      });
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _addressController.dispose();
    _amountFocusNode.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  void _useMaxAmount() {
    // Reserve small amount for transaction fees (0.001 SOL)
    final maxCashOut = (_maxAmount - 0.001).clamp(0.0, _maxAmount);
    _amountController.text = maxCashOut.toStringAsFixed(4);
  }

  bool _isValidAmount() {
    final text = _amountController.text.trim();
    if (text.isEmpty) return false;

    final amount = double.tryParse(text);
    if (amount == null) return false;

    return amount > 0 && amount <= _maxAmount;
  }

  bool _isValidAddress() {
    final address = _addressController.text.trim();
    if (address.isEmpty) return false;

    // Support both regular Solana addresses and .sol domains
    return AddressNameResolver.isBase58Address(address) ||
        AddressNameResolver.isSolDomain(address);
  }

  bool get _canSendSol =>
      _isValidAmount() && _isValidAddress() && !_isTransferring;

  Future<void> _performSendSol() async {
    if (!_canSendSol) return;

    setState(() {
      _isTransferring = true;
    });

    try {
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      final amount = double.parse(_amountController.text.trim());
      final addressInput = _addressController.text.trim();

      // Resolve domain name to address if needed
      String? destinationAddress = addressInput;
      if (AddressNameResolver.isSolDomain(addressInput)) {
        destinationAddress = await AddressNameResolver.resolveAddress(
          addressInput,
        );
        if (destinationAddress == null) {
          throw Exception('Could not resolve domain name: $addressInput');
        }
      }

      // Call wallet provider method to transfer SOL
      final transactionSignature = await walletProvider.transferSol(
        destinationAddress: destinationAddress,
        amount: amount,
        context: context,
      );

      if (transactionSignature != null && mounted) {
        // Close the sheet
        Navigator.of(context).pop();

        // Navigate to success screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (context) => SolTransferResultScreen(
                  status: SolTransferStatus.success,
                  destinationAddress:
                      addressInput, // Use original input (might be domain)
                  amount: amount,
                  transactionSignature: transactionSignature,
                  onDone: () => Navigator.of(context).pop(),
                ),
          ),
        );

        SnackBarUtils.showSuccess(
          context,
          title: 'Transfer Successful',
          subtitle: 'Sent ${amount.toStringAsFixed(4)} SOL to $addressInput',
        );
      }
    } catch (e) {
      if (mounted) {
        // Close the sheet
        Navigator.of(context).pop();

        // Navigate to error screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (context) => SolTransferResultScreen(
                  status: SolTransferStatus.failed,
                  errorMessage: e.toString(),
                  destinationAddress: _addressController.text.trim(),
                  amount: double.tryParse(_amountController.text.trim()),
                  onDone: () => Navigator.of(context).pop(),
                ),
          ),
        );

        SnackBarUtils.showError(
          context,
          title: 'Transfer Failed',
          subtitle: 'Error sending SOL: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTransferring = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 80.h,
        bottom: MediaQuery.of(context).viewInsets.bottom * 0.1,
      ),
      child: Container(
        // Simplified height calculation to prevent issues
        height: MediaQuery.of(context).size.height * 0.7,
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
              height: 200.h.clamp(
                160.h,
                MediaQuery.of(context).size.height * 0.4,
              ),
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
                            width: 43.w,
                            height: 3.2.h,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(2.r),
                            ),
                          ),
                          SizedBox(height: 24.h),
                          // Icon
                          Container(
                            width: 60.w,
                            height: 60.w,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(18.r),
                            ),
                            child: Icon(
                              PhosphorIcons.paperPlaneTilt(),
                              size: 32.w,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 16.h),
                          Text(
                            'Send SOL',
                            style: TextStyle(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Consumer<WalletProvider>(
                            builder: (context, walletProvider, _) {
                              return Text(
                                'Available: ${walletProvider.balance.toStringAsFixed(4)} SOL',
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              );
                            },
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
                      // Amount input
                      Text(
                        'Amount (SOL)',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(
                            color:
                                _amountFocusNode.hasFocus
                                    ? const Color(0xFFFF5A76)
                                    : Colors.grey.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _amountController,
                                focusNode: _amountFocusNode,
                                onTap: () {
                                  setState(
                                    () {},
                                  ); // Force rebuild to update border color
                                },
                                onChanged: (value) {
                                  setState(
                                    () {},
                                  ); // Force rebuild for validation
                                },
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                textInputAction: TextInputAction.next,
                                onSubmitted:
                                    (_) => _addressFocusNode.requestFocus(),
                                decoration: InputDecoration(
                                  hintText: '0.05',
                                  hintStyle: TextStyle(
                                    fontSize: 16.sp,
                                    color: Colors.grey.shade400,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.r),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.r),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.r),
                                    borderSide: BorderSide.none,
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.r),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16.r),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16.w,
                                    vertical: 16.h,
                                  ),
                                ),
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            // Max button
                            Padding(
                              padding: EdgeInsets.only(right: 8.w),
                              child: TextButton(
                                onPressed: _useMaxAmount,
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(
                                    0xFFFF5A76,
                                  ).withOpacity(0.1),
                                  foregroundColor: const Color(0xFFFF5A76),
                                  minimumSize: Size(50.w, 32.h),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12.w,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                ),
                                child: Text(
                                  'MAX',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 20.h),

                      // Recipient address input
                      Text(
                        'Recipient Address',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(
                            color:
                                _addressFocusNode.hasFocus
                                    ? const Color(0xFFFF5A76)
                                    : Colors.grey.shade200,
                          ),
                        ),
                        child: TextField(
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
                            hintText: 'Enter wallet address or .sol domain',
                            hintStyle: TextStyle(
                              fontSize: 16.sp,
                              color: Colors.grey.shade400,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.r),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.r),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.r),
                              borderSide: BorderSide.none,
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.r),
                              borderSide: BorderSide.none,
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16.r),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 16.h,
                            ),
                          ),
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                        ),
                      ),

                      SizedBox(height: 20.h),

                      // Action buttons
                      ChallengeButton(
                        createNewChallenge:
                            _canSendSol ? _performSendSol : () {},
                        label: _isTransferring ? 'Sending...' : 'Send SOL',
                        enabled: _canSendSol,
                        isLoading: _isTransferring,
                      ),
                      SizedBox(height: 8.h),
                      // Cancel button styled like "Failed to complete"
                      TertiaryActionButton(
                        text: 'Cancel',
                        onPressed:
                            _isTransferring
                                ? null
                                : () => Navigator.pop(context),
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

Future<void> showSendSolSheet(BuildContext context) async {
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
            child: const SendSolSheet(),
          ),
        ),
      );
    },
  );
}
