import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'dart:ui';

/// Send SOL modal following the app's design system
class CashOutModal extends StatefulWidget {
  const CashOutModal({super.key});

  @override
  State<CashOutModal> createState() => _CashOutModalState();
}

class _CashOutModalState extends State<CashOutModal> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  final FocusNode _addressFocusNode = FocusNode();

  bool _isTransferring = false;
  double _maxAmount = 0.0;

  @override
  void initState() {
    super.initState();
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
    // Basic Solana address validation (32-44 characters, base58)
    if (address.length < 32 || address.length > 44) return false;

    // Check for valid base58 characters
    final base58Regex = RegExp(
      r'^[123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz]+$',
    );
    return base58Regex.hasMatch(address);
  }

  bool get _canCashOut =>
      _isValidAmount() && _isValidAddress() && !_isTransferring;

  Future<void> _performCashOut() async {
    if (!_canCashOut) return;

    setState(() {
      _isTransferring = true;
    });

    try {
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      final amount = double.parse(_amountController.text.trim());
      final destinationAddress = _addressController.text.trim();

      // Call wallet provider method to transfer SOL
      final success = await walletProvider.transferSol(
        destinationAddress: destinationAddress,
        amount: amount,
        context: context,
      );

      if (success && mounted) {
        // Close modal and show success message
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              padding: EdgeInsets.symmetric(vertical: 4.h),
              child: Row(
                children: [
                  Container(
                    width: 20.w,
                    height: 20.w,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(
                      PhosphorIcons.checkCircle(),
                      size: 16.w,
                      color: Colors.green.shade600,
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SOL Transfer Successful! 🎉',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16.sp,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          '${amount.toStringAsFixed(4)} SOL transferred',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16.w),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            duration: const Duration(seconds: 4),
            elevation: 8,
          ),
        );
      } else if (mounted) {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              padding: EdgeInsets.symmetric(vertical: 4.h),
              child: Row(
                children: [
                  Container(
                    width: 20.w,
                    height: 20.w,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(
                      PhosphorIcons.warning(),
                      size: 16.w,
                      color: Colors.red.shade600,
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SOL Transfer Failed',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16.sp,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          'Please check your details and try again',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16.w),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            duration: const Duration(seconds: 4),
            elevation: 8,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer failed: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
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
    // Calculate responsive height
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.85;
    final minHeight = 500.h;
    final preferredHeight = 650.h;
    final finalHeight = preferredHeight.clamp(minHeight, maxHeight);

    return Container(
      height: finalHeight,
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26.r),
      ),
      child: Column(
        children: [_buildHeader(), Expanded(child: _buildScrollableContent())],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 200.h,
      child: Stack(
        children: [
          // Gradient background
          Container(
            height: 200.h,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(26),
                topRight: Radius.circular(26),
              ),
            ),
          ),
          // Wave clipper
          ClipPath(
            clipper: DetailedWaveClipper(),
            child: Container(
              height: 200.h,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.3),
                    Colors.white.withOpacity(0.1),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          // Content
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
                child: Column(
                  children: [
                    // Close button and title
                    Row(
                      children: [
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20.r),
                            ),
                            child: Icon(
                              PhosphorIcons.x(),
                              color: Colors.white,
                              size: 24.w,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Title and subtitle
                    Text(
                      'Send SOL',
                      style: TextStyle(
                        fontSize: 28.sp,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Consumer<WalletProvider>(
                      builder: (context, walletProvider, _) {
                        return Text(
                          '${walletProvider.balance.toStringAsFixed(4)} SOL Available',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        );
                      },
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableContent() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Amount display
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 32.h),
            child: Column(
              children: [
                Text(
                  'Amount',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                SizedBox(height: 16.h),
                // Large amount display
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: TextField(
                        controller: _amountController,
                        focusNode: _amountFocusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'),
                          ),
                        ],
                        style: TextStyle(
                          fontSize: 64.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(
                            fontSize: 64.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade300,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'SOL',
                      style: TextStyle(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Use Max button
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  PhosphorIcons.coins(),
                  size: 24.w,
                  color: Colors.green.shade600,
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                'Solana',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _useMaxAmount,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 8.h,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    'Use Max',
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 40.h),

          // Destination Address Input
          Text(
            'Destination Wallet Address',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 12.h),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color:
                    _addressFocusNode.hasFocus
                        ? const Color(0xFFFF5A76)
                        : Colors.grey.shade300,
                width: _addressFocusNode.hasFocus ? 2 : 1,
              ),
            ),
            child: TextField(
              controller: _addressController,
              focusNode: _addressFocusNode,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: 'Enter Solana wallet address',
                hintStyle: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 16.sp,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16.w),
                suffixIcon:
                    _addressController.text.isNotEmpty
                        ? IconButton(
                          onPressed: () {
                            _addressController.clear();
                            setState(() {});
                          },
                          icon: Icon(
                            PhosphorIcons.x(),
                            color: Colors.grey.shade400,
                            size: 20.w,
                          ),
                        )
                        : Icon(
                          PhosphorIcons.wallet(),
                          color: Colors.grey.shade400,
                          size: 20.w,
                        ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Validation messages
          if (_amountController.text.isNotEmpty && !_isValidAmount())
            Padding(
              padding: EdgeInsets.only(top: 8.h),
              child: Text(
                'Please enter a valid amount (max: ${_maxAmount.toStringAsFixed(4)} SOL)',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.red.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          if (_addressController.text.isNotEmpty && !_isValidAddress())
            Padding(
              padding: EdgeInsets.only(top: 8.h),
              child: Text(
                'Please enter a valid Solana wallet address',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.red.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          SizedBox(height: 40.h),

          // Send SOL Button
          ChallengeButton(
            createNewChallenge: _performCashOut,
            label: 'Send SOL',
            enabled: _canCashOut,
            isLoading: _isTransferring,
          ),

          SizedBox(height: 20.h),

          // Disclaimer
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  PhosphorIcons.info(),
                  color: Colors.blue.shade600,
                  size: 20.w,
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transaction Details',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'SOL will be transferred directly to the destination wallet. Transaction fees may apply. Please verify the wallet address before proceeding.',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: Colors.blue.shade700,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function to show the send SOL modal
void showCashOutModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (context) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
          child: const CashOutModal(),
        ),
  );
}
