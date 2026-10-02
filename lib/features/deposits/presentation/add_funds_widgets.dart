import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show CallJourneyNote, callJourneyBody, callJourneyHeading;
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/deposits_models.dart';
import 'deposit_copy.dart';

const _cardFill = Color(0xFFF6F7F9);
const _rule = Color(0xFFE6E9ED);
const _good = Color(0xFF07644C);
const _goodFill = Color(0xFFE6F6EF);

/// The wallet's real mainnet balance, exactly as the server read it.
/// Never a cached guess: loading, failure and "not available" all say so.
class DepositBalanceCard extends StatelessWidget {
  const DepositBalanceCard({
    super.key,
    required this.address,
    required this.balance,
    required this.loading,
    required this.error,
    required this.onRefresh,
    this.available = true,
    this.now,
  });

  final String? address;
  final WalletBalance? balance;
  final bool loading;
  final DepositsException? error;
  final VoidCallback? onRefresh;

  /// False when this server can't read balances at all.
  final bool available;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final b = balance;
    return Semantics(
      container: true,
      label: 'Your wallet balance',
      child: Container(
        key: const ValueKey('deposit-balance-card'),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        decoration: BoxDecoration(
          color: _cardFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _rule),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const BasilIcon(
                  'wallet-outline',
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    address == null
                        ? 'Your wallet'
                        : 'Your wallet · ${shortAddress(address!)}',
                    style: callJourneyBody(12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onRefresh != null && available)
                  SizedBox.square(
                    dimension: 40,
                    child: IconButton(
                      key: const ValueKey('deposit-balance-refresh'),
                      tooltip: 'Refresh balance',
                      padding: EdgeInsets.zero,
                      onPressed: loading ? null : onRefresh,
                      icon:
                          loading
                              ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textSecondary,
                                ),
                              )
                              : const BasilIcon(
                                'refresh-outline',
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (!available)
              Text(
                'Balances aren\'t available right now.',
                style: callJourneyBody(13),
              )
            else if (b != null)
              _figures(context, b)
            else if (error != null && !loading)
              Text(
                'We couldn\'t read your balance just now.',
                key: const ValueKey('deposit-balance-error'),
                style: callJourneyBody(13),
              )
            else
              const _BalanceSkeleton(),
          ],
        ),
      ),
    );
  }

  Widget _figures(BuildContext context, WalletBalance b) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _figure(
              context,
              b.usdcLabel,
              'USDC',
              'to trade',
              24,
              const ValueKey('deposit-balance-usdc'),
            ),
            _figure(
              context,
              b.solLabel,
              'SOL',
              'for network fees',
              18,
              const ValueKey('deposit-balance-sol'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Solana mainnet · ${_age(b.readAt)}',
          style: callJourneyBody(11).copyWith(color: AppColors.textTertiary),
        ),
      ],
    ),
  );

  Widget _figure(
    BuildContext context,
    String value,
    String unit,
    String caption,
    double size,
    Key key,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: value, style: callJourneyHeading(context, size)),
            TextSpan(
              text: ' $unit',
              style: callJourneyHeading(
                context,
                size * .55,
              ).copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        key: key,
      ),
      Text(caption, style: callJourneyBody(11)),
    ],
  );

  String _age(DateTime readAt) {
    final seconds = (now ?? DateTime.now)().difference(readAt).inSeconds;
    if (seconds < 60) return 'updated just now';
    final minutes = seconds ~/ 60;
    return minutes == 1 ? 'updated 1 min ago' : 'updated $minutes min ago';
  }
}

class _BalanceSkeleton extends StatelessWidget {
  const _BalanceSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Reading your balance',
    child: const Padding(
      padding: EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          _Bar(width: 112, height: 26),
          SizedBox(width: 20),
          _Bar(width: 80, height: 20),
        ],
      ),
    ),
  );
}

/// Preset chips as one even row when they fit, wrapping when the screen is
/// narrow or the text is large — never a label broken mid-word.
class DepositAmountChoices extends StatelessWidget {
  const DepositAmountChoices({super.key, required this.children});
  final List<Widget> children;

  static const _gap = 8.0;

  /// Room a "$100" chip needs at 1x text: display-font label, 12pt padding
  /// each side and a 2pt selected border, with a little to spare.
  static const _minChip = 72.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final each =
          (constraints.maxWidth - _gap * (children.length - 1)) /
          children.length;
      if (children.isEmpty || each < _minChip * scale) {
        return Wrap(spacing: _gap, runSpacing: _gap, children: children);
      }
      return Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            Expanded(child: children[i]),
          ],
        ],
      );
    },
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFE9ECEF),
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

/// How Crossmint takes payment. Shown, not chosen: the checkout offers what
/// the device supports (Apple Pay on iPhone, Google Pay on Android).
class DepositPaymentMethods extends StatelessWidget {
  const DepositPaymentMethods({super.key});

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 6,
    runSpacing: 6,
    children: const [
      _Pill('card-outline', 'Card'),
      _Pill('apple-solid', 'Apple Pay'),
      _Pill('google-solid', 'Google Pay'),
    ],
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.label);
  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: _cardFill,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: _rule),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BasilIcon(icon, size: 14, color: AppColors.textPrimary),
        const SizedBox(width: 5),
        Text(
          label,
          style: callJourneyBody(12).copyWith(color: AppColors.textPrimary),
        ),
      ],
    ),
  );
}

/// Pay → Send → Arrive. The order's own state decides the step; a failure
/// marks the step it failed on.
class DepositSteps extends StatelessWidget {
  const DepositSteps({super.key, required this.state});
  final DepositOrderState state;

  static const _labels = ['Pay', 'Send', 'In your wallet'];

  @override
  Widget build(BuildContext context) {
    final current = depositStep(state);
    final failed =
        state == DepositOrderState.deliveryFailed ||
        state == DepositOrderState.identityFailed ||
        state == DepositOrderState.expired;
    final done = state == DepositOrderState.delivered;
    return Semantics(
      label:
          'Step ${current + 1} of 3: ${_labels[current]}${failed ? ', stopped' : ''}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 18),
                  color:
                      i <= current && !(failed && i == current) ? _good : _rule,
                ),
              ),
            _dot(i, current, failed, done),
          ],
        ],
      ),
    );
  }

  Widget _dot(int i, int current, bool failed, bool done) {
    final complete = i < current || done;
    final active = i == current && !done;
    final (fill, ink, icon) =
        failed && active
            ? (
              AppColors.errorContainer,
              AppColors.onErrorContainer,
              'cross-outline',
            )
            : complete
            ? (_goodFill, _good, 'check-outline')
            : active
            ? (AppColors.primaryContainer, AppColors.primary, null)
            : (_cardFill, AppColors.textTertiary, null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: active ? ink : fill, width: 1.5),
          ),
          child: Center(
            child:
                icon != null
                    ? BasilIcon(icon, size: 14, color: ink)
                    : Text(
                      '${i + 1}',
                      style: callJourneyBody(
                        12,
                      ).copyWith(color: ink, fontWeight: FontWeight.w700),
                    ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _labels[i],
          style: callJourneyBody(11).copyWith(
            color:
                active || complete
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// The other way in: send crypto you already hold to your own address.
/// Collapsed by default so card buyers aren't shown a QR code they don't need.
class DepositReceivePanel extends StatefulWidget {
  const DepositReceivePanel({
    super.key,
    required this.address,
    this.initiallyOpen = false,
  });

  final String address;
  final bool initiallyOpen;

  @override
  State<DepositReceivePanel> createState() => _DepositReceivePanelState();
}

class _DepositReceivePanelState extends State<DepositReceivePanel> {
  late bool _open = widget.initiallyOpen;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.address));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration:
        MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 200),
    curve: Curves.easeOut,
    alignment: Alignment.topCenter,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              key: const ValueKey('deposit-receive-toggle'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const BasilIcon(
                        'exchange-outline',
                        size: 20,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Already have crypto?',
                              style: callJourneyHeading(context, 14),
                            ),
                            Text(
                              'Send USDC or SOL from another wallet or an exchange.',
                              style: callJourneyBody(12),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _open ? .5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const BasilIcon(
                          'arrow-down-outline',
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              key: const ValueKey('deposit-receive-details'),
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _rule),
                      ),
                      child: Semantics(
                        label: 'QR code of your wallet address',
                        image: true,
                        child: QrImageView(
                          data: widget.address,
                          size: 152,
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Your Solana address', style: callJourneyBody(12)),
                  const SizedBox(height: 2),
                  SelectableText(
                    widget.address,
                    key: const ValueKey('deposit-receive-address'),
                    style: callJourneyBody(13).copyWith(
                      color: AppColors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('deposit-receive-copy'),
                      onPressed: _copy,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 44),
                        foregroundColor: AppColors.textPrimary,
                      ),
                      icon: BasilIcon(
                        _copied ? 'check-outline' : 'copy-outline',
                        size: 18,
                        color: _copied ? _good : AppColors.textPrimary,
                      ),
                      label: Text(_copied ? 'Copied' : 'Copy address'),
                    ),
                  ),
                  const CallJourneyNote(
                    'Send USDC or SOL on the Solana network only. Tokens sent on other networks can be lost for good.',
                    icon: 'info-triangle-outline',
                    quiet: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// A one-line headline above a status message, tinted by tone.
class DepositStatusCard extends StatelessWidget {
  const DepositStatusCard({super.key, required this.copy, this.trailing});
  final DepositStateCopy copy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = switch (copy.tone) {
      DepositTone.good => (_goodFill, _good),
      DepositTone.bad => (AppColors.errorContainer, AppColors.onErrorContainer),
      _ => (AppColors.primaryContainer, AppColors.onPrimaryContainer),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const ValueKey('deposit-status-card'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .7),
                shape: BoxShape.circle,
              ),
              child: Center(child: BasilIcon(copy.icon, size: 18, color: ink)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.title,
                    style: callJourneyHeading(context, 15).copyWith(color: ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    copy.message,
                    style: callJourneyBody(
                      13,
                    ).copyWith(color: ink, height: 1.5),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}
