import '../data/deposits_models.dart';

/// What a person reads about one payment, for one state. Plain words; every
/// number comes from the order itself.
class DepositStateCopy {
  const DepositStateCopy(this.title, this.message, this.icon, {this.tone});
  final String title;
  final String message;

  /// A Basil icon slug.
  final String icon;
  final DepositTone? tone;
}

enum DepositTone { waiting, good, bad }

/// Which of the three steps a payment is on: pay, send, arrive.
int depositStep(DepositOrderState state) => switch (state) {
  DepositOrderState.delivering => 1,
  DepositOrderState.delivered => 2,
  DepositOrderState.deliveryFailed => 1,
  _ => 0,
};

DepositStateCopy depositStateCopy(DepositOrder order) {
  final usdc = order.receiveLabel;
  return switch (order.state) {
    DepositOrderState.awaitingPayment => const DepositStateCopy(
      'Waiting for your payment',
      'Finish paying in the secure checkout. Nothing is charged until you confirm there.',
      'card-outline',
      tone: DepositTone.waiting,
    ),
    DepositOrderState.verifyingIdentity => const DepositStateCopy(
      'Quick identity check',
      'Crossmint asks a few questions the first time you buy. It\'s the law for card purchases of crypto. You haven\'t been charged.',
      'shield-outline',
      tone: DepositTone.waiting,
    ),
    DepositOrderState.identityReview => const DepositStateCopy(
      'Crossmint is reviewing your details',
      'This can take a little while. You haven\'t been charged, and we\'ll keep checking.',
      'user-clock-outline',
      tone: DepositTone.waiting,
    ),
    DepositOrderState.identityFailed => const DepositStateCopy(
      'Identity check didn\'t pass',
      'Crossmint couldn\'t verify your identity, so nothing was charged. You can still send USDC from another wallet.',
      'user-block-outline',
      tone: DepositTone.bad,
    ),
    DepositOrderState.awaitingWalletProof => const DepositStateCopy(
      'Confirm this wallet is yours',
      'Above \$1,000 of purchases, Crossmint asks the receiving wallet to sign a short message. Signing a message can\'t move your funds.',
      'lock-outline',
      tone: DepositTone.waiting,
    ),
    DepositOrderState.paymentProcessing => const DepositStateCopy(
      'Payment going through',
      'Hang tight. This usually takes a few seconds.',
      'clock-outline',
      tone: DepositTone.waiting,
    ),
    DepositOrderState.paymentFailed => DepositStateCopy(
      'Payment didn\'t go through',
      order.failureMessage ??
          'Your card or wallet declined it. Try another card or payment method in the checkout. You weren\'t charged.',
      'info-triangle-outline',
      tone: DepositTone.bad,
    ),
    DepositOrderState.delivering => DepositStateCopy(
      'Sending your USDC',
      usdc == null
          ? 'Payment received. Crossmint is sending USDC to your wallet on Solana.'
          : 'Payment received. Crossmint is sending $usdc USDC to your wallet on Solana.',
      'send-outline',
      tone: DepositTone.good,
    ),
    DepositOrderState.delivered => DepositStateCopy(
      'Funds added',
      usdc == null
          ? 'Your USDC is in your wallet.'
          : '$usdc USDC is in your wallet.',
      'check-outline',
      tone: DepositTone.good,
    ),
    DepositOrderState.deliveryFailed => DepositStateCopy(
      'Delivery failed. You\'ll be refunded',
      order.refundedUsd == null
          ? 'Crossmint couldn\'t send the USDC, so it refunds your payment automatically.'
          : 'Crossmint couldn\'t send the USDC and refunded \$${order.refundedUsd} to your card.',
      'refresh-outline',
      tone: DepositTone.bad,
    ),
    DepositOrderState.expired => const DepositStateCopy(
      'This payment timed out',
      'The price expired before you paid. Nothing was charged. Start again for a fresh price.',
      'timer-outline',
      tone: DepositTone.bad,
    ),
  };
}
