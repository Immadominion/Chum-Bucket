import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solana/base58.dart';
import 'package:solana/solana.dart' as solana;
import 'package:solana/encoder.dart' as encoder;
import 'package:solana/dto.dart' show Account, Commitment, Encoding;
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart'
    show LoadingState;
import 'package:chumbucket/core/config/network_config.dart';

/// Pinocchio escrow instructions this app can still build.
///
/// Creating a SOL escrow challenge (`0x01`) is retired: the program is live on
/// mainnet, so a new one would lock real SOL behind a witness rather than a
/// venue. The app keeps only what an EXISTING escrow needs: the witness's
/// resolve, and the challenger's cancel.
class PinocchioInstructions {
  static const int resolveChallenge = 0x02;
  static const int cancelChallenge = 0x03;
}

/// MWA-based wallet provider: SOL balance and transfers, and the remaining
/// actions on an earlier Pinocchio escrow challenge (Settings → History).
class MwaWalletProvider extends ChangeNotifier {
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // Pinocchio escrow program ID (deployed on devnet and mainnet)
  static const String escrowProgramId =
      'D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1';

  // Platform fee wallet
  static const String platformFeeWallet =
      '3yHQosvdAhoFZHs66iFcdfRuT2aApAu6Yst2yoeDNjZm';

  // System program
  static const String systemProgramId = '11111111111111111111111111111111';

  // Challenge account size (matches Pinocchio struct)
  static const int challengeAccountSize = 146;

  late final solana.SolanaClient _client;
  final Future<Account?> Function(String address)? _readEscrowAccount;

  double _balance = 0.0;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _isLoading = false;
  String? _walletAddress;
  LoadingState _loadingState = LoadingState.idle;

  // Getters
  double get balance => _balance;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  String? get walletAddress => _walletAddress;
  LoadingState get loadingState => _loadingState;

  /// [readEscrowAccount] replaces the RPC read behind [escrowIsOpen] (tests).
  MwaWalletProvider({
    Future<Account?> Function(String address)? readEscrowAccount,
  }) : _readEscrowAccount = readEscrowAccount {
    final rpcUrl = NetworkConfig.rpcUrl;
    _client = solana.SolanaClient(
      rpcUrl: Uri.parse(rpcUrl),
      websocketUrl: Uri.parse(
        rpcUrl.replaceFirst('https', 'wss').replaceFirst('http', 'ws'),
      ),
    );
    log(
      'MwaWalletProvider initialized with RPC: $rpcUrl (network: ${NetworkConfig.currentNetwork})',
      name: 'MwaWalletProvider',
    );
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    _loadingState = loading ? LoadingState.loading : LoadingState.idle;
    notifyListeners();
  }

  void _setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Initialize wallet from MWA auth provider
  Future<void> initializeFromAuth(MwaAuthProvider authProvider) async {
    log(
      '🔄 initializeFromAuth called - current state: isInitialized=$_isInitialized, walletAddress=$_walletAddress',
      name: 'MwaWalletProvider',
    );
    log(
      '🔄 authProvider.walletAddress = ${authProvider.walletAddress}',
      name: 'MwaWalletProvider',
    );

    // Check if already initialized for a DIFFERENT wallet - if so, force re-init
    if (_isInitialized && _walletAddress != authProvider.walletAddress) {
      log(
        '🔄 Wallet address changed from $_walletAddress to ${authProvider.walletAddress}, clearing and re-initializing',
        name: 'MwaWalletProvider',
      );
      clear();
    }

    if (_isInitialized && _walletAddress == authProvider.walletAddress) {
      log(
        '⚠️ Wallet already initialized for same address, skipping',
        name: 'MwaWalletProvider',
      );
      return;
    }

    if (!authProvider.isAuthenticated) {
      throw Exception('User must be authenticated to initialize wallet');
    }

    _setLoading(true);
    try {
      _walletAddress = authProvider.walletAddress;
      await refreshBalance(authProvider.walletAddress!);
      _isInitialized = true;
      log(
        '✅ Wallet initialized for ${authProvider.walletAddress}',
        name: 'MwaWalletProvider',
      );
    } catch (e) {
      _setError('Failed to initialize wallet: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Clear wallet state (for logout)
  void clear() {
    log('🧹 Clearing wallet state for logout', name: 'MwaWalletProvider');
    _balance = 0.0;
    _isInitialized = false;
    _errorMessage = null;
    _isLoading = false;
    _walletAddress = null;
    _loadingState = LoadingState.idle;
    log(
      '✅ Wallet state cleared - isInitialized: $_isInitialized, walletAddress: $_walletAddress',
      name: 'MwaWalletProvider',
    );
    notifyListeners();
  }

  /// Refresh wallet balance using stored wallet address
  Future<void> refreshWalletBalance() async {
    if (_walletAddress == null) {
      log(
        'No wallet address set, cannot refresh balance',
        name: 'MwaWalletProvider',
      );
      return;
    }
    await refreshBalance(_walletAddress!);
  }

  /// Refresh wallet balance
  Future<void> refreshBalance(String walletAddress) async {
    try {
      final publicKey = solana.Ed25519HDPublicKey.fromBase58(walletAddress);
      final balanceResponse = await _client.rpcClient.getBalance(
        publicKey.toBase58(),
      );
      _balance = balanceResponse.value / solana.lamportsPerSol;
      notifyListeners();
      log('Balance: $_balance SOL', name: 'MwaWalletProvider');
    } catch (e) {
      log('Error refreshing balance: $e', name: 'MwaWalletProvider');
    }
  }

  /// Whether an earlier escrow still holds its stake on Solana. Read-only.
  ///
  /// Resolve and cancel both close the escrow account, so an account that is
  /// missing (or no longer owned by the escrow program) was already settled and
  /// there is nothing left to sign for. `null` when the network could not say;
  /// the wallet's own simulation still guards the transaction then.
  Future<bool?> escrowIsOpen(String escrowAddress) async {
    try {
      final read = _readEscrowAccount;
      final account =
          read != null
              ? await read(escrowAddress)
              : (await _client.rpcClient.getAccountInfo(
                escrowAddress,
                commitment: Commitment.confirmed,
                encoding: Encoding.base64,
              )).value;
      return escrowAccountIsOpen(account);
    } catch (e) {
      log('Escrow account read failed: $e', name: 'MwaWalletProvider');
      return null;
    }
  }

  /// An escrow is open while its account exists and the program owns it.
  static bool escrowAccountIsOpen(Account? account) =>
      account != null && account.owner == escrowProgramId;

  /// Build resolve challenge transaction for Pinocchio program
  /// NOTE: WITNESS must sign (witness is the judge)
  Future<Uint8List> buildResolveChallengeTransaction({
    required String challengeAddress,
    required String initiatorAddress,
    required String witnessAddress,
    required bool initiatorWon,
  }) async {
    log('Building resolve challenge transaction', name: 'MwaWalletProvider');
    log('Challenge: $challengeAddress', name: 'MwaWalletProvider');
    log('Initiator: $initiatorAddress', name: 'MwaWalletProvider');
    log('Witness (signer): $witnessAddress', name: 'MwaWalletProvider');
    log('Initiator won: $initiatorWon', name: 'MwaWalletProvider');

    final challengePubkey = solana.Ed25519HDPublicKey.fromBase58(
      challengeAddress,
    );
    final initiatorPubkey = solana.Ed25519HDPublicKey.fromBase58(
      initiatorAddress,
    );
    final witnessPubkey = solana.Ed25519HDPublicKey.fromBase58(witnessAddress);
    final platformPubkey = solana.Ed25519HDPublicKey.fromBase58(
      platformFeeWallet,
    );
    final programPubkey = solana.Ed25519HDPublicKey.fromBase58(escrowProgramId);

    // Build instruction data: discriminator(1) + initiator_won(1) = 2 bytes
    // Program does split_first on discriminator, so data becomes [initiator_won]
    final instructionData = Uint8List(2);
    instructionData[0] = PinocchioInstructions.resolveChallenge;
    instructionData[1] = initiatorWon ? 1 : 0;

    // Accounts order MUST match Pinocchio program (updated for witness-is-judge model):
    // [witness (signer), challenge, initiator, platform_fee_account]
    final instruction = encoder.Instruction(
      programId: programPubkey,
      accounts: [
        encoder.AccountMeta.writeable(
          pubKey: witnessPubkey,
          isSigner: true,
        ), // Witness signs (judge)
        encoder.AccountMeta.writeable(pubKey: challengePubkey, isSigner: false),
        encoder.AccountMeta.writeable(pubKey: initiatorPubkey, isSigner: false),
        encoder.AccountMeta.writeable(pubKey: platformPubkey, isSigner: false),
      ],
      data: encoder.ByteArray(instructionData),
    );

    // Get recent blockhash
    final blockhashResult = await _client.rpcClient.getLatestBlockhash();
    final blockhash = blockhashResult.value.blockhash;

    // Build message (witness is fee payer and signer)
    final message = encoder.Message.only(instruction);
    final compiledMessage = message.compile(
      recentBlockhash: blockhash,
      feePayer: witnessPubkey,
    );

    // Create SignedTx with placeholder signature for MWA
    final placeholderSignature = encoder.Signature(
      List.filled(64, 0),
      publicKey: witnessPubkey, // Witness signs
    );

    final signedTx = encoder.SignedTx(
      compiledMessage: compiledMessage,
      signatures: [placeholderSignature],
    );

    return Uint8List.fromList(signedTx.toByteArray().toList());
  }

  /// Build cancel challenge transaction for Pinocchio program
  Future<Uint8List> buildCancelChallengeTransaction({
    required String challengeAddress,
    required String initiatorAddress,
    required String witnessAddress,
  }) async {
    log('Building cancel challenge transaction', name: 'MwaWalletProvider');

    final challengePubkey = solana.Ed25519HDPublicKey.fromBase58(
      challengeAddress,
    );
    final initiatorPubkey = solana.Ed25519HDPublicKey.fromBase58(
      initiatorAddress,
    );
    final witnessPubkey = solana.Ed25519HDPublicKey.fromBase58(witnessAddress);
    final programPubkey = solana.Ed25519HDPublicKey.fromBase58(escrowProgramId);

    // Build instruction data: discriminator(1) = 1 byte
    final instructionData = Uint8List(1);
    instructionData[0] = PinocchioInstructions.cancelChallenge;

    // Accounts order MUST match Pinocchio program:
    // [initiator (signer), challenge, witness]
    // NOTE: Witness is WRITEABLE because cancel does 50/50 split
    final instruction = encoder.Instruction(
      programId: programPubkey,
      accounts: [
        encoder.AccountMeta.writeable(pubKey: initiatorPubkey, isSigner: true),
        encoder.AccountMeta.writeable(pubKey: challengePubkey, isSigner: false),
        encoder.AccountMeta.writeable(
          pubKey: witnessPubkey,
          isSigner: false,
        ), // Writeable for 50/50 split
      ],
      data: encoder.ByteArray(instructionData),
    );

    // Get recent blockhash
    final blockhashResult = await _client.rpcClient.getLatestBlockhash();
    final blockhash = blockhashResult.value.blockhash;

    // Build message
    final message = encoder.Message.only(instruction);
    final compiledMessage = message.compile(
      recentBlockhash: blockhash,
      feePayer: initiatorPubkey,
    );

    // Create SignedTx with placeholder signature for MWA
    final placeholderSignature = encoder.Signature(
      List.filled(64, 0),
      publicKey: initiatorPubkey,
    );

    final signedTx = encoder.SignedTx(
      compiledMessage: compiledMessage,
      signatures: [placeholderSignature],
    );

    return Uint8List.fromList(signedTx.toByteArray().toList());
  }

  /// Resolve a challenge (witness resolves - "Witness is Judge" model)
  /// NOTE: Only the WITNESS can resolve per updated Pinocchio program design
  Future<String?> resolveChallenge({
    required String challengeAddress,
    required String initiatorAddress,
    required bool initiatorWon,
    required BuildContext context,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      if (!authProvider.isAuthenticated) {
        throw Exception('User must be authenticated');
      }

      // The connected wallet is the WITNESS (only witness can resolve)
      final witnessAddress = authProvider.walletAddress!;

      log(
        '🔄 Resolving challenge (witness is judge):',
        name: 'MwaWalletProvider',
      );
      log('  Challenge: $challengeAddress', name: 'MwaWalletProvider');
      log('  Initiator: $initiatorAddress', name: 'MwaWalletProvider');
      log('  Witness (signer): $witnessAddress', name: 'MwaWalletProvider');
      log('  Initiator Won: $initiatorWon', name: 'MwaWalletProvider');

      // Build the transaction
      final txBytes = await buildResolveChallengeTransaction(
        challengeAddress: challengeAddress,
        initiatorAddress: initiatorAddress,
        witnessAddress: witnessAddress,
        initiatorWon: initiatorWon,
      );

      // Create MWA signing session
      final signingSession = await authProvider.createSigningSession();
      if (signingSession == null) {
        throw Exception('Failed to create signing session');
      }

      try {
        // Sign and send transaction via MWA
        final result = await signingSession.signAndSendTransactions(
          transactions: [txBytes],
        );

        if (result.signatures.isEmpty) {
          throw Exception('Transaction signing failed');
        }

        final txSignature = base58encode(
          Uint8List.fromList(result.signatures.first),
        );
        log('✅ Challenge resolved: $txSignature', name: 'MwaWalletProvider');

        await refreshBalance(witnessAddress);
        return txSignature;
      } finally {
        await signingSession.close();
      }
    } catch (e) {
      log('❌ Error resolving challenge: $e', name: 'MwaWalletProvider');
      _setError('Failed to resolve challenge: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Cancel an open challenge (challenger only, any time before it is
  /// resolved). The program splits what is in escrow 50/50 between challenger
  /// and witness, so this is not a refund. No screen offers it: the app never
  /// has, and offering it is an owner decision.
  Future<String?> cancelChallenge({
    required String challengeAddress,
    required String witnessAddress,
    required BuildContext context,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      if (!authProvider.isAuthenticated) {
        throw Exception('User must be authenticated');
      }

      final initiatorAddress = authProvider.walletAddress!;

      // Build the transaction
      final txBytes = await buildCancelChallengeTransaction(
        challengeAddress: challengeAddress,
        initiatorAddress: initiatorAddress,
        witnessAddress: witnessAddress,
      );

      // Create MWA signing session
      final signingSession = await authProvider.createSigningSession();
      if (signingSession == null) {
        throw Exception('Failed to create signing session');
      }

      try {
        // Sign and send transaction via MWA
        final result = await signingSession.signAndSendTransactions(
          transactions: [txBytes],
        );

        if (result.signatures.isEmpty) {
          throw Exception('Transaction signing failed');
        }

        final txSignature = base58encode(
          Uint8List.fromList(result.signatures.first),
        );
        log('✅ Challenge cancelled: $txSignature', name: 'MwaWalletProvider');

        await refreshBalance(initiatorAddress);
        return txSignature;
      } finally {
        await signingSession.close();
      }
    } catch (e) {
      log('❌ Error cancelling challenge: $e', name: 'MwaWalletProvider');
      _setError('Failed to cancel challenge: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Request airdrop for testing on devnet
  Future<bool> requestAirdrop(
    String walletAddress, {
    double amount = 1.0,
  }) async {
    try {
      final lamports = (amount * solana.lamportsPerSol).round();
      final pubkey = solana.Ed25519HDPublicKey.fromBase58(walletAddress);

      await _client.requestAirdrop(address: pubkey, lamports: lamports);

      // Wait a bit for confirmation
      await Future.delayed(const Duration(seconds: 2));
      await refreshBalance(walletAddress);

      log('✅ Airdrop successful: $amount SOL', name: 'MwaWalletProvider');
      return true;
    } catch (e) {
      log('❌ Airdrop failed: $e', name: 'MwaWalletProvider');
      return false;
    }
  }

  /// Transfer SOL to another address using MWA
  Future<String?> transferSol({
    required String destinationAddress,
    required double amount,
    required BuildContext context,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      if (!authProvider.isAuthenticated) {
        throw Exception('User must be authenticated');
      }

      final senderAddress = authProvider.walletAddress!;
      final lamports = (amount * solana.lamportsPerSol).round();

      // Validate destination address
      solana.Ed25519HDPublicKey destPubkey;
      try {
        destPubkey = solana.Ed25519HDPublicKey.fromBase58(destinationAddress);
      } catch (_) {
        throw Exception('Invalid destination address');
      }

      final senderPubkey = solana.Ed25519HDPublicKey.fromBase58(senderAddress);

      // Build transfer instruction
      final instruction = solana.SystemInstruction.transfer(
        fundingAccount: senderPubkey,
        recipientAccount: destPubkey,
        lamports: lamports,
      );

      // Get recent blockhash
      final blockhashResult = await _client.rpcClient.getLatestBlockhash();
      final blockhash = blockhashResult.value.blockhash;

      // Build message
      final message = solana.Message.only(instruction);
      final compiledMessage = message.compile(
        recentBlockhash: blockhash,
        feePayer: senderPubkey,
      );

      final txBytes = Uint8List.fromList(
        compiledMessage.toByteArray().toList(),
      );

      // Create MWA signing session
      final signingSession = await authProvider.createSigningSession();
      if (signingSession == null) {
        throw Exception('Failed to create signing session');
      }

      try {
        // Sign and send transaction via MWA
        final result = await signingSession.signAndSendTransactions(
          transactions: [txBytes],
        );

        if (result.signatures.isEmpty) {
          throw Exception('Transaction signing failed');
        }

        final txSignature = base58encode(
          Uint8List.fromList(result.signatures.first),
        );
        log(
          '✅ SOL transfer successful: $txSignature',
          name: 'MwaWalletProvider',
        );

        await refreshBalance(senderAddress);
        return txSignature;
      } finally {
        await signingSession.close();
      }
    } catch (e) {
      log('❌ Error transferring SOL: $e', name: 'MwaWalletProvider');
      _setError('Failed to transfer SOL: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }
}
