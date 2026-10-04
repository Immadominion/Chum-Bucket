// The legacy Friends → Challenge SOL escrow is retired (owner decision): the
// escrow program D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1 is live on
// mainnet, so a new challenge would lock real SOL behind a witness rather than
// a venue.
//
//   - Nothing in lib/ can create one: no screen, no instruction builder, no
//     PDA derivation.
//   - Earlier ones stay in Settings → History, and one that still holds SOL
//     stays settleable by its witness (the only action the legacy flow ever
//     offered), including after its own deadline, which the program ignores.
//   - Friends and People offer the call-based actions instead.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:solana/dto.dart' show Account, BinaryAccountData;
import 'package:solana/solana.dart' show Ed25519HDPublicKey;

import 'package:chumbucket/core/config/app_config.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/trust/presentation/legacy_history_screen.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenges_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/escrow_settle.dart';
import 'package:chumbucket/shared/screens/home/widgets/friend_actions.dart';
import 'package:chumbucket/shared/screens/home/widgets/resolve_challenge_sheet.dart';
import 'package:chumbucket/shared/screens/home/widgets/view_more_friends_sheet.dart';
import 'package:chumbucket/shared/utils/challenge_status_utils.dart';

import 'ui_people_layout_continuity_test.dart'
    show ConnectedAuth, ConnectedWallet, ExistingProfile, walletFixture;
import 'ui_people_layout_profile_test.dart' show PeopleRepository;

const _program = 'D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1';
const _challenger = 'So11111111111111111111111111111111111111112';

Challenge _escrow(
  String id,
  ChallengeStatus status, {
  String witness = walletFixture,
  String initiator = _challenger,
  double amount = .1,
  double winner = .0975,
}) => Challenge(
  id: id,
  creatorId: initiator,
  member1Address: initiator,
  witnessAddress: witness,
  title: 'Run 5k every day',
  description: 'Run 5k every day',
  amount: amount,
  platformFee: amount - winner,
  winnerAmount: winner,
  createdAt: DateTime.utc(2025, 7, 1),
  // Noon UTC: the same calendar day in every test machine's time zone.
  expiresAt: DateTime.utc(2025, 8, 1, 12),
  status: status,
  escrowAddress: 'Escrow1111111111111111111111111111111111111',
);

/// Mounts [child] as the app's home. [above] wraps the whole app, the way
/// main.dart provides app-wide state above the navigator.
Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  Widget Function(Widget app)? above,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, _) => MaterialApp(home: child),
  );
  await tester.pumpWidget(above?.call(app) ?? app);
  await tester.pumpAndSettle();
}

class _Account implements AccountApi {
  @override
  Future<AccountProfile> me() async =>
      const AccountProfile(userId: 'user_ada', displayName: 'Ada Okafor');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No wallet connected: a Google or X account.
class _NoWallet extends MwaAuthProvider {
  @override
  String? get walletAddress => null;
}

Iterable<File> _libSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppConfig.initialize();
  });

  group('nothing in the app can create a SOL escrow challenge', () {
    test('no source builds the create instruction or opens a create flow', () {
      final forbidden = <String, RegExp>{
        'the create screen': RegExp(r'\bCreateChallengeScreen\b'),
        'the create transaction': RegExp(r'buildCreateChallengeTransaction'),
        'a createChallenge call or method': RegExp(r'\bcreateChallenge\s*\('),
        'the create discriminator': RegExp(r'createChallenge\s*=\s*0x01'),
        'the escrow PDA seed': RegExp(r"'CHALLENGE'\s*\.codeUnits"),
        'the old "Challenge a new friend" label': RegExp(
          r"'Challenge a new friend'",
        ),
      };
      final offenders = <String>[
        for (final file in _libSources())
          for (final entry in forbidden.entries)
            if (entry.value.hasMatch(file.readAsStringSync()))
              '${file.path}: ${entry.key}',
      ];
      expect(offenders, isEmpty);
    });

    test('the escrow program id lives only in read and settle code', () {
      final holders = [
        for (final file in _libSources())
          if (file.readAsStringSync().contains(_program))
            file.path.split('/').last,
      ];
      expect(
        holders.toSet(),
        everyElement(
          isIn({
            'mwa_wallet_provider.dart', // resolve, cancel, escrowIsOpen
            'pinocchio_escrow_service.dart', // read-only account parser
            'blockchain_sync_service.dart', // read-only, unwired
          }),
        ),
      );
    });

    test('the provider builds only resolve (0x02) and cancel (0x03)', () {
      expect(PinocchioInstructions.resolveChallenge, 0x02);
      expect(PinocchioInstructions.cancelChallenge, 0x03);
    });
  });

  group('an earlier escrow that still holds SOL stays settleable', () {
    test('open means anything not settled, past due included', () async {
      final state = ChallengeStateProvider(
        loadChallenges:
            (_) async => [
              for (final status in ChallengeStatus.values)
                _escrow(status.name, status),
            ],
      );
      addTearDown(state.dispose);
      await state.initialize(walletFixture);
      expect(state.openChallenges.map((c) => c.status).toSet(), {
        ChallengeStatus.pending,
        ChallengeStatus.active,
        // Older open states: the chain is asked before any wallet opens.
        ChallengeStatus.accepted,
        ChallengeStatus.funded,
        ChallengeStatus.expired,
      });
      for (final status in [
        'pending',
        'active',
        'accepted',
        'funded',
        'expired',
      ]) {
        expect(ChallengeStatusUtils.isResolvable(status), isTrue);
      }
      for (final status in ['completed', 'failed', 'cancelled']) {
        expect(ChallengeStatusUtils.isResolvable(status), isFalse);
      }
    });

    test('the payout is the stake less the program fee', () {
      expect(escrowPayoutText({'winner_amount_sol': .0975}), '0.0975 SOL');
      // No stored payout: 2.5% of the stake, at most 0.1 SOL.
      expect(escrowPayoutText({'amount': 1}), '0.975 SOL');
      expect(escrowPayoutText({'amount': 10}), '9.9 SOL');
      expect(escrowPayoutText(const {}), 'the SOL');
    });

    test('the escrow check reads Solana: open only while the program owns '
        'the account', () async {
      Account owned(String owner) => Account(
        lamports: 100000000,
        owner: owner,
        data: null,
        executable: false,
        rentEpoch: BigInt.zero,
      );
      Future<bool?> check(Future<Account?> Function(String) read) async {
        final wallet = MwaWalletProvider(readEscrowAccount: read);
        addTearDown(wallet.dispose);
        return wallet.escrowIsOpen(
          'Escrow1111111111111111111111111111111111111',
        );
      }

      expect(await check((_) async => owned(_program)), isTrue);
      // Resolve and cancel close the account.
      expect(await check((_) async => null), isFalse);
      expect(
        await check((_) async => owned('11111111111111111111111111111111')),
        isFalse,
      );
      // The network could not say: the wallet's own checks still apply.
      expect(await check((_) async => throw Exception('rpc down')), isNull);
    });

    // The program's own layout (chumbucket-pinocchio src/lib.rs
    // process_create_challenge), as the mainnet escrows hold it.
    Account escrowAccount({
      String initiator = _challenger,
      String witness = walletFixture,
      int stake = 50000000,
      int resolved = 0,
      String owner = _program,
    }) {
      final fee = stake * 250 ~/ 10000;
      final bytes = Uint8List(146);
      bytes.setAll(0, 'CHALL001'.codeUnits);
      bytes.setAll(8, Ed25519HDPublicKey.fromBase58(initiator).bytes);
      bytes.setAll(40, Ed25519HDPublicKey.fromBase58(witness).bytes);
      bytes.setAll(
        72,
        Ed25519HDPublicKey.fromBase58(
          MwaWalletProvider.platformFeeWallet,
        ).bytes,
      );
      final view = ByteData.sublistView(bytes);
      view.setUint64(104, stake, Endian.little);
      view.setUint64(112, fee, Endian.little);
      view.setUint64(120, stake - fee, Endian.little);
      view.setInt64(128, 1770120000, Endian.little);
      bytes[136] = resolved;
      return Account(
        lamports: stake,
        owner: owner,
        data: BinaryAccountData(bytes),
        executable: false,
        rentEpoch: BigInt.zero,
      );
    }

    test('the escrow account is read as the program wrote it', () {
      final open = EscrowAccountCheck.of(escrowAccount());
      expect(open.state, EscrowAccountState.open);
      expect(open.initiator, _challenger);
      expect(open.witness, walletFixture);
      // 0.05 SOL less the 2.5% fee: what the program sends the winner.
      expect(open.payoutLamports, 48750000);

      expect(
        EscrowAccountCheck.of(escrowAccount(resolved: 1)).state,
        EscrowAccountState.settled,
      );
      expect(EscrowAccountCheck.of(null).state, EscrowAccountState.settled);
      expect(
        EscrowAccountCheck.of(
          escrowAccount(owner: '11111111111111111111111111111111'),
        ).state,
        EscrowAccountState.notThisProgram,
      );
    });

    group(
      'the witness\'s wallet opens only for a resolve the program accepts',
      () {
        const row = {
          'id': 'escrow-row',
          'escrowAddress': 'Escrow1111111111111111111111111111111111111',
          'member1_address': _challenger,
          'amount': .05,
          'winner_amount_sol': .04875,
        };

        test('nothing to sign without the witness wallet or an escrow', () {
          expect(
            escrowSettlePreflight(row, connectedWallet: null)?.subtitle,
            'Connect the witness wallet to settle it.',
          );
          expect(
            escrowSettlePreflight(const {
              'member1_address': _challenger,
            }, connectedWallet: walletFixture)?.subtitle,
            'It has no escrow account on record, so there is nothing to sign.',
          );
          expect(
            escrowSettlePreflight(row, connectedWallet: walletFixture),
            isNull,
          );
        });

        test('an open escrow: the stored challenger and the exact payout', () {
          final plan = planEscrowSettle(
            {
              ...row,
              'member1_address': 'So11111111111111111111111111111111111111112',
            },
            connectedWallet: walletFixture,
            check: EscrowAccountCheck.of(escrowAccount()),
          );
          expect(plan, isA<EscrowSettlePlan>());
          plan as EscrowSettlePlan;
          expect(plan.escrow, row['escrowAddress']);
          // The program checks the challenger it stored, not the row's.
          expect(plan.initiator, _challenger);
          expect(plan.payout, '0.04875 SOL');
        });

        test('a closed escrow is already settled, and says so', () {
          final stop = planEscrowSettle(
            row,
            connectedWallet: walletFixture,
            check: EscrowAccountCheck.of(null),
          );
          expect(stop, isA<EscrowSettleStop>());
          stop as EscrowSettleStop;
          expect(stop.title, 'Already settled');
          expect(stop.settled, isTrue);
        });

        test('another program\'s account is not called settled', () {
          final stop = planEscrowSettle(
            row,
            connectedWallet: walletFixture,
            check: EscrowAccountCheck.of(
              escrowAccount(owner: '11111111111111111111111111111111'),
            ),
          );
          stop as EscrowSettleStop;
          expect(stop.settled, isFalse);
          expect(stop.subtitle, contains('Nothing was sent'));
        });

        test(
          'a wallet that is not the stored witness stops before signing',
          () {
            final stop = planEscrowSettle(
              row,
              connectedWallet: walletFixture,
              check: EscrowAccountCheck.of(
                escrowAccount(
                  witness: 'So11111111111111111111111111111111111111112',
                ),
              ),
            );
            stop as EscrowSettleStop;
            expect(stop.title, 'Not the witness wallet');
          },
        );

        test(
          'the network could not say: the row decides, the program checks',
          () {
            final plan = planEscrowSettle(
              row,
              connectedWallet: walletFixture,
              check: const EscrowAccountCheck(EscrowAccountState.unknown),
            );
            plan as EscrowSettlePlan;
            expect(plan.initiator, _challenger);
            expect(plan.payout, '0.04875 SOL');
          },
        );
      },
    );

    test('a wallet name fits under its avatar', () {
      expect(compactWalletName('CHaLLe...1111'), 'CHaL…1111');
      expect(
        compactWalletName('So11111111111111111111111111111111111111112'),
        'So11…1112',
      );
      expect(compactWalletName('tolu.sol'), 'tolu.sol');
      expect(compactWalletName('Ada'), 'Ada');
    });

    testWidgets('the witness settles with its consequences spelled out', (
      tester,
    ) async {
      final verdicts = <bool>[];
      await _mount(
        tester,
        Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showResolveChallengeSheet(
                        context,
                        challenge: const {
                          'description': 'Run 5k every day',
                          'amount': .1,
                          'winner_amount_sol': .0975,
                          // Past due, but the program ignores the deadline.
                          'status': 'expired',
                          'isCurrentUserWitness': true,
                          'friendName': 'You',
                        },
                        onMarkCompleted:
                            (_, initiatorWon) => verdicts.add(initiatorWon),
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('In escrow'), findsOneWidget);
      expect(
        find.text(
          'You’re the witness, so you settle it. Completed sends 0.0975 SOL '
          'back to the challenger; not completed sends it to you. Your wallet '
          'asks you to approve either one.',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Not completed'));
      await tester.tap(find.text('Not completed'));
      await tester.pumpAndSettle();
      expect(verdicts, [false]);
      // The sheet hands over; it never announces a result it does not have.
      expect(find.byType(ResolveChallengeSheet), findsNothing);
      expect(find.textContaining('successfully'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the challenger is told whose move it is, with no action', (
      tester,
    ) async {
      await _mount(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ResolveChallengeSheet(
              challenge: const {
                'description': 'Run 5k every day',
                'amount': .1,
                'status': 'active',
                'isCurrentUserWitness': false,
                'friendName': 'Ada',
              },
              onMarkCompleted: (_, _) => fail('the challenger cannot settle'),
            ),
          ),
        ),
      );
      expect(find.text('Waiting for the witness to settle'), findsOneWidget);
      expect(find.textContaining('Chumbucket can’t move it'), findsOneWidget);
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Not completed'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a settled escrow says how it ended', (tester) async {
      await _mount(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ResolveChallengeSheet(
              challenge: const {
                'description': 'Run 5k every day',
                'amount': .1,
                'status': 'failed',
                'isCurrentUserWitness': true,
              },
              onMarkCompleted: (_, _) => fail('already settled'),
            ),
          ),
        ),
      );
      expect(find.text('Staked'), findsOneWidget);
      expect(find.text('Not completed'), findsOneWidget); // the outcome label
      expect(find.text('Completed'), findsNothing);
      expect(find.textContaining('You’re the witness'), findsNothing);
      // Said to the reader: the witness got it.
      expect(find.text('The stake went to you, less the fee.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the challenger reads where their stake went', (tester) async {
      await _mount(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ResolveChallengeSheet(
              challenge: const {
                'description': 'Run 5k every day',
                'amount': .1,
                'status': 'completed',
                'isCurrentUserWitness': false,
                'friendName': 'tolu.sol',
              },
              onMarkCompleted: (_, _) => fail('already settled'),
            ),
          ),
        ),
      );
      expect(find.text('Completed'), findsOneWidget);
      expect(
        find.text('Your stake came back to you, less the fee.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the escrow list never invites starting one', (tester) async {
      Future<void> list(MwaAuthProvider auth) async {
        final state = ChallengeStateProvider(loadChallenges: (_) async => []);
        addTearDown(state.dispose);
        addTearDown(auth.dispose);
        await _mount(
          tester,
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ChallengeStateProvider>.value(
                value: state,
              ),
              ChangeNotifierProvider<MwaAuthProvider>.value(value: auth),
            ],
            child: Scaffold(
              body: ChallengesTab(
                refreshKey: 0,
                onMarkChallengeCompleted: (_, _) {},
              ),
            ),
          ),
        );
      }

      // The brand scene and one line; the detail is read, not printed.
      await list(ConnectedAuth());
      expect(find.text('No escrow challenges'), findsOneWidget);
      expect(
        find.bySemanticsLabel('No escrow challenges'),
        findsOneWidget,
      );
      expect(find.textContaining('Create'), findsNothing);

      await list(_NoWallet());
      expect(find.text('Connect your wallet to see them'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every row opens its sheet, settled ones included', (
      tester,
    ) async {
      final state = ChallengeStateProvider(
        loadChallenges:
            (_) async => [
              _escrow('open', ChallengeStatus.active),
              _escrow(
                'done',
                ChallengeStatus.completed,
                witness: 'Witness111111111111111111111111111111111111',
              ),
            ],
      );
      final auth = ConnectedAuth();
      addTearDown(state.dispose);
      addTearDown(auth.dispose);
      await state.initialize(walletFixture);
      await _mount(
        tester,
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ChallengeStateProvider>.value(value: state),
            ChangeNotifierProvider<MwaAuthProvider>.value(value: auth),
          ],
          child: Scaffold(
            body: ChallengesTab(
              refreshKey: 0,
              onMarkChallengeCompleted: (_, _) {},
            ),
          ),
        ),
      );
      expect(find.text('You’re the witness'), findsOneWidget);
      // The deadline is the challenge's own: past it, the row says so plainly
      // (it used to read "Expires soon" for any date).
      expect(find.text('Was due 1 Aug 2025'), findsOneWidget);
      // A settled row says how it ended without being opened.
      expect(find.text('Completed'), findsOneWidget);
      expect(find.textContaining('Expires'), findsNothing);
      await tester.tap(find.text('Run 5k every day').last);
      await tester.pumpAndSettle();
      expect(find.byType(ResolveChallengeSheet), findsOneWidget);
      expect(find.text('Completed'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Profile points at an open escrow, saying who has to act', (
      tester,
    ) async {
      Future<void> profile(Challenge escrow) async {
        final state = ChallengeStateProvider(
          loadChallenges: (_) async => [escrow],
        );
        final calls = CallsProvider(repository: PeopleRepository([]))
          ..setViewer('user_ada');
        final auth = ConnectedAuth();
        final wallet = ConnectedWallet();
        final existing = ExistingProfile();
        for (final n in <ChangeNotifier>[
          state,
          calls,
          auth,
          wallet,
          existing,
        ]) {
          addTearDown(n.dispose);
        }
        await state.initialize(walletFixture);
        var opened = 0;
        await _mount(
          tester,
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ProfileProvider>.value(value: existing),
              ChangeNotifierProvider<MwaAuthProvider>.value(value: auth),
              ChangeNotifierProvider<MwaWalletProvider>.value(value: wallet),
              ChangeNotifierProvider<CallsProvider>.value(value: calls),
              ChangeNotifierProvider<ChallengeStateProvider>.value(
                value: state,
              ),
              Provider<AccountApi>.value(value: _Account()),
            ],
            child: ProfileScreen(
              embedded: true,
              onOpenChallenges: () => opened++,
            ),
          ),
        );
        // A slim row: a few words and a chevron. Who has to act is read
        // out with it.
        expect(find.text('Escrow still open'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('profile-open-escrow')));
        expect(opened, 1);
      }

      String hint() =>
          tester
              .getSemantics(find.byKey(const ValueKey('profile-open-escrow')))
              .hint;

      // The database writes `active` for a new escrow: it counts.
      await profile(_escrow('mine-to-settle', ChallengeStatus.active));
      expect(hint(), 'You’re the witness: only you can settle it.');

      await profile(
        _escrow(
          'theirs-to-settle',
          ChallengeStatus.expired,
          witness: 'Witness111111111111111111111111111111111111',
          initiator: walletFixture,
        ),
      );
      expect(hint(), 'Your SOL stays in escrow until the witness settles it.');
      expect(find.textContaining('refund'), findsNothing);
      expect(find.textContaining('claim'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('History promises only what the escrow program allows', (
      tester,
    ) async {
      await _mount(tester, LegacyHistoryScreen(onOpenEscrowChallenges: () {}));
      expect(find.textContaining('refund'), findsNothing);
      // Slim rows; what each holds is read out, not printed as a paragraph.
      expect(find.text('Escrow challenges'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Escrow challenges')).hint,
        contains('Any still open are settled here by their witness.'),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('friends lead to calls', () {
    testWidgets('a friend with a person id opens their profile and calls', (
      tester,
    ) async {
      final repository = PeopleRepository([]);
      final calls = CallsProvider(repository: repository);
      addTearDown(calls.dispose);
      var madeCall = false;
      await _mount(
        tester,
        Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => openFriend(context, const {
                        'name': 'Ada',
                        'walletAddress': walletFixture,
                        'userId': 'user_ada',
                      }, onMakeCall: () => madeCall = true),
                  child: const Text('Ada'),
                ),
          ),
        ),
        above:
            (app) => ChangeNotifierProvider<CallsProvider>.value(
              value: calls,
              child: app,
            ),
      );
      await tester.tap(find.text('Ada'));
      await tester.pumpAndSettle();
      expect(find.byType(CallPersonScreen), findsOneWidget);
      // Addressed by the person, never by the wallet.
      expect(repository.requestedPeople, everyElement('user_ada'));
      expect(madeCall, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without one, the sheet offers a call, not an escrow', (
      tester,
    ) async {
      var madeCall = 0;
      await _mount(
        tester,
        Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => openFriend(context, const {
                        'name': 'Ada',
                        'walletAddress': walletFixture,
                      }, onMakeCall: () => madeCall++),
                  child: const Text('Ada'),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Ada'));
      await tester.pumpAndSettle();
      expect(find.byType(FriendCallActionsSheet), findsOneWidget);
      expect(find.textContaining('dare them to call it'), findsOneWidget);
      expect(find.textContaining('no money moves'), findsOneWidget);
      expect(find.textContaining('scrow'), findsNothing);
      expect(find.textContaining('SOL'), findsNothing);
      await tester.tap(find.text('Make a call'));
      await tester.pumpAndSettle();
      expect(madeCall, 1);
      expect(find.byType(FriendCallActionsSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('All Friends opens friends, with no invented presence', (
      tester,
    ) async {
      Map<String, String>? opened;
      await _mount(
        tester,
        Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showViewMoreFriendsSheet(
                        context,
                        friends: const [
                          {'name': 'Ada', 'userId': 'user_ada'},
                          {'name': 'Ada', 'userId': 'user_ada_2'},
                        ],
                        onFriendSelected: (friend) => opened = friend,
                      ),
                  child: const Text('all'),
                ),
          ),
        ),
      );
      await tester.tap(find.text('all'));
      await tester.pumpAndSettle();
      expect(find.text('Open a friend to see their calls'), findsOneWidget);
      expect(find.textContaining('challenge'), findsNothing);
      expect(find.text('Available'), findsNothing);
      await tester.tap(find.text('Ada').first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      // The whole row travels, so two friends with one name stay distinct.
      expect(opened?['userId'], 'user_ada');
      expect(tester.takeException(), isNull);
    });
  });
}
