import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/data/match_arena_service.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';

/// Pick an outcome bucket and stake USDC into the shared match pot. This is a
/// solo stake into a parimutuel pot, not a 1-v-1 friend dare.
class DareYourselfScreen extends StatefulWidget {
  final ArenaMatchEntry match;

  const DareYourselfScreen({super.key, required this.match});

  @override
  State<DareYourselfScreen> createState() => _DareYourselfScreenState();
}

class _DareYourselfScreenState extends State<DareYourselfScreen> {
  int? _selectedBucket;
  final TextEditingController _amountController = TextEditingController();
  bool _isSubmitting = false;
  String? _serviceError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureService());
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _ensureService() async {
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
    final arena = Provider.of<ArenaProvider>(context, listen: false);
    if (arena.isArenaServiceReady) return;
    try {
      await arena.ensureArenaService(
        authProvider: authProvider,
        walletAddress: authProvider.walletAddress,
        rpcUrl: NetworkConfig.rpcUrl,
      );
      if (mounted) setState(() => _serviceError = null);
    } catch (e) {
      if (mounted) setState(() => _serviceError = e.toString());
    }
  }

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  Future<void> _submit() async {
    final arena = Provider.of<ArenaProvider>(context, listen: false);

    if (_selectedBucket == null) {
      SnackBarUtils.showError(
        context,
        title: 'Pick an outcome',
        subtitle: 'Choose HOME, DRAW or AWAY before placing your call.',
      );
      return;
    }
    if (_amount <= 0) {
      SnackBarUtils.showError(
        context,
        title: 'Enter a stake',
        subtitle: 'Enter how much USDC you want to stake.',
      );
      return;
    }
    if (!arena.isArenaServiceReady) {
      await _ensureService();
      if (!mounted) return;
      if (!arena.isArenaServiceReady) {
        SnackBarUtils.showError(
          context,
          title: 'Wallet not ready',
          subtitle: _serviceError ?? 'Could not connect to your wallet yet.',
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      await arena.placeCall(
        match: widget.match,
        bucket: _selectedBucket!,
        amountUsdc: _amount,
      );
      if (!mounted) return;
      SnackBarUtils.showSuccess(
        context,
        title: 'Call placed',
        subtitle:
            '${ArenaFormat.usdc(_amount)} staked on ${ArenaFormat.bucketLabel(_selectedBucket!)}.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not place call',
        subtitle: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final market = widget.match.resultMarket;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'Make a call',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.match.fixture.competition,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  widget.match.fixture.title,
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 24.h),
                Text(
                  'Call an outcome',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12.h),
                if (market != null) _buildBucketPicker(market),
                SizedBox(height: 28.h),
                Text(
                  'Your stake',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12.h),
                _buildAmountInput(),
                SizedBox(height: 16.h),
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Text(
                    'If your bucket wins, everyone who called it splits the '
                    'losers\' pool pro-rata (after a small house rake). USDC '
                    'moves into the shared pot the moment you sign - not '
                    'into any individual\'s wallet.',
                    style: TextStyle(
                      fontSize: 11.5.sp,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                if (_serviceError != null) ...[
                  SizedBox(height: 12.h),
                  Text(
                    _serviceError!,
                    style: TextStyle(color: AppColors.error, fontSize: 12.sp),
                  ),
                ],
                SizedBox(height: 32.h),
                _buildSubmitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBucketPicker(ArenaMarket market) {
    return Row(
      children:
          [
            MatchArenaService.bucketHome,
            MatchArenaService.bucketDraw,
            MatchArenaService.bucketAway,
          ].map((bucket) {
            final total = market.bucketByIndex(bucket);
            final selected = _selectedBucket == bucket;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedBucket = bucket),
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 4.w),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primaryContainer : Colors.white,
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(
                      color:
                          selected ? AppColors.primary : Colors.grey.shade300,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        ArenaFormat.bucketLabel(bucket),
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppColors.primary : Colors.black,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        total != null
                            ? ArenaFormat.usdcFromBaseUnits(total.stake)
                            : '0 USDC',
                        style: TextStyle(
                          fontSize: 10.5.sp,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (total != null)
                        Text(
                          ArenaFormat.percent(total.impliedProb),
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildAmountInput() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                // Digits and a single decimal point; any excess precision
                // beyond USDC's 6 decimals is simply rounded away when
                // converting to base units, so this only needs to keep the
                // field numeric - not fully validate structure.
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '0.00',
                hintStyle: TextStyle(color: Colors.grey.shade400),
              ),
            ),
          ),
          Text(
            'USDC',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final label =
        _amount > 0
            ? 'Place call • ${ArenaFormat.usdc(_amount)}'
            : 'Place call';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          padding: EdgeInsets.symmetric(vertical: 16.h),
        ),
        child:
            _isSubmitting
                ? SizedBox(
                  height: 20.h,
                  width: 20.h,
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                : Text(
                  label,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
      ),
    );
  }
}
