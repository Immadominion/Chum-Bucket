/// Rollout: money calls and the Chumbucket wallet can be on for admin
/// accounts only. The app decides from the server's answer for THIS
/// account (money.status, wallet.status), never from the build flags: a
/// non-admin sees exactly today's app — no money UI, no wallet, no provider
/// session.
library;

import 'dart:typed_data';

import 'package:chumbucket/core/cache/snapshot_store.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/sign_in_methods.dart';
import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart' show CallFeedMode;
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/sign_in_methods_sheet.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_backend.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_controller.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_of.dart';
import 'package:chumbucket/features/money/presentation/money_balance_pill.dart';
import 'package:chumbucket/features/money/presentation/money_pending_card.dart';
import 'package:chumbucket/features/money/presentation/money_winnings_card.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'bff_calls_fixtures.dart' show FakeBffServer, feedPageJson, okResponse;
import 'money_fakes.dart';
import 'money_widgets_test.dart' show Opener, harness, tradable, usePhone;
import 'session_fakes.dart' show kAccessToken, kCanonicalUserId, kSessionBase;

/// Records every provider call; a non-admin must never cause one.
class _RecordingBackend implements ChumbucketWalletBackend {
  final calls = <String>[];

  @override
  Future<void> signIn(String account) async => calls.add('signIn');
  @override
  Future<String?> wallet(String account) async {
    calls.add('wallet');
    return null;
  }

  @override
  Future<String> createWallet(String account) async {
    calls.add('createWallet');
    return signerWallet;
  }

  @override
  Future<Uint8List> signMessage(
    String account,
    String address,
    Uint8List message,
  ) async {
    calls.add('signMessage');
    return Uint8List(64);
  }

  @override
  Future<Uint8List> signTransaction(
    String account,
    String address,
    Uint8List unsigned,
  ) async {
    calls.add('signTransaction');
    return unsigned;
  }

  @override
  Future<void> signOut() async => calls.add('signOut');
}

ChumbucketWalletController _walletFor(
  bool enabled,
  _RecordingBackend backend,
) => ChumbucketWalletController(
  backend: backend,
  bff: SessionBffClient(
    baseUrl: kSessionBase,
    httpClient:
        FakeBffServer(
          (request) => okResponse(
            enabled
                ? {
                  'enabled': true,
                  'account': {
                    'tradingWallet': {
                      'address': signerWallet,
                      'walletType': 'chumbucket',
                    },
                    'chumbucketWallet': signerWallet,
                  },
                }
                : {'enabled': false, 'account': null},
          ),
        ).client,
  ),
  authToken: () async => kAccessToken,
);

void main() {
  group('the Chumbucket wallet follows wallet.status for this account', () {
    test('a non-admin: off, no wallet, no provider session', () async {
      final backend = _RecordingBackend();
      final wallet = _walletFor(false, backend);
      addTearDown(wallet.dispose);
      await wallet.bind(kCanonicalUserId);
      expect(wallet.enabled, isFalse);
      expect(wallet.address, isNull);
      expect(wallet.signer, isNull);
      await expectLater(
        wallet.ensure(),
        throwsA(isA<ChumbucketWalletException>()),
      );
      expect(backend.calls, isEmpty);
    });

    test('an admin: on, with the linked wallet', () async {
      final backend = _RecordingBackend();
      final wallet = _walletFor(true, backend);
      addTearDown(wallet.dispose);
      await wallet.bind(kCanonicalUserId);
      expect(wallet.enabled, isTrue);
      expect(wallet.address, signerWallet);
      expect(backend.calls, isEmpty, reason: 'shown from the server alone');
    });

    testWidgets('every reader sees no wallet for a non-admin', (tester) async {
      final off = _walletFor(false, _RecordingBackend());
      final on = _walletFor(true, _RecordingBackend());
      addTearDown(off.dispose);
      addTearDown(on.dispose);
      await off.bind(kCanonicalUserId);
      await on.bind(kCanonicalUserId);
      ChumbucketWalletController? seen;
      Widget reader(ChumbucketWalletController wallet) =>
          ChangeNotifierProvider<ChumbucketWalletController>.value(
            value: wallet,
            child: Builder(
              builder: (context) {
                seen = chumbucketWalletOf(context, listen: true);
                return const SizedBox();
              },
            ),
          );
      await tester.pumpWidget(reader(off));
      expect(seen, isNull);
      await tester.pumpWidget(reader(on));
      expect(seen, same(on));
    });
  });

  group('money follows money.status for this account', () {
    testWidgets('a non-admin status hides every piece of money UI', (
      tester,
    ) async {
      usePhone(tester);
      final server =
          FakeMoneyServer()
            // What a non-admin gets while MONEY_CALLS_ENABLED=admins.
            ..on('money.status', [moneyStatusJson(enabled: false)])
            ..on('money.wallet', [moneyWalletJson()])
            ..on('money.winnings', [winningsJson()]);
      final money = await boundMoney(server);
      addTearDown(money.dispose);
      final pending = callFeedEntryFromJson(
        pantaEntryJson(
          money: {
            'state': 'PENDING',
            'amountBaseUnits': '5000000',
            'side': 'YES',
            'expiresAt': moneyNow,
          },
        ),
      );
      final theirs = callFeedEntryFromJson(
        pantaEntryJson(id: targetCallId, userId: 'user_ada'),
      );
      await tester.pumpWidget(
        harness(
          money: money,
          deps: fakeMoneyDeps(server),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MoneyBalancePill(),
              const MoneyWinningsCard(),
              MoneyPendingCard(entry: pending, onChanged: () {}),
              Opener(
                open:
                    (context) => showCallComposer(
                      context: context,
                      market: tradable,
                      initialSide: Side.yes,
                    ),
              ),
            ],
          ),
        ),
      );
      expect(find.byKey(const ValueKey('money-balance-pill')), findsNothing);
      expect(find.byKey(const ValueKey('money-winnings-card')), findsNothing);
      expect(find.byKey(const ValueKey('money-pending-card')), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('money-amount-free')), findsNothing);
      expect(
        tester
            .widget<ChumbucketPrimaryButton>(
              find.widgetWithText(ChumbucketPrimaryButton, 'Call YES'),
            )
            .neutral,
        isTrue,
        reason: 'today\'s free call',
      );
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        harness(
          money: money,
          child: Opener(
            open:
                (context) => showCallResponseSheet(
                  context: context,
                  entry: theirs,
                  initialKind: CallResponseKind.back,
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('money-amount-free')), findsNothing);

      // Nothing money-shaped was even read for this account.
      expect(server.count('money.wallet'), 0);
      expect(server.count('money.winnings'), 0);
    });
  });

  group('Sign-in methods follow the linking status for this account', () {
    Future<void> pump(
      WidgetTester tester,
      Future<SignInMethods?> Function() load,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignInMethodsEntry(load: load, child: const Text('Sign-in methods')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('linking off: the whole section is hidden, read-only row too', (
      tester,
    ) async {
      await pump(
        tester,
        () async => const SignInMethods(rows: [], linking: false, fold: false),
      );
      expect(find.text('Sign-in methods'), findsNothing);
    });

    testWidgets('not known is off', (tester) async {
      await pump(tester, () async => throw Exception('offline'));
      expect(find.text('Sign-in methods'), findsNothing);
      await pump(tester, () async => null);
      expect(find.text('Sign-in methods'), findsNothing);
    });

    testWidgets('linking on: the row shows', (tester) async {
      await pump(
        tester,
        () async => const SignInMethods(rows: [], linking: true, fold: false),
      );
      expect(find.text('Sign-in methods'), findsOneWidget);
    });
  });

  group('the owner\'s pending money call in the saved feed', () {
    final withPending = feedPageJson(
      entries: [
        pantaEntryJson(
          money: {
            'state': 'PENDING',
            'amountBaseUnits': '5000000',
            'side': 'YES',
            'expiresAt': moneyNow,
          },
        ),
      ],
      nextCursor: null,
    );

    BffCallsRepository repo(SnapshotStore store) => BffCallsRepository(
      baseUrl: 'https://bff.test.invalid',
      httpClient: FakeBffServer.routes({'calls.feed': withPending}).client,
      authToken: () => 'session-token',
      verbose: false,
      snapshots: store,
    );

    test('another account on this phone: cleared', () async {
      final store = MemorySnapshotStore();
      final calls = CallsProvider(repository: repo(store))..setViewer(viewerId);
      addTearDown(calls.dispose);
      await calls.loadFeed();
      final source = calls.repository as BffCallsRepository;
      // On screen the owner sees it pending; on disk it is never written.
      expect(calls.feed.single.money!.pending, isTrue);
      final saved = await source.savedFeed(mode: CallFeedMode.global);
      expect(saved!.entries.single.money, isNull);

      calls.setViewer('user_other');
      await Future<void>.delayed(Duration.zero);
      expect(store.keys, isEmpty);
      calls.setViewer(viewerId);
      expect(await source.savedFeed(mode: CallFeedMode.global), isNull);
    });

    test('sign-out wipes the saved reads, pending money with them', () async {
      final store = MemorySnapshotStore();
      final source = repo(store)..bindSnapshotViewer(viewerId);
      await source.fetchFeed(mode: CallFeedMode.global, viewerUserId: viewerId);
      expect(store.keys, isNotEmpty);
      await store.clear(); // what AppSignOutEffects does to the device store
      expect(await source.savedFeed(mode: CallFeedMode.global), isNull);

      // And the app's sign-out does wipe the device store.
      final before = SnapshotStore.device.generation;
      AppSignOutEffects().clearSharedState();
      expect(SnapshotStore.device.generation, before + 1);
    });
  });

  test('a saved profile never carries the owner\'s money view either', () {
    final stripped =
        withoutOwnerMoney({
              'calls': [
                pantaEntryJson(
                  money: {
                    'state': 'PENDING',
                    'amountBaseUnits': '5000000',
                    'side': 'YES',
                    'expiresAt': moneyNow,
                  },
                ),
              ],
            })
            as Map;
    final call = (stripped['calls'] as List).single as Map;
    expect(call.containsKey('money'), isFalse);
    expect(call.containsKey('call'), isTrue);
  });
}
