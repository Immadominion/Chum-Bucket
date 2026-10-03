// Every onboarding string against the copy rules (onboarding spec §5): true
// about money, never the banned words, and the few statements that must be
// said are said.
import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every string the onboarding screens can show, including the templated
/// ones filled with ordinary values.
final List<String> _all = [
  OnboardingCopy.splashRestoring,
  OnboardingCopy.restoreOk('@ada'),
  OnboardingCopy.restoreOk(null),
  OnboardingCopy.welcomeTitle,
  OnboardingCopy.welcomeBody,
  OnboardingCopy.welcomeLiveCalls,
  OnboardingCopy.welcomeLiveMarkets,
  OnboardingCopy.welcomeCardCalled('Ada', 'YES'),
  OnboardingCopy.welcomeCardCloses('in 2 days'),
  OnboardingCopy.howCallLead,
  OnboardingCopy.howCallBody,
  OnboardingCopy.howSideLead,
  OnboardingCopy.howSideBody,
  OnboardingCopy.howReceiptLead,
  OnboardingCopy.howReceiptBody,
  OnboardingCopy.welcomeMoney,
  OnboardingCopy.welcomeCta,
  OnboardingCopy.welcomeSignIn,
  OnboardingCopy.welcomeFooter,
  OnboardingCopy.welcomeOffline,
  OnboardingCopy.topicsTitle,
  OnboardingCopy.topicsBody,
  OnboardingCopy.topicChipA11y('Sports', 2),
  OnboardingCopy.topicsNote,
  OnboardingCopy.ctaSkip,
  OnboardingCopy.ctaContinue,
  OnboardingCopy.topicsSheetTitle,
  OnboardingCopy.topicsSheetBody,
  OnboardingCopy.topicsSheetSave,
  OnboardingCopy.topicsSheetEmpty,
  OnboardingCopy.peopleTitle,
  OnboardingCopy.peopleBody,
  OnboardingCopy.peopleSection,
  OnboardingCopy.friendsTitle,
  OnboardingCopy.friendsBody,
  OnboardingCopy.friendsSection,
  OnboardingCopy.recordAccuracy(8, 10),
  OnboardingCopy.recordBuilding(3),
  OnboardingCopy.recordOpen(2),
  OnboardingCopy.recordNone,
  OnboardingCopy.follow,
  OnboardingCopy.following,
  OnboardingCopy.followAll,
  OnboardingCopy.unfollowAll,
  OnboardingCopy.pendingNote,
  OnboardingCopy.followedAllA11y(3),
  OnboardingCopy.unfollowedAllA11y,
  OnboardingCopy.followingApplied(2, null),
  OnboardingCopy.followingApplied(1, 'Ada'),
  OnboardingCopy.followApplyFailed(1),
  OnboardingCopy.latestCall('YES', 'Will it?'),
  OnboardingCopy.callTitle,
  OnboardingCopy.callBody,
  OnboardingCopy.callAnswerHeader,
  OnboardingCopy.callAnswerHelper,
  OnboardingCopy.callOwnHeader,
  OnboardingCopy.callSeeAll,
  OnboardingCopy.callLater,
  OnboardingCopy.callSignedInNote('ada'),
  OnboardingCopy.callSignedInNote(null),
  OnboardingCopy.callStale,
  OnboardingCopy.callPickAnother,
  OnboardingCopy.callBack,
  OnboardingCopy.callFade,
  OnboardingCopy.calledSide('NO'),
  OnboardingCopy.callLoading,
  OnboardingCopy.signInTitleCall,
  OnboardingCopy.signInTitleFollow(3, null),
  OnboardingCopy.signInTitleFollow(1, 'Ada'),
  OnboardingCopy.signInTitleDefault,
  OnboardingCopy.signInSubtitle,
  OnboardingCopy.signInDraftNote,
  OnboardingCopy.signInLastUsed,
  OnboardingCopy.signInNoWallet,
  OnboardingCopy.signInWalletLine,
  OnboardingCopy.signInConsentLead,
  OnboardingCopy.signInTerms,
  OnboardingCopy.signInPrivacy,
  OnboardingCopy.signInNotNow,
  OnboardingCopy.signInWalletOpening,
  OnboardingCopy.signInWalletChecking,
  OnboardingCopy.signInSettingUp,
  OnboardingCopy.signInWaiting,
  OnboardingCopy.signInOpeningWalletA11y,
  OnboardingCopy.signInOpeningBrowserA11y,
  OnboardingCopy.signInErrNoWallet,
  OnboardingCopy.signInErrDeclined,
  OnboardingCopy.signInErrNoAnswer,
  OnboardingCopy.signInErrCancelled,
  OnboardingCopy.signInErrNetwork,
  OnboardingCopy.signInOffline,
  OnboardingCopy.backTitle,
  OnboardingCopy.backBody,
  OnboardingCopy.backLook,
  OnboardingCopy.backSessionEnded,
  OnboardingCopy.usernameTitle,
  OnboardingCopy.usernameSubtitle,
  OnboardingCopy.usernameLabel,
  OnboardingCopy.nameLabel,
  OnboardingCopy.nameHelper,
  OnboardingCopy.usernameSuggestedX,
  OnboardingCopy.usernameSuggestedDomain('ada.sol'),
  OnboardingCopy.usernameSuggestedGoogle,
  OnboardingCopy.usernamePermanent,
  OnboardingCopy.usernameClaim('ada'),
  OnboardingCopy.usernameClaim(null),
  OnboardingCopy.usernameClaiming,
  OnboardingCopy.usernameDifferentSignIn,
  OnboardingCopy.usernameCTitle,
  OnboardingCopy.usernameCBody('Ada'),
  OnboardingCopy.usernameCBody(null),
  OnboardingCopy.usernameCLater,
  OnboardingCopy.usernameNetwork,
  OnboardingCopy.recordTitle,
  OnboardingCopy.recordTitleAlready,
  OnboardingCopy.recordBody('YES', 'Will it?', '2 Oct, 12:00 UTC'),
  OnboardingCopy.recordBodyShort,
  OnboardingCopy.recordNoPush,
  OnboardingCopy.recordPushOn,
  OnboardingCopy.notifyTitle,
  OnboardingCopy.notifyBody,
  OnboardingCopy.notifyCta,
  OnboardingCopy.notifyLater,
  OnboardingCopy.notifyDenied,
  OnboardingCopy.recordDone,
  OnboardingCopy.recordShare,
  OnboardingCopy.recordLockedAt('0.50'),
  OnboardingCopy.recordPriceNotCaptured,
  OnboardingCopy.upgradeTitle,
  OnboardingCopy.upgradeBody,
  OnboardingCopy.upgradeSafe,
  OnboardingCopy.upgradeCta,
  OnboardingCopy.upgradeLater,
  OnboardingCopy.upgradeClosed,
  OnboardingCopy.upgradeNoProfile,
  OnboardingCopy.cardTitle,
  OnboardingCopy.cardBody,
  OnboardingCopy.cardCta,
  OnboardingCopy.cardLater,
  OnboardingCopy.pendingCallTitle,
  OnboardingCopy.pendingCallBody('YES', 'Will it?'),
  OnboardingCopy.pendingCallCta,
  OnboardingCopy.pendingCallDiscard,
  OnboardingCopy.settingsTopics,
  OnboardingCopy.settingsTopicsValue(0),
  OnboardingCopy.settingsTopicsValue(2),
  OnboardingCopy.settingsNotifications,
  OnboardingCopy.settingsNotificationsOff,
  OnboardingCopy.settingsNotificationsOpen,
  OnboardingCopy.settingsNotificationsOn,
  OnboardingCopy.settingsNotificationsTapToTurnOn,
  OnboardingCopy.stepOf(1, 4),
  OnboardingCopy.back,
];

/// §5 "Never". Word-bounded so "Panta settles" does not trip "settle" rules
/// and "safely" would still be caught by "safe".
final Map<String, RegExp> _banned = {
  'play money': RegExp(r'play money', caseSensitive: false),
  'practice': RegExp(r'\bpractice\b', caseSensitive: false),
  'bet': RegExp(r'\bbet(s|ting)?\b', caseSensitive: false),
  'win money': RegExp(r'win money', caseSensitive: false),
  'earn': RegExp(r'\bearn', caseSensitive: false),
  'risk-free': RegExp(r'risk[- ]free', caseSensitive: false),
  'safe': RegExp(r'\bsafe', caseSensitive: false),
  'guaranteed': RegExp(r'guarantee', caseSensitive: false),
  'odds': RegExp(r'\bodds\b', caseSensitive: false),
  'chance': RegExp(r'\bchance', caseSensitive: false),
  '%': RegExp(r'%'),
  'airdrop': RegExp(r'airdrop', caseSensitive: false),
  'jackpot': RegExp(r'jackpot', caseSensitive: false),
  // Chumbucket never holds anyone's money.
  'we hold': RegExp(
    r'\b(we|chumbucket) (hold|keep)s? (your )?(funds|money)',
    caseSensitive: false,
  ),
  // The old escrow/football product.
  'escrow': RegExp(r'escrow|football|match ends', caseSensitive: false),
};

void main() {
  test('no onboarding string says anything the rules forbid', () {
    for (final text in _all) {
      for (final MapEntry(key: rule, value: pattern) in _banned.entries) {
        expect(
          pattern.hasMatch(text),
          isFalse,
          reason: '"$text" breaks "$rule"',
        );
      }
    }
  });

  test('the explain-first sheet after a social action keeps the same rules', () {
    // PushRationaleSheet's words, as rendered.
    const rationale = [
      'Know when it lands',
      'Only about your calls and the people you’ve faced.',
      'We’ll tell you when someone backs or fades your call, when the market '
          'resolves, when someone wants a rematch, and when someone you faded '
          'makes a new call.',
    ];
    for (final text in rationale) {
      for (final pattern in _banned.values) {
        expect(pattern.hasMatch(text), isFalse, reason: text);
      }
    }
    expect(const PushRationaleSheet(), isA<StatelessWidget>());
  });

  test(
    'money is said once, plainly: real USDC on Panta, and you can lose it',
    () {
      expect(OnboardingCopy.welcomeMoney, contains('real USDC'));
      expect(OnboardingCopy.welcomeMoney, contains('Panta'));
      expect(OnboardingCopy.welcomeMoney, contains('lose'));
      expect(OnboardingCopy.welcomeMoney, contains('optional'));
      // Calls themselves are free, and it says so where you make one.
      expect(OnboardingCopy.howCallBody, contains('free'));
      expect(OnboardingCopy.callBody, contains('free'));
      // Only the money line and the venue line name money or the chain.
      final money = [
        for (final t in _all)
          if (RegExp(
            r'USDC|deposit|wallet balance|fund',
            caseSensitive: false,
          ).hasMatch(t))
            t,
      ];
      expect(money, [
        OnboardingCopy.welcomeMoney,
        OnboardingCopy.recordLockedAt('0.50'),
      ]);
    },
  );

  test('receipts come only from Panta settling, right or wrong', () {
    expect(OnboardingCopy.howReceiptBody, contains('Panta settles'));
    expect(OnboardingCopy.howReceiptBody, contains('Right or wrong'));
    expect(OnboardingCopy.recordBodyShort, contains('right or wrong'));
  });

  test('usernames are said to be permanent, because rename is not built', () {
    expect(OnboardingCopy.usernamePermanent, contains('can’t be changed'));
  });

  test('a notification is promised only for what the server pushes', () {
    // BACKED, FADED, RESOLVED, REMATCH (a dare, a faded rival again).
    final body = OnboardingCopy.notifyBody;
    for (final kind in ['settles', 'backs', 'fades', 'dares', 'faded']) {
      expect(body, contains(kind));
    }
    expect(body, endsWith('Nothing else.'));
    // Without push, the receipt is promised in Activity, not as a push.
    expect(OnboardingCopy.recordNoPush, contains('Activity'));
    expect(OnboardingCopy.recordNoPush, isNot(contains('notif')));
  });

  test('prices are USDC per share, never a probability', () {
    expect(OnboardingCopy.recordLockedAt('0.38'), 'Locked at 0.38 USDC/share');
  });
}
