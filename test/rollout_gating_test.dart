/// Rollout: money calls and the Chumbucket wallet can be on for admin
/// accounts only. The app decides from the server's answer for THIS
/// account (money.status, wallet.status), never from the build flags: a
/// non-admin sees exactly today's app — no money UI, no wallet, no provider
/// session.
library;

import 'dart:typed_data';

import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
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

import 'bff_calls_fixtures.dart' show FakeBffServer, okResponse;
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

ChumbucketWalletController walletFor(
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
      final wallet = walletFor(false, backend);
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
      final wallet = walletFor(true, backend);
      addTearDown(wallet.dispose);
      await wallet.bind(kCanonicalUserId);
      expect(wallet.enabled, isTrue);
      expect(wallet.address, signerWallet);
      expect(backend.calls, isEmpty, reason: 'shown from the server alone');
    });

    testWidgets('every reader sees no wallet for a non-admin', (tester) async {
      final off = walletFor(false, _RecordingBackend());
      final on = walletFor(true, _RecordingBackend());
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
}
