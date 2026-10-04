import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/person_finder.dart';
import 'package:chumbucket/shared/screens/home/widgets/add_friend_sheet.dart';
import 'package:chumbucket/shared/services/add_friend_service.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// A holdable Solana address.
const friendWallet = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';

PersonMatch matchOf({
  String id = 'u-irf',
  String name = 'Irfan',
  String handle = 'irfan_calls',
  String? xHandle = 'Irfan',
  String? xAvatarUrl,
  String? avatarArt,
  bool following = false,
  bool isViewer = false,
  PersonMatchedBy matchedBy = PersonMatchedBy.x,
}) => PersonMatch(
  person: PersonCard(
    id: id,
    handle: handle,
    displayName: name,
    record: PublicRecord.empty,
    viewerIsFollowing: following,
  ),
  matchedBy: matchedBy,
  xHandle: xHandle,
  xAvatarUrl: xAvatarUrl,
  avatarArt: avatarArt,
  isViewer: isViewer,
);

PersonLookup found(List<PersonMatch> matches) =>
    PersonLookup(kind: PersonLookupKind.handle, matches: matches);

/// In memory: nothing reaches a server, a wallet or a share sheet.
class FakeFriends implements AddFriendService {
  bool signedIn = true;
  final finds = <String>[];
  final follows = <String>[];
  final shared = <String>[];
  Future<PersonLookup> Function(String query)? answer;
  Future<bool> Function(String personId, bool following)? follow;
  Future<String?> Function(String name)? resolve;

  @override
  bool get isSignedIn => signedIn;

  @override
  String get inviteLink => 'https://chumbucket.fun';

  @override
  Future<PersonLookup> find(String query) async {
    finds.add(query);
    return answer == null ? found([matchOf()]) : answer!(query);
  }

  @override
  Future<bool> setFollowing(String personId, bool following) async {
    follows.add('$personId:$following');
    return follow == null ? following : follow!(personId, following);
  }

  @override
  Future<String?> resolveName(String name) async =>
      resolve == null ? null : resolve!(name);

  @override
  Future<void> share(String text) async => shared.add(text);
}

Future<void> mount(
  WidgetTester tester,
  FakeFriends service, {
  double width = 390,
  double scale = 1,
  double keyboard = 0,
  VoidCallback? onAdded,
  VoidCallback? onSignIn,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder:
          (_, _) => MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder:
                  (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      viewInsets: EdgeInsets.only(bottom: keyboard),
                    ),
                    child: Scaffold(
                      resizeToAvoidBottomInset: false,
                      body: AddFriendSheet(
                        // A fresh sheet per mount, so state never leaks
                        // between scenes in one test.
                        key: UniqueKey(),
                        service: service,
                        onFriendAdded: onAdded ?? () {},
                        onSignIn: onSignIn,
                      ),
                    ),
                  ),
            ),
          ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String value) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('friend-identifier')),
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.enterText(find.byKey(const Key('friend-identifier')), value);
  await tester.pump();
}

/// Scrolls to a primary action, proves it is reachable, and taps it.
Future<void> submit(WidgetTester tester, [String label = 'Find']) async {
  final button = find.widgetWithText(ChumbucketPrimaryButton, label);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    button,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  expect(button.hitTestable(), findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// The same for a text action under the call to action.
Future<void> tapText(WidgetTester tester, String label) async {
  final action = find.widgetWithText(ChumbucketTextAction, label);
  await tester.scrollUntilVisible(
    action,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  expect(action.hitTestable(), findsOneWidget);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'an X handle shows who it is first; adding is a follow, with no wallet '
    'signature',
    (tester) async {
      final service = FakeFriends();
      var added = 0;
      await mount(tester, service, onAdded: () => added++);
      expect(find.text('Add a friend'), findsOneWidget);
      expect(find.textContaining('No wallet signature needed'), findsOneWidget);
      await enter(tester, '@Irfan');
      expect(
        find.text('X handle or Chumbucket @username: @irfan'),
        findsOneWidget,
      );
      await submit(tester);

      // The confirmation card, before anything is written.
      expect(service.finds, ['@irfan']);
      expect(service.follows, isEmpty);
      expect(find.text('Is this them?'), findsOneWidget);
      expect(find.text('Irfan'), findsOneWidget);
      expect(find.text('@irfan_calls on Chumbucket'), findsOneWidget);
      expect(find.text('@Irfan on X'), findsOneWidget);
      expect(find.text('No public calls yet'), findsOneWidget);
      expect(added, 0);
      // The shared frame owns dismissal; no close X anywhere in the sheet.
      expect(find.byIcon(Icons.close), findsNothing);

      await submit(tester, 'Add friend');
      expect(service.follows, ['u-irf:true']);
      expect(added, 1);
      expect(find.text('Friend added'), findsOneWidget);
      expect(find.textContaining('You’re following Irfan'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    },
  );

  testWidgets('an X profile link asks for X accounts only', (tester) async {
    final service = FakeFriends();
    await mount(tester, service);
    await enter(tester, 'https://x.com/Irfan/status/1840000000000000000');
    expect(find.text('X account @irfan'), findsOneWidget);
    await submit(tester);
    expect(service.finds, ['https://x.com/irfan']);
  });

  testWidgets('Not them goes back with what was typed, and adds nobody', (
    tester,
  ) async {
    final service = FakeFriends();
    await mount(tester, service);
    await enter(tester, '@Irfan');
    await submit(tester);
    await tapText(tester, 'Not them');
    expect(find.text('Add a friend'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('friend-identifier')))
          .controller!
          .text,
      '@Irfan',
    );
    expect(service.follows, isEmpty);
  });

  testWidgets('already following says so, and offers Unfollow', (tester) async {
    final service =
        FakeFriends()..answer = (_) async => found([matchOf(following: true)]);
    await mount(tester, service);
    await enter(tester, 'irfan_calls');
    await submit(tester);
    expect(find.textContaining('You already follow Irfan'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(
      find.widgetWithText(ChumbucketPrimaryButton, 'Add friend'),
      findsNothing,
    );
    await tapText(tester, 'Unfollow');
    expect(service.follows, ['u-irf:false']);
    expect(find.text('Unfollowed'), findsOneWidget);
    expect(find.text('You no longer follow Irfan.'), findsOneWidget);
  });

  testWidgets('your own account is never offered to add', (tester) async {
    final service =
        FakeFriends()
          ..answer =
              (_) async => found([
                matchOf(id: 'u-me', name: 'Dominion', isViewer: true),
              ]);
    await mount(tester, service);
    await enter(tester, '@dominion');
    await submit(tester);
    expect(find.text('That’s your own account.'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(
      find.widgetWithText(ChumbucketPrimaryButton, 'Add friend'),
      findsNothing,
    );
    await submit(tester, 'Search again');
    expect(find.text('Add a friend'), findsOneWidget);
  });

  testWidgets(
    'an X handle nobody here has: say so, and invite — never a pending friend',
    (tester) async {
      final service =
          FakeFriends()
            ..answer =
                (_) async => const PersonLookup(
                  kind: PersonLookupKind.handle,
                  handle: 'vitalik',
                  matches: [],
                  notOnChumbucket: NotOnChumbucket(xHandle: 'vitalik'),
                );
      await mount(tester, service);
      await enter(tester, '@vitalik');
      await submit(tester);
      expect(find.text('Not here yet'), findsOneWidget);
      expect(find.text('Not on Chumbucket yet'), findsOneWidget);
      expect(find.text('@vitalik'), findsOneWidget);
      expect(find.text('On X'), findsOneWidget);
      // No picture was found: initials, not a stand-in.
      expect(find.text('V'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await submit(tester, 'Invite @vitalik');
      expect(service.shared.single, contains('@vitalik'));
      expect(service.shared.single, contains('https://chumbucket.fun'));
      expect(service.follows, isEmpty);
      await tapText(tester, 'Search again');
      expect(find.text('Add a friend'), findsOneWidget);
    },
  );

  testWidgets('their public X picture shows when the server found one', (
    tester,
  ) async {
    const pic = 'https://pbs.twimg.com/profile_images/9/v_400x400.jpg';
    final service =
        FakeFriends()
          ..answer =
              (_) async => const PersonLookup(
                kind: PersonLookupKind.x,
                matches: [],
                notOnChumbucket: NotOnChumbucket(
                  xHandle: 'vitalik',
                  xAvatarUrl: pic,
                ),
              );
    await mount(tester, service);
    await enter(tester, 'x.com/vitalik');
    await submit(tester);
    expect(find.byKey(const ValueKey('friend-picture-$pic')), findsOneWidget);
  });

  testWidgets('a wallet nobody uses says so and offers an invite', (
    tester,
  ) async {
    final service =
        FakeFriends()
          ..answer =
              (_) async => const PersonLookup(
                kind: PersonLookupKind.wallet,
                matches: [],
              );
    await mount(tester, service);
    await enter(tester, friendWallet);
    expect(find.text('Solana wallet 9WzD…AWWM'), findsOneWidget);
    await submit(tester);
    expect(service.finds, [friendWallet]);
    expect(find.text('No one found'), findsOneWidget);
    expect(
      find.textContaining('No one on Chumbucket uses that wallet yet'),
      findsOneWidget,
    );
    await submit(tester, 'Invite a friend');
    expect(service.shared.single, startsWith('Hey, I’m making calls'));
  });

  testWidgets(
    'a .skr name is resolved on the phone, then its wallet looked up',
    (tester) async {
      final service = FakeFriends()..resolve = (_) async => friendWallet;
      await mount(tester, service);
      await enter(tester, 'Alice.skr');
      expect(find.text('Wallet name alice.skr'), findsOneWidget);
      await submit(tester);
      expect(service.finds, [friendWallet]);

      final unknown = FakeFriends()..resolve = (_) async => null;
      await mount(tester, unknown);
      await enter(tester, 'ghost.skr');
      await submit(tester);
      expect(unknown.finds, isEmpty);
      expect(
        find.textContaining('We couldn’t find a wallet for ghost.skr'),
        findsOneWidget,
      );
    },
  );

  testWidgets('several matches: add the one you know, or none of these', (
    tester,
  ) async {
    Future<PersonLookup> two(String _) async => found([
      matchOf(),
      matchOf(
        id: 'u-name',
        name: 'Another Irfan',
        handle: 'irfan',
        xHandle: null,
        matchedBy: PersonMatchedBy.username,
      ),
    ]);
    final service = FakeFriends()..answer = two;
    await mount(tester, service);
    await enter(tester, '@irfan');
    await submit(tester);
    expect(find.text('Which one is them?'), findsOneWidget);
    expect(find.textContaining('2 people match @irfan'), findsOneWidget);
    await submit(tester, 'Add Another Irfan');
    expect(service.follows, ['u-name:true']);
    expect(
      find.textContaining('You’re following Another Irfan'),
      findsOneWidget,
    );

    final again = FakeFriends()..answer = two;
    await mount(tester, again);
    await enter(tester, '@irfan');
    await submit(tester);
    await tapText(tester, 'None of these');
    expect(again.follows, isEmpty);
    expect(find.text('Add a friend'), findsOneWidget);
  });

  testWidgets('two matches with one name: each button names its handle', (
    tester,
  ) async {
    final service =
        FakeFriends()
          ..answer =
              (_) async => found([
                matchOf(),
                matchOf(
                  id: 'u-name',
                  handle: 'irfan',
                  xHandle: null,
                  matchedBy: PersonMatchedBy.username,
                ),
              ]);
    await mount(tester, service);
    await enter(tester, '@irfan');
    await submit(tester);
    // Never two buttons that both say "Add Irfan".
    expect(
      find.widgetWithText(ChumbucketPrimaryButton, 'Add Irfan'),
      findsNothing,
    );
    expect(
      find.widgetWithText(ChumbucketPrimaryButton, 'Add @irfan_calls'),
      findsOneWidget,
    );
    await submit(tester, 'Add @irfan');
    expect(service.follows, ['u-name:true']);
  });

  testWidgets('a refusal is shown as the server words it, and can be retried', (
    tester,
  ) async {
    const refusal =
        'You’re following and unfollowing very quickly. Try again in a minute.';
    var refuse = true;
    final service =
        FakeFriends()
          ..follow = (_, following) async {
            if (refuse) throw const CallsRejectedException(refusal);
            return following;
          };
    await mount(tester, service);
    await enter(tester, '@irfan');
    await submit(tester);
    await submit(tester, 'Add friend');
    expect(find.text(refusal), findsOneWidget);
    expect(find.text('Is this them?'), findsOneWidget);
    refuse = false;
    await submit(tester, 'Add friend');
    expect(service.follows, ['u-irf:true', 'u-irf:true']);
    expect(find.text('Friend added'), findsOneWidget);
  });

  testWidgets(
    'a lapsed session asks to sign in, and a failed lookup says why',
    (tester) async {
      var signIns = 0;
      final service =
          FakeFriends()
            ..answer = (_) async => throw const CallsSignedOutException();
      await mount(tester, service, onSignIn: () => signIns++);
      await enter(tester, '@irfan');
      await submit(tester);
      expect(
        find.text('Sign in to your Chumbucket account to add friends.'),
        findsOneWidget,
      );
      await tapText(tester, 'Sign in');
      expect(signIns, 1);

      final offline =
          FakeFriends()
            ..answer = (_) async => throw const CallsOfflineException();
      await mount(tester, offline);
      await enter(tester, '@irfan');
      await submit(tester);
      expect(find.textContaining('You’re offline'), findsOneWidget);

      final old =
          FakeFriends()
            ..answer = (_) async => throw const PersonFinderUnavailable();
      await mount(tester, old);
      await enter(tester, '@irfan');
      await submit(tester);
      expect(
        find.textContaining('isn’t available on the server yet'),
        findsOneWidget,
      );
    },
  );

  testWidgets('signing in from the sheet closes it before sign-in opens', (
    tester,
  ) async {
    var signIns = 0;
    final service =
        FakeFriends()
          ..answer = (_) async => throw const CallsSignedOutException();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, _) => MaterialApp(
              theme: AppTheme.lightTheme,
              home: Builder(
                builder:
                    (context) => Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed:
                              () => showChumbucketWavySheet<void>(
                                context: context,
                                builder:
                                    (_) => AddFriendSheet(
                                      service: service,
                                      onFriendAdded: () {},
                                      onSignIn: () => signIns++,
                                    ),
                              ),
                          child: const Text('open'),
                        ),
                      ),
                    ),
              ),
            ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await enter(tester, '@irfan');
    await submit(tester);
    await tapText(tester, 'Sign in');
    expect(find.byType(AddFriendSheet), findsNothing);
    expect(signIns, 1);
  });

  testWidgets('something that is none of these cannot be searched', (
    tester,
  ) async {
    final service = FakeFriends();
    await mount(tester, service);
    await enter(tester, 'hello world');
    final button = tester.widget<ChumbucketPrimaryButton>(
      find.widgetWithText(ChumbucketPrimaryButton, 'Find'),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('Enter an X handle'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(service.finds, isEmpty);
  });

  testWidgets('a screen reader hears the card as one person', (tester) async {
    final semantics = tester.ensureSemantics();
    final service = FakeFriends();
    await mount(tester, service);
    await enter(tester, '@irfan');
    // The hint changes on every keystroke, so it is not a live region that
    // would talk over someone typing.
    expect(
      tester
          .getSemantics(find.byKey(const Key('friend-identifier-hint')))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isFalse,
    );
    await submit(tester);
    expect(
      find.bySemanticsLabel(
        'Irfan, @irfan_calls on Chumbucket, @Irfan on X, No public calls yet',
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.widgetWithText(ChumbucketPrimaryButton, 'Add friend'),
      ),
      matchesSemantics(
        label: 'Add friend',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    // A person with no display name is named by their @username once, not
    // twice.
    final unnamed =
        FakeFriends()
          ..answer =
              (_) async =>
                  found([matchOf(name: 'irfan_calls', handle: 'irfan_calls')]);
    await mount(tester, unnamed);
    await enter(tester, '@irfan');
    await submit(tester);
    expect(
      find.bySemanticsLabel('@irfan_calls, @Irfan on X, No public calls yet'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets(
    'pictures: the chosen avatar without an X photo; initials with nothing',
    (tester) async {
      final service =
          FakeFriends()
            ..answer =
                (_) async => found([
                  matchOf(
                    xHandle: null,
                    avatarArt: 'assets/images/ai_gen/profile_images/3.png',
                  ),
                ]);
      await mount(tester, service);
      await enter(tester, 'irfan_calls');
      await submit(tester);
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        ((image.image as ResizeImage).imageProvider as AssetImage).assetName,
        'assets/images/ai_gen/profile_images/3.png',
      );

      final bare =
          FakeFriends()..answer = (_) async => found([matchOf(xHandle: null)]);
      await mount(tester, bare);
      await enter(tester, 'irfan_calls');
      await submit(tester);
      expect(find.byType(Image), findsNothing);
      expect(find.text('I'), findsOneWidget);
    },
  );

  test('a name that only repeats the @username is shown as @username', () {
    // The server's fallback when there is no name: displayName = handle.
    expect(
      friendName(matchOf(name: 'irfan_calls', handle: 'irfan_calls')),
      '@irfan_calls',
    );
    // A name someone chose stays, even when it reads like their handle.
    expect(friendName(matchOf(name: 'Irfan', handle: 'irfan')), 'Irfan');
    expect(friendName(matchOf(name: 'Ada Lovelace')), 'Ada Lovelace');
  });

  test('initials come from the name the card shows, never a placeholder', () {
    // No name yet: the server's fallback is the placeholder handle.
    expect(
      friendInitials(
        matchOf(
          name: 'user-1a2b3c4d',
          handle: 'user-1a2b3c4d',
          xHandle: 'ada_x',
        ),
      ),
      'a',
    );
    expect(
      friendInitials(
        matchOf(name: 'user-1a2b3c4d', handle: 'ada_calls', xHandle: null),
      ),
      'a',
    );
    expect(friendInitials(matchOf(name: 'Ada Lovelace')), 'AL');
    expect(
      friendInitials(
        matchOf(name: 'user-1a2b3c4d', handle: 'user-1a2b3c4d', xHandle: null),
      ),
      '?',
    );
  });

  testWidgets(
    'pictures: an X photo that will not load falls back to the next real one',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: FriendPicture(
              sources: [
                'https://pbs.twimg.com/profile_images/1/gone_400x400.jpg',
                'assets/images/ai_gen/profile_images/2.png',
              ],
              initials: 'I',
            ),
          ),
        ),
      );
      // Tests have no network: the X photo fails, as a removed one would.
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      final providers =
          tester
              .widgetList<Image>(find.byType(Image))
              .map((i) => (i.image as ResizeImage).imageProvider)
              .toList();
      expect(
        providers.whereType<AssetImage>().single.assetName,
        'assets/images/ai_gen/profile_images/2.png',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320dp, 2x text and a keyboard keep the card and its actions reachable',
    (tester) async {
      final service = FakeFriends();
      await mount(tester, service, width: 320, scale: 2, keyboard: 300);
      await enter(tester, '@irfan');
      await submit(tester);
      await tester.scrollUntilVisible(
        find.byType(FriendPicture),
        -100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      // At large text the picture stacks above the words.
      final picture = tester.getRect(find.byType(FriendPicture));
      final name = tester.getRect(find.text('Irfan'));
      expect(name.top, greaterThan(picture.bottom));
      await submit(tester, 'Add friend');
      expect(service.follows, ['u-irf:true']);
      expect(find.text('Friend added'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
