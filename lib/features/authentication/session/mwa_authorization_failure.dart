/// Safe, value-free checkpoints for the existing wallet connection flow.
/// Never include an MWA exception's message: it may contain a session URI or
/// authorization token supplied by a wallet implementation.
enum MwaAuthorizationStep {
  walletDiscovery,
  sessionCreation,
  walletLaunch,
  association,
  walletApproval,
  sessionClose,
  secureSave,
  accountSync,
  profileLoad,
}

String mwaAuthorizationFailureMessage(
  MwaAuthorizationStep step,
) => switch (step) {
  MwaAuthorizationStep.walletDiscovery =>
    'Could not check for a compatible wallet. Please try again.',
  MwaAuthorizationStep.sessionCreation =>
    'Could not start a wallet connection. Please try again.',
  MwaAuthorizationStep.walletLaunch =>
    'Could not open the wallet approval screen. Unlock your wallet and try again.',
  MwaAuthorizationStep.association =>
    'The wallet did not finish connecting. Check the wallet app and try again.',
  MwaAuthorizationStep.walletApproval =>
    'The wallet did not complete authorization. Check its approval screen.',
  MwaAuthorizationStep.sessionClose =>
    'The wallet approved, but its connection did not close safely. Please try again.',
  MwaAuthorizationStep.secureSave =>
    'The wallet approved, but the secure session could not be saved. Unlock your device and try again.',
  MwaAuthorizationStep.accountSync =>
    'The wallet connected, but account sync did not complete. Please try again.',
  MwaAuthorizationStep.profileLoad =>
    'The wallet connected, but profile loading did not complete. Please try again.',
};
