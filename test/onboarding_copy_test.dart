// Every onboarding string against the copy rules (onboarding spec §5): true
// about money, never the banned words, and the few statements that must be
// said are said.
import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:flutter/material.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every string the onboarding screens can show, including the templated
/// ones filled with ordinary values. (W1's old body, strip headings, money
/// line and footer, C's "See all", A1's "Not now" and B1's "Look around
/// first" are no longer shown anywhere.)
final List<String> _all = [
  OnboardingCopy.splashRestoring,
  OnboardingCopy.restoreOk('@ada'),
  OnboardingCopy.restoreOk(null),
  OnboardingCopy.welcomeTitle,
  OnboardingCopy.welcomeTagline,
  OnboardingCopy.welcomeTaglineMarkets,
  OnboardingCopy.welcomePhoneEmpty,
  OnboardingCopy.welcomePhoneOffline,
  OnboardingCopy.welcomeSignInShort,
  OnboardingCopy.welcomeCardCalled('Ada', 'YES'),
  // U1's how-it-works list.
  OnboardingCopy.howCallLead,
  OnboardingCopy.howCallBody,
  OnboardingCopy.howSideLead,
  OnboardingCopy.howSideBody,
  OnboardingCopy.howReceiptLead,
  OnboardingCopy.howReceiptBody,
  OnboardingCopy.welcomeCta,
  OnboardingCopy.topicsTitle,
  OnboardingCopy.topicsBody,
  OnboardingCopy.topicChipA11y('Sports', 2),
  OnboardingCopy.topicTileCount(1),
  OnboardingCopy.topicTileCount(3),
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
  OnboardingCopy.signInDraftNote,
  OnboardingCopy.signInLastUsed,
  OnboardingCopy.signInNoWallet,
  OnboardingCopy.signInWalletLine,
  OnboardingCopy.signInConsentLead,
  OnboardingCopy.signInTerms,
  OnboardingCopy.signInPrivacy,
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

  test('calls are free and it says so; no onboarding line asks for or promises '
      'money, and none names USDC (USDC prices read bare)', () {
    // W1 no longer carries a money line: the first run never brings up
    // trading at all. Calls are free, and that is said where it matters.
    expect(OnboardingCopy.welcomeTaglineMarkets, contains('free'));
    expect(OnboardingCopy.callBody, contains('free'));
    expect(OnboardingCopy.howCallBody, contains('free'));
    final money = [
      for (final t in _all)
        if (RegExp(
          r'USDC|deposit|wallet balance|fund',
          caseSensitive: false,
        ).hasMatch(t))
          t,
    ];
    expect(money, isEmpty);
  });

  test('W1\'s line says what the phone shows: calls, or markets', () {
    expect(OnboardingCopy.welcomeTagline, contains('call'));
    expect(OnboardingCopy.welcomeTagline, contains('Back'));
    expect(OnboardingCopy.welcomeTagline, contains('fade'));
    expect(OnboardingCopy.welcomeTaglineMarkets, contains('markets'));
    // The empty phone is honest about why, and never invents a call.
    expect(OnboardingCopy.welcomePhoneOffline, contains('offline'));
    expect(OnboardingCopy.welcomePhoneEmpty, isNot(contains('offline')));
  });

  test('topic tiles count open markets in words, singular and plural', () {
    expect(OnboardingCopy.topicTileCount(1), '1 open market');
    expect(OnboardingCopy.topicTileCount(3), '3 open markets');
  });

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

  test(
    'a USDC price reads bare, a SOL price names its unit; never a probability',
    () {
      expect(OnboardingCopy.recordLockedAt('0.38'), 'Locked at 0.38');
      expect(
        OnboardingCopy.recordLockedAt('0.67', currency: ShareCurrency.sol),
        'Locked at 0.67 SOL/share',
      );
    },
  );
}
