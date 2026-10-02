/// The phone's own check of a gasless USDC -> SOL swap, before any wallet is
/// asked to sign it.
///
/// The BFF runs the same rules (`src/solTopUp/verify.ts`) and simulates the
/// swap on mainnet before sending it here. This is the independent check on
/// the device: for the wallet that lives on this phone it is the only thing
/// between "Sign and swap" and a signature; for a wallet app it runs before
/// the app opens. It needs no network: everything that belongs to the person
/// (the wallet, its USDC and WSOL accounts) is a static key, because lookup
/// tables only ever hold shared accounts and can never hold a signer.
///
/// A swap may only: let someone else pay the fee; create the person's own
/// USDC/WSOL account at the payer's cost; run ONE exact-in Jupiter route or
/// JupiterZ fill that spends exactly the reviewed USDC from the person's own
/// USDC account into the person's own SOL; close the WSOL account back to the
/// person; repay the payer the rent it put into that WSOL account; and pay
/// Jupiter's quoted fee. Rules and the real transactions they were read from:
/// docs/gasless-sol-topup.md (API repo).
library;

import 'dart:typed_data';

import 'package:solana/encoder.dart' as encoder;
import 'package:solana/solana.dart'
    show Ed25519HDPublicKey, findAssociatedTokenAddress;

const usdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const wsolMint = 'So11111111111111111111111111111111111111112';
const tokenProgram = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const ataProgram = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const systemProgram = '11111111111111111111111111111111';
const computeBudgetProgram = 'ComputeBudget111111111111111111111111111111';

/// Jupiter Aggregator v6 (the Metis router).
const jupiterV6Program = 'JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4';

/// JupiterZ order engine (the RFQ router).
const jupiterZProgram = '61DFfeTKM7trxYcPQCM78bJ794ddZprZpAwAnLiwTpYH';

/// Jupiter's gas wallet: `signatureFeePayer` when Jupiter sponsors a swap.
const jupiterGasWallet = 'gasTzr94Pmp4Gf8vknQnqxeYxdgwFjbgdJa4msYRpnB';

const maxSwapFeeBps = 300;
const maxSwapSlippageBps = 300;
final maxRentRepayLamports = BigInt.from(2039280);
const maxFillTtlSeconds = 600;
const minQuoteFidelityBps = 9900;

// sha256("global:<name>")[0..8], the Anchor discriminators in Jupiter's
// on-chain IDLs.
const _routeV1Disc = [0xe5, 0x17, 0xcb, 0x97, 0x7a, 0xe3, 0xad, 0x2a];
const _sharedRouteV1Disc = [0xc1, 0x20, 0x9b, 0x33, 0x41, 0xd6, 0x9c, 0x81];
const _routeV2Disc = [0xbb, 0x64, 0xfa, 0xcc, 0x31, 0xc4, 0xaf, 0x14];
const _sharedRouteV2Disc = [0xd1, 0x98, 0x53, 0x93, 0x7c, 0xfe, 0xd8, 0xe9];
const _fillDisc = [0xa8, 0x60, 0xb7, 0xa3, 0x5c, 0x0a, 0x28, 0xa0];

enum SwapRouter {
  metis,
  jupiterZ;

  static SwapRouter? parse(Object? wire) => switch (wire) {
    'metis' => SwapRouter.metis,
    'jupiterz' => SwapRouter.jupiterZ,
    _ => null,
  };
}

class SwapCheckException implements Exception {
  const SwapCheckException(this.reason);

  /// Internal, for tests and logs. Never shown: the sheet says "didn't pass
  /// our checks — nothing was signed".
  final String reason;

  @override
  String toString() => 'SwapCheckException($reason)';
}

/// What the person reviewed.
class ExpectedSwap {
  const ExpectedSwap({
    required this.owner,
    required this.inAmount,
    required this.router,
    required this.quotedOutLamports,
    required this.feeBps,
    required this.nowSeconds,
  });

  final String owner;
  final BigInt inAmount;
  final SwapRouter router;

  /// The quote's SOL, net of Jupiter's fee, before slippage.
  final BigInt quotedOutLamports;
  final int feeBps;
  final int nowSeconds;
}

class CheckedSwap {
  const CheckedSwap({
    required this.router,
    required this.feePayer,
    required this.ownerSignatureIndex,
    required this.inAmount,
    required this.minOutLamports,
    required this.expectedOutLamports,
    required this.feeBps,
    required this.slippageBps,
    required this.messageBytes,
  });

  final SwapRouter router;
  final String feePayer;
  final int ownerSignatureIndex;
  final BigInt inAmount;

  /// The least SOL the transaction itself lets land in the person's wallet.
  final BigInt minOutLamports;
  final BigInt expectedOutLamports;
  final int feeBps;
  final int slippageBps;

  /// Exactly what the person's key signs.
  final Uint8List messageBytes;
}

Future<String> ownerTokenAccount(String owner, String mint) async =>
    (await findAssociatedTokenAddress(
      owner: Ed25519HDPublicKey.fromBase58(owner),
      mint: Ed25519HDPublicKey.fromBase58(mint),
    )).toBase58();

/// Throws [SwapCheckException] for anything but the reviewed swap.
Future<CheckedSwap> checkGaslessSwap(
  Uint8List bytes,
  ExpectedSwap expected,
) async {
  Never fail(String reason) => throw SwapCheckException(reason);
  void need(bool ok, String reason) {
    if (!ok) fail(reason);
  }

  final encoder.SignedTx tx;
  try {
    need(bytes.isNotEmpty && bytes.length <= 1232, 'size');
    tx = encoder.SignedTx.fromBytes(bytes);
  } on SwapCheckException {
    rethrow;
  } catch (_) {
    fail('encoding');
  }
  final message = tx.compiledMessage;
  need(message is encoder.CompiledMessageV0, 'not a v0 transaction');
  final v0 = message as encoder.CompiledMessageV0;
  final keys = v0.accountKeys.map((k) => k.toBase58()).toList();
  final messageBytes = Uint8List.fromList(v0.toByteArray().toList());
  final header = v0.header;
  final signers = header.numRequiredSignatures;
  need(signers >= 2 && signers <= 3, 'signer count');
  need(
    bytes[0] == signers &&
        tx.signatures.length == signers &&
        bytes.length == 1 + 64 * signers + messageBytes.length &&
        _same(bytes.sublist(1 + 64 * signers), messageBytes),
    'signature slots',
  );
  need(keys.toSet().length == keys.length, 'duplicate keys');

  final owner = expected.owner;
  final ownerUsdc = await ownerTokenAccount(owner, usdcMint);
  final ownerWsol = await ownerTokenAccount(owner, wsolMint);
  final feePayer = keys.first;
  need(feePayer != owner, 'the person would pay the network fee');
  final ownerIndex = keys.indexOf(owner);
  final writableSigners = signers - header.numReadonlySignedAccounts;
  need(ownerIndex >= 1 && ownerIndex < writableSigners, 'not a signer');
  need(
    tx.signatures[ownerIndex].bytes.every((b) => b == 0),
    'already signed for the person',
  );
  for (final account in [ownerUsdc, ownerWsol]) {
    final at = keys.indexOf(account);
    need(at < 0 || at >= signers, 'token account as signer');
  }
  var loaded = 0;
  for (final lookup in v0.addressTableLookups) {
    loaded += lookup.writableIndexes.length + lookup.readonlyIndexes.length;
  }
  final total = keys.length + loaded;

  bool isStatic(int index, String key) =>
      index < keys.length && keys[index] == key;
  bool staticOrLoaded(int index, String key) =>
      index < keys.length ? keys[index] == key : index < total;
  String? at(int index) {
    if (index >= total) fail('account index');
    return index < keys.length ? keys[index] : null;
  }

  _Swap? swap;
  var wsolCreated = false;
  var wsolClosed = false;
  var rentRepay = BigInt.zero;
  ({String to, BigInt lamports})? feePaid;
  final synced = <String>{};
  var ataCreates = 0;

  for (final ix in v0.instructions) {
    need(
      ix.programIdIndex >= signers && ix.programIdIndex < keys.length,
      'program index',
    );
    final program = keys[ix.programIdIndex];
    final data = ix.data.toList();
    final accounts = ix.accountKeyIndexes;
    for (final index in accounts) {
      at(index);
    }
    switch (program) {
      case computeBudgetProgram:
        need(accounts.isEmpty && data.isNotEmpty && data.length <= 9, 'budget');
        if (data[0] == 2) {
          need(
            data.length == 5 && _le(data, 1, 4) <= BigInt.from(1400000),
            'compute limit',
          );
        } else if (data[0] == 3) {
          need(data.length == 9, 'compute price');
        } else {
          need(data[0] == 1 || data[0] == 4, 'budget kind');
        }
      case ataProgram:
        need(
          data.isEmpty || (data.length == 1 && (data[0] == 0 || data[0] == 1)),
          'token account instruction',
        );
        need(accounts.length == 6 && ++ataCreates <= 2, 'token account');
        final wsol = isStatic(accounts[1], ownerWsol);
        need(isStatic(accounts[0], feePayer), 'paid by the person');
        need(isStatic(accounts[2], owner), 'for someone else');
        need(wsol || isStatic(accounts[1], ownerUsdc), 'unexpected account');
        need(
          isStatic(accounts[4], systemProgram) &&
              isStatic(accounts[5], tokenProgram),
          'token account programs',
        );
        need(
          staticOrLoaded(accounts[3], wsol ? wsolMint : usdcMint),
          'token account mint',
        );
        if (wsol) wsolCreated = true;
      case jupiterV6Program:
        need(
          swap == null && expected.router == SwapRouter.metis,
          'second or unexpected swap',
        );
        swap = _route(
          data,
          accounts,
          owner: owner,
          ownerUsdc: ownerUsdc,
          ownerWsol: ownerWsol,
          isStatic: isStatic,
          staticOrLoaded: staticOrLoaded,
        );
      case jupiterZProgram:
        need(
          swap == null && expected.router == SwapRouter.jupiterZ,
          'second or unexpected swap',
        );
        // fill(input_amount u64, output_amount u64, expire_at i64); live
        // fills carry up to 5 more bytes the published IDL does not name.
        need(
          data.length >= 32 && data.length <= 40 && _starts(data, _fillDisc),
          'not a fill',
        );
        need(accounts.length >= 11, 'fill accounts');
        need(isStatic(accounts[0], owner), 'fill taker');
        need(isStatic(accounts[1], feePayer), 'maker is not the fee payer');
        need(isStatic(accounts[2], ownerUsdc), 'spends another account');
        need(
          isStatic(accounts[4], jupiterZProgram) ||
              isStatic(accounts[4], ownerWsol),
          'pays someone else',
        );
        need(
          staticOrLoaded(accounts[6], usdcMint) &&
              staticOrLoaded(accounts[8], wsolMint),
          'fill mints',
        );
        final out = _le(data, 16, 8);
        final expireAt = _le(data, 24, 8).toInt();
        need(out > BigInt.zero, 'pays nothing');
        need(
          expireAt > expected.nowSeconds &&
              expireAt <= expected.nowSeconds + maxFillTtlSeconds,
          'fill expiry',
        );
        swap = _Swap(
          inAmount: _le(data, 8, 8),
          expectedOut: out,
          minOut: out,
          slippageBps: 0,
          feeBps: 0,
        );
      case tokenProgram:
        if (data.length == 1 && data[0] == 9) {
          need(
            accounts.length == 3 &&
                isStatic(accounts[0], ownerWsol) &&
                isStatic(accounts[1], owner) &&
                isStatic(accounts[2], owner) &&
                !wsolClosed,
            'close pays someone else',
          );
          wsolClosed = true;
        } else if (data.length == 1 && data[0] == 17) {
          need(accounts.length == 1, 'sync');
          final account = at(accounts[0]);
          need(account != null && account != ownerUsdc, 'sync');
          synced.add(account!);
        } else {
          fail('token instruction');
        }
      case systemProgram:
        need(
          data.length == 12 && _le(data, 0, 4) == BigInt.two,
          'system instruction',
        );
        need(accounts.length == 2, 'transfer accounts');
        final from = at(accounts[0]);
        final to = at(accounts[1]);
        final lamports = _le(data, 4, 8);
        if (from != owner) {
          // The payer's own money (a tip), never the person's.
          need(from != null && accounts[0] < signers, 'transfer source');
          break;
        }
        need(to != null && to != owner, 'transfer destination');
        if (to == feePayer) {
          need(
            rentRepay == BigInt.zero &&
                wsolCreated &&
                wsolClosed &&
                lamports <= maxRentRepayLamports,
            'rent repayment',
          );
          rentRepay = lamports;
        } else {
          need(
            feePaid == null && expected.router == SwapRouter.jupiterZ,
            'transfer from the person',
          );
          feePaid = (to: to!, lamports: lamports);
        }
      default:
        fail('program');
    }
  }

  final s = swap ?? fail('no swap');
  need(s.inAmount == expected.inAmount, 'amount differs from the review');
  need(
    expected.feeBps >= 0 && expected.feeBps <= maxSwapFeeBps,
    'fee too high',
  );
  var minOut = s.minOut;
  var expectedOut = s.expectedOut;
  var feeBps = s.feeBps;
  if (expected.router == SwapRouter.jupiterZ) {
    feeBps = expected.feeBps;
    final bound =
        (s.expectedOut * BigInt.from(expected.feeBps) + BigInt.from(9999)) ~/
        BigInt.from(10000);
    final paid = feePaid;
    if (paid != null) {
      need(
        paid.lamports <= bound && synced.contains(paid.to),
        'fee above the quote',
      );
      minOut -= paid.lamports;
      expectedOut -= paid.lamports;
    }
  } else {
    need(
      s.feeBps <= maxSwapFeeBps && s.feeBps <= expected.feeBps,
      'fee above the quote',
    );
    need(wsolClosed, 'SOL left wrapped');
  }
  need(s.slippageBps <= maxSwapSlippageBps, 'slippage too wide');
  need(minOut > BigInt.zero, 'pays nothing');
  need(
    expectedOut * BigInt.from(10000) >=
        expected.quotedOutLamports * BigInt.from(minQuoteFidelityBps),
    'worse than the quote',
  );
  return CheckedSwap(
    router: expected.router,
    feePayer: feePayer,
    ownerSignatureIndex: ownerIndex,
    inAmount: s.inAmount,
    minOutLamports: minOut,
    expectedOutLamports: expectedOut,
    feeBps: feeBps,
    slippageBps: s.slippageBps,
    messageBytes: messageBytes,
  );
}

class _Swap {
  const _Swap({
    required this.inAmount,
    required this.expectedOut,
    required this.minOut,
    required this.slippageBps,
    required this.feeBps,
  });
  final BigInt inAmount;
  final BigInt expectedOut;
  final BigInt minOut;
  final int slippageBps;
  final int feeBps;
}

/// Jupiter v6 exact-in routes only (layouts from its on-chain IDL).
_Swap _route(
  List<int> data,
  List<int> accounts, {
  required String owner,
  required String ownerUsdc,
  required String ownerWsol,
  required bool Function(int, String) isStatic,
  required bool Function(int, String) staticOrLoaded,
}) {
  void need(bool ok, String reason) {
    if (!ok) throw SwapCheckException(reason);
  }

  bool noneOrWsol(int index) =>
      isStatic(index, jupiterV6Program) || isStatic(index, ownerWsol);

  BigInt inAmount, quotedOut;
  int slippageBps, feeBps;
  if (_starts(data, _routeV2Disc) || _starts(data, _sharedRouteV2Disc)) {
    final shared = _starts(data, _sharedRouteV2Disc);
    final o = shared ? 9 : 8;
    need(data.length >= o + 26, 'route data');
    inAmount = _le(data, o, 8);
    quotedOut = _le(data, o + 8, 8);
    slippageBps = _le(data, o + 16, 2).toInt();
    feeBps = _le(data, o + 18, 2).toInt();
    if (shared) {
      need(accounts.length >= 12, 'route accounts');
      need(
        isStatic(accounts[1], owner) && isStatic(accounts[2], ownerUsdc),
        'spends another account',
      );
      need(isStatic(accounts[5], ownerWsol), 'pays someone else');
      need(
        staticOrLoaded(accounts[6], usdcMint) &&
            staticOrLoaded(accounts[7], wsolMint),
        'route mint',
      );
    } else {
      need(accounts.length >= 10, 'route accounts');
      need(
        isStatic(accounts[0], owner) && isStatic(accounts[1], ownerUsdc),
        'spends another account',
      );
      need(
        isStatic(accounts[2], ownerWsol) && noneOrWsol(accounts[7]),
        'pays someone else',
      );
      need(
        staticOrLoaded(accounts[3], usdcMint) &&
            staticOrLoaded(accounts[4], wsolMint),
        'route mint',
      );
      need(
        staticOrLoaded(accounts[5], tokenProgram) &&
            staticOrLoaded(accounts[6], tokenProgram),
        'route token programs',
      );
    }
  } else if (_starts(data, _routeV1Disc) || _starts(data, _sharedRouteV1Disc)) {
    // v1: route_plan first, then a fixed 19-byte tail.
    final shared = _starts(data, _sharedRouteV1Disc);
    need(data.length >= 8 + (shared ? 1 : 0) + 4 + 19, 'route data');
    final t = data.length - 19;
    inAmount = _le(data, t, 8);
    quotedOut = _le(data, t + 8, 8);
    slippageBps = _le(data, t + 16, 2).toInt();
    feeBps = data[t + 18];
    if (shared) {
      need(accounts.length >= 13, 'route accounts');
      need(
        isStatic(accounts[2], owner) && isStatic(accounts[3], ownerUsdc),
        'spends another account',
      );
      need(isStatic(accounts[6], ownerWsol), 'pays someone else');
      need(
        staticOrLoaded(accounts[7], usdcMint) &&
            staticOrLoaded(accounts[8], wsolMint),
        'route mint',
      );
    } else {
      need(accounts.length >= 9, 'route accounts');
      need(
        isStatic(accounts[1], owner) && isStatic(accounts[2], ownerUsdc),
        'spends another account',
      );
      need(
        isStatic(accounts[3], ownerWsol) && noneOrWsol(accounts[4]),
        'pays someone else',
      );
      need(staticOrLoaded(accounts[5], wsolMint), 'route mint');
    }
  } else {
    throw const SwapCheckException('not an exact-in route');
  }
  need(quotedOut > BigInt.zero, 'pays nothing');
  final tenK = BigInt.from(10000);
  BigInt afterFee(BigInt v) => v * BigInt.from(10000 - feeBps) ~/ tenK;
  return _Swap(
    inAmount: inAmount,
    expectedOut: afterFee(quotedOut),
    minOut: afterFee(quotedOut * BigInt.from(10000 - slippageBps) ~/ tenK),
    slippageBps: slippageBps,
    feeBps: feeBps,
  );
}

bool _starts(List<int> data, List<int> prefix) {
  if (data.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (data[i] != prefix[i]) return false;
  }
  return true;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

BigInt _le(List<int> data, int offset, int length) {
  if (offset + length > data.length) {
    throw const SwapCheckException('short data');
  }
  var value = BigInt.zero;
  for (var i = length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(data[offset + i]);
  }
  return value;
}
