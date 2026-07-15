import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:solana/base58.dart';
import 'package:solana/encoder.dart' as encoder;
import 'package:solana/solana.dart' as solana;
import 'package:solana/src/programs/associated_token_account_program/instruction.dart';
import 'package:solana/src/rpc/dto/account_data/account_data.dart';

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';

/// Solo staking into a shared match-outcome pot.
///
/// This talks to the chumbucket_arena Anchor program through Mobile Wallet
/// Adapter. It intentionally avoids Privy/Anchor wallet adapters because the
/// live Chumbucket app authenticates and signs with MWA on Solana Mobile.
class MatchArenaService {
  static const String PROGRAM_ID =
      'AMFpYiYPCUwiVbYMkhnaCmnSDv226yew17QXLhVWk9CG';

  /// Devnet test USDC mint (onchain/gaffer_verifier/scripts/devnet-lifecycle/test-usdc-mint.json).
  static const String USDC_MINT =
      '3r7XYUxoGZ57Fm91zbTw8GtmwCYzPV5CdmabqgDwtdhY';

  static const int USDC_DECIMALS = 6;
  static const int _usdcBaseUnitsPerWhole = 1000000;

  static const int bucketHome = 0;
  static const int bucketDraw = 1;
  static const int bucketAway = 2;

  static const List<int> _placeCallDiscriminator = [
    11,
    8,
    17,
    8,
    195,
    166,
    211,
    69,
  ];
  static const List<int> _claimDiscriminator = [
    62,
    198,
    214,
    193,
    213,
    159,
    108,
    210,
  ];
  static const List<int> _positionDiscriminator = [
    170,
    188,
    143,
    228,
    122,
    64,
    247,
    208,
  ];

  static final List<int> _potSeed = utf8.encode('pot');
  static final List<int> _vaultSeed = utf8.encode('vault');
  static final List<int> _positionSeed = utf8.encode('position');

  final MwaAuthProvider _authProvider;
  final solana.SolanaClient _client;
  final solana.Ed25519HDPublicKey _playerPubkey;
  final solana.Ed25519HDPublicKey _programPubkey;
  final solana.Ed25519HDPublicKey _usdcMintPubkey;

  MatchArenaService._({
    required MwaAuthProvider authProvider,
    required solana.SolanaClient client,
    required solana.Ed25519HDPublicKey playerPubkey,
    required solana.Ed25519HDPublicKey programPubkey,
    required solana.Ed25519HDPublicKey usdcMintPubkey,
  }) : _authProvider = authProvider,
       _client = client,
       _playerPubkey = playerPubkey,
       _programPubkey = programPubkey,
       _usdcMintPubkey = usdcMintPubkey;

  static Future<MatchArenaService> create({
    required MwaAuthProvider authProvider,
    required String walletAddress,
    String? rpcUrl,
  }) async {
    if (!authProvider.isAuthenticated) {
      throw StateError('Connect your wallet before using the arena.');
    }

    final effectiveRpcUrl = rpcUrl ?? NetworkConfig.rpcUrl;
    log('🎯 Initializing MatchArenaService for MWA');
    log('🔗 RPC URL: $effectiveRpcUrl');
    log('🔑 Wallet Address: $walletAddress');

    final client = solana.SolanaClient(
      rpcUrl: Uri.parse(effectiveRpcUrl),
      websocketUrl: Uri.parse(
        effectiveRpcUrl.replaceFirst('https', 'wss').replaceFirst('http', 'ws'),
      ),
    );

    final service = MatchArenaService._(
      authProvider: authProvider,
      client: client,
      playerPubkey: solana.Ed25519HDPublicKey.fromBase58(walletAddress),
      programPubkey: solana.Ed25519HDPublicKey.fromBase58(PROGRAM_ID),
      usdcMintPubkey: solana.Ed25519HDPublicKey.fromBase58(USDC_MINT),
    );

    try {
      final programAccount = await client.rpcClient.getAccountInfo(PROGRAM_ID);
      if (programAccount.value == null) {
        throw Exception(
          'chumbucket_arena program not found on-chain. Please deploy it first.',
        );
      }
      log('✅ chumbucket_arena program account verified on-chain');
    } catch (e) {
      log('⚠️ Warning: Could not verify chumbucket_arena program on-chain: $e');
    }

    return service;
  }

  String get walletAddress => _playerPubkey.toBase58();
  solana.Ed25519HDPublicKey get playerPubkey => _playerPubkey;

  static int usdcToBaseUnits(double amountUsdc) =>
      (amountUsdc * _usdcBaseUnitsPerWhole).round();

  static double baseUnitsToUsdc(BigInt baseUnits) =>
      baseUnits.toDouble() / _usdcBaseUnitsPerWhole;

  static List<int> encodeMatchId(String matchId) {
    final asciiBytes = ascii.encode(matchId);
    if (asciiBytes.length > 32) {
      throw ArgumentError(
        'matchId "$matchId" is ${asciiBytes.length} ASCII bytes, longer than the 32-byte on-chain limit',
      );
    }
    final padded = List<int>.filled(32, 0);
    final start = 32 - asciiBytes.length;
    for (var i = 0; i < asciiBytes.length; i++) {
      padded[start + i] = asciiBytes[i];
    }
    return padded;
  }

  Future<solana.Ed25519HDPublicKey> derivePotPda(String matchId) =>
      solana.Ed25519HDPublicKey.findProgramAddress(
        seeds: [_potSeed, encodeMatchId(matchId)],
        programId: _programPubkey,
      );

  Future<solana.Ed25519HDPublicKey> deriveVaultPda(
    solana.Ed25519HDPublicKey pot,
  ) => solana.Ed25519HDPublicKey.findProgramAddress(
    seeds: [_vaultSeed, pot.bytes],
    programId: _programPubkey,
  );

  Future<solana.Ed25519HDPublicKey> derivePositionPda(
    solana.Ed25519HDPublicKey pot,
    solana.Ed25519HDPublicKey player,
  ) => solana.Ed25519HDPublicKey.findProgramAddress(
    seeds: [_positionSeed, pot.bytes, player.bytes],
    programId: _programPubkey,
  );

  Future<solana.Ed25519HDPublicKey> derivePlayerUsdcAta(
    solana.Ed25519HDPublicKey player,
  ) => solana.findAssociatedTokenAddress(owner: player, mint: _usdcMintPubkey);

  Future<List<encoder.Instruction>> _maybeCreateAtaPreInstructions(
    solana.Ed25519HDPublicKey player,
    solana.Ed25519HDPublicKey ata,
  ) async {
    final accountInfo = await _client.rpcClient.getAccountInfo(ata.toBase58());
    if (accountInfo.value != null) return const [];

    log('💳 Player USDC ATA does not exist yet, creating: ${ata.toBase58()}');
    return [
      AssociatedTokenAccountInstruction.createAccount(
        funder: player,
        address: ata,
        owner: player,
        mint: _usdcMintPubkey,
      ),
    ];
  }

  encoder.Instruction _placeCallInstruction({
    required solana.Ed25519HDPublicKey player,
    required solana.Ed25519HDPublicKey pot,
    required solana.Ed25519HDPublicKey vault,
    required solana.Ed25519HDPublicKey playerUsdc,
    required solana.Ed25519HDPublicKey position,
    required int bucket,
    required int amountBaseUnits,
  }) {
    final data = ByteData(17);
    for (var i = 0; i < _placeCallDiscriminator.length; i++) {
      data.setUint8(i, _placeCallDiscriminator[i]);
    }
    data.setUint8(8, bucket);
    data.setUint64(9, amountBaseUnits, Endian.little);

    return encoder.Instruction(
      programId: _programPubkey,
      accounts: [
        encoder.AccountMeta.writeable(pubKey: player, isSigner: true),
        encoder.AccountMeta.writeable(pubKey: pot, isSigner: false),
        encoder.AccountMeta.writeable(pubKey: vault, isSigner: false),
        encoder.AccountMeta.writeable(pubKey: playerUsdc, isSigner: false),
        encoder.AccountMeta.writeable(pubKey: position, isSigner: false),
        encoder.AccountMeta.readonly(
          pubKey: solana.TokenProgram.id,
          isSigner: false,
        ),
        encoder.AccountMeta.readonly(
          pubKey: solana.SystemProgram.id,
          isSigner: false,
        ),
      ],
      data: encoder.ByteArray(Uint8List.view(data.buffer)),
    );
  }

  encoder.Instruction _claimInstruction({
    required solana.Ed25519HDPublicKey player,
    required solana.Ed25519HDPublicKey pot,
    required solana.Ed25519HDPublicKey vault,
    required solana.Ed25519HDPublicKey playerUsdc,
    required solana.Ed25519HDPublicKey position,
  }) {
    return encoder.Instruction(
      programId: _programPubkey,
      accounts: [
        encoder.AccountMeta.writeable(pubKey: player, isSigner: true),
        encoder.AccountMeta.writeable(pubKey: pot, isSigner: false),
        encoder.AccountMeta.writeable(pubKey: vault, isSigner: false),
        encoder.AccountMeta.writeable(pubKey: playerUsdc, isSigner: false),
        encoder.AccountMeta.writeable(pubKey: position, isSigner: false),
        encoder.AccountMeta.readonly(
          pubKey: solana.TokenProgram.id,
          isSigner: false,
        ),
      ],
      data: encoder.ByteArray(Uint8List.fromList(_claimDiscriminator)),
    );
  }

  Future<String> _signAndSend(List<encoder.Instruction> instructions) async {
    final blockhashResult = await _client.rpcClient.getLatestBlockhash();
    final compiledMessage = encoder.Message(instructions: instructions).compile(
      recentBlockhash: blockhashResult.value.blockhash,
      feePayer: playerPubkey,
    );

    final placeholderSignature = encoder.Signature(
      List.filled(64, 0),
      publicKey: playerPubkey,
    );
    final signedTx = encoder.SignedTx(
      compiledMessage: compiledMessage,
      signatures: [placeholderSignature],
    );

    final signingSession = await _authProvider.createSigningSession();
    if (signingSession == null) {
      throw Exception('Failed to create MWA signing session');
    }

    try {
      final result = await signingSession.signAndSendTransactions(
        transactions: [Uint8List.fromList(signedTx.toByteArray().toList())],
      );
      if (result.signatures.isEmpty) {
        throw Exception('Transaction signing failed');
      }
      return base58encode(Uint8List.fromList(result.signatures.first));
    } finally {
      await signingSession.close();
      log('🔒 Arena MWA session closed');
    }
  }

  Future<String> placeCall({
    required String matchId,
    required int bucket,
    required double amountUsdc,
  }) async {
    if (bucket != bucketHome && bucket != bucketDraw && bucket != bucketAway) {
      throw ArgumentError('bucket must be 0 (HOME), 1 (DRAW) or 2 (AWAY)');
    }
    if (amountUsdc <= 0) {
      throw ArgumentError('amountUsdc must be greater than zero');
    }

    final amountBaseUnits = usdcToBaseUnits(amountUsdc);
    log(
      '🚀 placeCall: matchId=$matchId bucket=$bucket amount=$amountBaseUnits',
    );

    final pot = await derivePotPda(matchId);
    final vault = await deriveVaultPda(pot);
    final position = await derivePositionPda(pot, playerPubkey);
    final playerUsdc = await derivePlayerUsdcAta(playerPubkey);

    final instructions = [
      ...await _maybeCreateAtaPreInstructions(playerPubkey, playerUsdc),
      _placeCallInstruction(
        player: playerPubkey,
        pot: pot,
        vault: vault,
        playerUsdc: playerUsdc,
        position: position,
        bucket: bucket,
        amountBaseUnits: amountBaseUnits,
      ),
    ];

    final signature = await _signAndSend(instructions);
    log('✅ place_call sent: $signature');
    log('🔗 Explorer: ${NetworkConfig.getExplorerUrl(signature)}');
    return signature;
  }

  Future<String> claim({required String matchId}) async {
    log('🎯 claim: matchId=$matchId player=${playerPubkey.toBase58()}');

    final pot = await derivePotPda(matchId);
    final vault = await deriveVaultPda(pot);
    final position = await derivePositionPda(pot, playerPubkey);
    final playerUsdc = await derivePlayerUsdcAta(playerPubkey);

    final signature = await _signAndSend([
      _claimInstruction(
        player: playerPubkey,
        pot: pot,
        vault: vault,
        playerUsdc: playerUsdc,
        position: position,
      ),
    ]);
    log('✅ claim sent: $signature');
    return signature;
  }

  Future<Map<String, dynamic>?> getPosition({
    required String matchId,
    solana.Ed25519HDPublicKey? player,
  }) async {
    try {
      final pot = await derivePotPda(matchId);
      final position = await derivePositionPda(pot, player ?? playerPubkey);
      final accountInfo = await _client.rpcClient.getAccountInfo(
        position.toBase58(),
      );
      final account = accountInfo.value;
      final rawData = account?.data;
      if (rawData == null) return null;

      final data = _extractAccountData(rawData);
      if (data == null || data.length < 83) return null;
      if (!_listEquals(data.sublist(0, 8), _positionDiscriminator)) {
        return null;
      }

      var offset = 8;
      final potAddress = base58encode(data.sublist(offset, offset + 32));
      offset += 32;
      final playerAddress = base58encode(data.sublist(offset, offset + 32));
      offset += 32;
      final bucket = data[offset];
      offset += 1;
      final stake = _readU64LE(data, offset);
      offset += 8;
      final claimed = data[offset] != 0;
      offset += 1;
      final bump = data[offset];

      return {
        'pot': potAddress,
        'player': playerAddress,
        'bucket': bucket,
        'stake': stake,
        'claimed': claimed,
        'bump': bump,
      };
    } catch (e) {
      log('⚠️ getPosition($matchId) failed: $e');
      return null;
    }
  }

  Uint8List? _extractAccountData(AccountData rawData) {
    if (rawData is BinaryAccountData) {
      return Uint8List.fromList(rawData.data);
    }
    return null;
  }

  BigInt _readU64LE(Uint8List data, int offset) {
    var value = BigInt.zero;
    for (var i = 0; i < 8; i++) {
      value |= BigInt.from(data[offset + i]) << (8 * i);
    }
    return value;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
