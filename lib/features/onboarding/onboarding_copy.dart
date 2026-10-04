/// Every onboarding string, in one place (onboarding spec §5).
///
/// Always true: calls are free; trades are real USDC on Panta (Solana mainnet)
/// and can lose money; Panta settles markets; a receipt exists only after
/// Panta settles; usernames can't be changed yet.
///
/// Never: "play money", "practice", "bet", "win money", "earn", "risk-free",
/// "safe", "guaranteed", "odds", "chance", "%" for prices, "airdrop",
/// "jackpot". Never a promise of a notification nobody sends.
/// `test/onboarding_copy_test.dart` holds every string to those rules.
///
/// Strings marked (identity) are fleet/identity's own, reused verbatim.
library;

import 'package:chumbucket/features/calls/data/call_models.dart'
    show ShareCurrency;

abstract final class OnboardingCopy {
  // ── S0 / B2 ──────────────────────────────────────────────────────────────
  static const splashRestoring = 'Restoring your account…';
  static String restoreOk(String? who) =>
      who == null ? 'Welcome back.' : 'Welcome back, $who.';

  // ── W1 Welcome ───────────────────────────────────────────────────────────
  // A no-break space keeps the last two words together: no one-word line.
  static const welcomeTitle = 'Call it before it\u00A0happens.';
  static const welcomeBody =
      'See what people call on real prediction markets. Back them, fade '
      'them, or make your own call.';
  static const welcomeLiveCalls = 'Live calls';
  static const welcomeLiveMarkets = 'Open on Panta now';
  static String welcomeCardCalled(String name, String side) =>
      '$name called $side';
  static String welcomeCardCloses(String relative) =>
      'Closes $relative · Panta';
  static const howCallLead = 'Call it.';
  static const howCallBody = 'Pick YES or NO on a real market. Calls are free.';
  static const howSideLead = 'Back or fade.';
  static const howSideBody =
      'Side with someone’s call, or take the other side.';
  static const howReceiptLead = 'Get the receipt.';
  static const howReceiptBody =
      'When Panta settles the market, your call gets a receipt. Right or '
      'wrong, it stays on your record.';
  static const welcomeMoney =
      'Trading is optional. Trades use real USDC on Panta, and you can lose '
      'what you put in.';
  static const welcomeCta = 'Get started';
  static const welcomeSignIn = 'I already have an account';

  /// W1's one line under the title: the product in eight words.
  static const welcomeTagline =
      'See what people call. Back them or fade\u00A0them.';

  /// W1's line when nobody has called anything yet: the phone shows markets.
  static const welcomeTaglineMarkets =
      'Call real markets before they happen. It’s\u00A0free.';

  /// W1's phone when it has nothing to show yet (API down, or empty).
  static const welcomePhoneEmpty = 'Live calls show up here.';
  static const welcomePhoneOffline =
      'You’re offline. Calls show up when you’re back.';

  /// W1's top-right sign-in for people who already have an account.
  static const welcomeSignInShort = 'Sign in';
  static const welcomeFooter = 'Markets powered by Panta · Solana';
  static const welcomeOffline =
      'You’re offline. Live calls show up when you’re back.';

  // ── T Topics ─────────────────────────────────────────────────────────────
  static const topicsTitle = 'What are you into?';
  static const topicsBody = 'Pick what you want to see first.';
  static String topicChipA11y(String label, int n) =>
      '$label, $n open ${n == 1 ? 'market' : 'markets'}';
  static const topicsNote = 'Change these any time in Settings.';
  static String topicTileCount(int open) =>
      open == 1 ? '1 open market' : '$open open markets';
  static const ctaSkip = 'Skip for now';
  static const ctaContinue = 'Continue';
  static const topicsSheetTitle = 'Topics';
  static const topicsSheetBody =
      'Markets in these topics come first in Markets and in your first-call '
      'picks. Nothing is hidden.';
  static const topicsSheetSave = 'Save topics';
  static const topicsSheetEmpty =
      'No topics have open markets on Panta right now. Try again later.';

  // ── P People / Friends ──────────────────────────────────────────────────
  static const peopleTitle = 'Follow people who call\u00A0it';
  static const peopleBody =
      'Their calls show up first on your Home. You can unfollow any time.';
  static const peopleSection = 'People to follow';
  static const friendsTitle = 'Your friends are here';
  static const friendsBody =
      'These are your friends from Chumbucket. Follow them to see their calls '
      'first.';
  static const friendsSection = 'Your friends';
  static String recordAccuracy(int correct, int decided) =>
      '$correct of $decided called right';
  static String recordBuilding(int decided) =>
      '$decided settled · building a record';
  static String recordOpen(int n) => '$n open ${n == 1 ? 'call' : 'calls'}';
  static const recordNone = 'No calls yet';
  static const follow = 'Follow';
  static const following = 'Following';
  static const followAll = 'Follow all';
  static const unfollowAll = 'Unfollow all';
  static const pendingNote = 'You’ll follow them when you sign in.';
  static String followedAllA11y(int n) => 'Following all $n';
  static const unfollowedAllA11y = 'Following no one';
  static String followingApplied(int n, String? name) =>
      n == 1 && name != null ? 'Following $name.' : 'Following $n people.';
  static String followApplyFailed(int n) =>
      'Couldn’t follow $n. Try again from their profile.';
  static String latestCall(String side, String question) =>
      'Latest call $side on $question';

  // ── C First call ─────────────────────────────────────────────────────────
  static const callTitle = 'Make your first call';
  static const callBody =
      'Pick a side. It’s free, and it goes on your\u00A0record.';
  static const callAnswerHeader = 'Answer a call';
  static const callAnswerHelper =
      'Back takes their side. Fade takes the other side.';
  static const callOwnHeader = 'Or call one yourself';
  static const callSeeAll = 'See all open markets';
  static const callLater = 'I’ll do this later';
  static String callSignedInNote(String? handle) =>
      handle == null
          ? 'You’re signed in. Lock it when you’re ready.'
          : 'Signed in as @$handle. Lock it when you’re ready.';
  static const callStale =
      'Panta hasn’t sent a fresh price for this market. Pick another one, or '
      'try again in a minute.';
  static const callPickAnother = 'Pick another market';
  static const callBack = 'Back';
  static const callFade = 'Fade';
  static String calledSide(String side) => 'called $side';
  static const callLoading = 'Finding markets open on Panta…';

  // ── A1 Sign in / B1 Welcome back ─────────────────────────────────────────
  static const signInTitleCall = 'Sign in to lock your call';
  static String signInTitleFollow(int n, String? name) =>
      n == 1 && name != null
          ? 'Sign in to follow $name'
          : 'Sign in to follow $n people';
  static const signInTitleDefault = 'Sign in to go on record';
  static const signInSubtitle =
      'One Chumbucket account. Use your wallet, Google or X.'; // (identity)
  static const signInDraftNote = 'Saved on this phone until you lock it.';
  static const signInLastUsed = 'Last used';
  static const signInNoWallet =
      'Needs a Solana wallet app, like Phantom, Solflare or Seed Vault Wallet';
  static const signInWalletLine =
      'Your wallet signs a message, not a transaction: it costs nothing and '
      'moves nothing.'; // (identity)
  static const signInConsentLead = 'By continuing, you agree to the ';
  static const signInTerms = 'Terms of Use';
  static const signInConsentJoin = ' and ';
  static const signInPrivacy = 'Privacy Policy';
  static const signInNotNow = 'Not now';
  static const signInWalletOpening = 'Opening your wallet…';
  static const signInWalletChecking = 'Checking your signature…';
  static const signInSettingUp = 'Setting up your account…'; // (identity)
  static const signInWaiting = 'Waiting for your sign-in…'; // (identity)
  static const signInOpeningWalletA11y = 'Opening your wallet app';
  static const signInOpeningBrowserA11y = 'Opening your browser to sign in';
  static const signInErrNoWallet =
      'No Solana wallet app found on this phone. Use Google or X, or install '
      'a wallet.';
  static const signInErrDeclined =
      'Nothing was signed. Try again, or use Google or X.';
  static const signInErrNoAnswer = 'Your wallet didn’t answer. Try again.';
  static const signInErrCancelled = 'Sign-in was cancelled. Nothing changed.';
  static const signInErrNetwork =
      'Couldn’t reach Chumbucket. Check your connection and try again.';
  static const signInOffline = 'You’re offline. Connect to sign in.';
  static const signInLegalPending =
      'The Terms of Use and Privacy Policy are being finalised.';

  static const backTitle = 'Welcome back';
  static const backBody = 'Sign in to pick up where you left off.';
  static const backLook = 'Look around first';
  static const backSessionEnded =
      'Your session on this phone ended. Sign in again. Your calls and '
      'follows are saved to your account.';

  // ── A2 / A2c Username ────────────────────────────────────────────────────
  static const usernameTitle = 'Claim your @username'; // (identity, adds @)
  static const usernameSubtitle =
      'One name for your calls, friends and receipts.'; // (identity)
  static const usernameLabel = 'Username'; // (identity)
  static const nameLabel = 'Name'; // (identity)
  static const nameHelper = 'How you appear next to your calls.'; // (identity)
  static const usernameSuggestedX = 'Suggested from your X account';
  static String usernameSuggestedDomain(String domain) =>
      'Suggested from $domain';
  static const usernameSuggestedGoogle = 'Suggested from your Google name';
  static const usernamePermanent =
      'Pick carefully: usernames can’t be changed yet.';
  static String usernameClaim(String? handle) =>
      handle == null ? 'Claim username' : 'Claim @$handle'; // (identity)
  static const usernameClaiming = 'Claiming…';
  static const usernameDifferentSignIn =
      'Use a different sign-in'; // (identity)
  static const usernameCTitle = 'Pick your @username';
  static String usernameCBody(String? displayName) =>
      displayName == null || displayName.trim().isEmpty
          ? 'Your profile came with you. It just needs a username.'
          : 'Your profile came with you. It just needs a username. Right now '
              'you show up as $displayName.';
  static const usernameCLater = 'Later';
  static const usernameNetwork =
      'Couldn’t reach Chumbucket. Your username isn’t claimed yet. Try again.';

  // ── R You're on record ───────────────────────────────────────────────────
  static const recordTitle = 'You’re on record';
  static const recordTitleAlready = 'You already called this one';
  static String recordBody(String side, String question, String time) =>
      '$side on “$question”. Locked $time. When Panta settles the market, '
      'you’ll get a receipt, right or wrong.';

  /// Under the title when the call itself is shown right below (side,
  /// question, stamped price and lock time are on the card).
  static const recordBodyShort =
      'When Panta settles the market, you’ll get a receipt, right or wrong.';
  static const recordNoPush =
      'Your receipt will show up in Activity (the bell on Home) when Panta '
      'settles it.';
  static const notifyTitle = 'Know when it settles';

  /// Exactly what the server pushes (BACKED, FADED, RESOLVED and the two
  /// rematch kinds in the API's `notifications/copy.ts`), nothing more.
  static const notifyBody =
      'Get a notification when Panta settles your call, when someone backs, '
      'fades or dares you, or when someone you faded calls again. Nothing '
      'else.';
  static const recordPushOn =
      'You’ll get a notification when Panta settles it.';
  static const notifyCta = 'Notify me';
  static const notifyLater = 'Not now';
  static const notifyDenied =
      'No problem. You can turn notifications on in Settings.';
  static const recordDone = 'Done';
  static const recordShare = 'Share your call';
  static String recordLockedAt(
    String price, {
    ShareCurrency currency = ShareCurrency.usdc,
  }) => 'Locked at $price ${currency.perShare}';
  static const recordPriceNotCaptured = 'Price not captured';

  // ── U1 What's new ────────────────────────────────────────────────────────
  static const upgradeTitle = 'Chumbucket is now about calls';
  static const upgradeBody =
      'See what people call on real prediction markets. Back them, fade them, '
      'or make your own call, and build a record.';
  // Said before the wallet is asked anything, so it claims nothing that the
  // signature has yet to do: the profile is kept either way.
  static const upgradeSafe =
      'Your profile and friends are still here. Your old challenges are in '
      'Settings → History.';
  static const upgradeCta = 'Continue with wallet';

  /// When the server is not carrying wallet profiles over (carry off, or no
  /// profile came across): never a path to a second account here.
  static const upgradeClosed =
      'Bringing wallet profiles into the new app isn’t open yet. Your '
      'profile, friends and challenges are unchanged.';

  /// Carry-over is open, but the server found no profile behind this wallet:
  /// the sign-in is undone and nothing is created.
  static const upgradeNoProfile =
      'There’s no Chumbucket profile on this wallet to bring across, so '
      'nothing was created. You can still look around, and sign in from any '
      'call.';
  static const upgradeLater = 'Not now';

  // ── K1 Make Home yours ───────────────────────────────────────────────────
  static const cardTitle = 'Make Home yours';
  static const cardBody = 'Pick topics and people to follow.';
  static const cardCta = 'Set up';
  static const cardLater = 'Not now';

  // ── Pending call offered again on Home ───────────────────────────────────
  static const pendingCallTitle = 'Your call is waiting';
  static String pendingCallBody(String side, String question) =>
      '$side on “$question”. Saved on this phone until you lock it.';
  static const pendingCallCta = 'Review and lock';
  static const pendingCallDiscard = 'Discard';

  // ── Settings ─────────────────────────────────────────────────────────────
  static const settingsTopics = 'Topics';
  static String settingsTopicsValue(int n) =>
      n == 0 ? 'None picked' : '$n picked';
  static const settingsNotifications = 'Notifications';
  static const settingsNotificationsOff =
      'Notifications are off for Chumbucket. Turn them on in Android '
      'Settings.';
  static const settingsNotificationsOpen = 'Open Android Settings';
  static const settingsNotificationsOn = 'On';
  static const settingsNotificationsTapToTurnOn = 'Off. Tap to turn them on.';

  // ── Progress ─────────────────────────────────────────────────────────────
  static String stepOf(int i, int n) => 'Step $i of $n';
  static const back = 'Back';
}
