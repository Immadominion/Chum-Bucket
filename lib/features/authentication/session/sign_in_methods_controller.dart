/// Settings → Sign-in methods, as a [ChangeNotifier].
///
/// Reads the account's sign-in methods from the BFF and drives every change:
/// linking X/Google (Supabase manual linking), linking a wallet (its SIWS
/// challenge), unlinking, and — when Supabase can't link because the identity
/// or wallet is on another account — the move: the app's account issues a
/// ticket, the person proves the other side with a sign-in made only for that
/// (the app's own session never changes), sees what would happen, confirms.
///
/// The ticket and the proof's token live only in this object's memory and
/// the proof is released whatever happens.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart';

import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/sign_in_link_port.dart';
import 'package:chumbucket/features/authentication/session/sign_in_methods.dart';
import 'package:chumbucket/features/authentication/session/solana_sign_in.dart';

/// Where a move stands.
enum MoveStage { conflict, proving, preview, moving }

class SignInMove {
  const SignInMove._(
    this.stage,
    this.method, {
    this.preview,
    this.ticket,
    this.proof,
  });

  final MoveStage stage;
  final SignInMethodKind method;
  final LinkPreview? preview;
  final String? ticket;
  final String? proof;

  @override
  String toString() => 'SignInMove(${stage.name}, ${method.name})';
}

class SignInMethodsController extends ChangeNotifier {
  SignInMethodsController({
    required Future<String?> Function() accessToken,
    required SessionBffClient bff,
    required SignInLinkPort port,
    this.wallet,
    bool ownsBff = false,
  }) : _token = accessToken,
       _bff = bff,
       _port = port,
       _ownsBff = ownsBff;

  final bool _ownsBff;

  final Future<String?> Function() _token;
  final SessionBffClient _bff;
  final SignInLinkPort _port;

  /// The wallet this phone can sign with (Mobile Wallet Adapter), or null.
  final SolanaSignInWallet? wallet;

  SignInMethods? _methods;
  String? _line;
  String? _busy;
  SignInMove? _move;
  bool _disposed = false;

  SignInMethods? get methods => _methods;

  /// One short line about the last thing that happened, or null.
  String? get line => _line;

  /// The row id (or kind name) something is happening to.
  String? get busy => _busy;
  SignInMove? get move => _move;

  /// Link is offered for these: the kinds with no row, and a wallet only
  /// where this phone has one to sign with.
  List<SignInMethodKind> get linkable => [
    for (final kind in _methods?.missing ?? const <SignInMethodKind>[])
      if (kind != SignInMethodKind.wallet || wallet != null) kind,
  ];

  void _set({
    SignInMethods? methods,
    Object? line = _keep,
    Object? busy = _keep,
    Object? move = _keep,
  }) {
    if (_disposed) return;
    if (methods != null) _methods = methods;
    if (line != _keep) _line = line as String?;
    if (busy != _keep) _busy = busy as String?;
    if (move != _keep) _move = move as SignInMove?;
    notifyListeners();
  }

  static const _keep = Object();

  static String _copyOf(Object error) => switch (error) {
    SignInLinkStopped(:final code) => signInLinkCopy(code),
    SessionException(:final error) => error.message,
    _ => signInLinkCopy('network'),
  };

  Future<String> _requireToken() async {
    final token = await _token();
    if (token == null) throw const SignInLinkStopped('cancelled');
    return token;
  }

  Future<void> load() async {
    try {
      final token = await _requireToken();
      _set(methods: await _bff.signInMethods(token));
    } catch (e) {
      _set(line: _copyOf(e));
    }
  }

  /// X or Google onto this account. On "already on another account", the move.
  Future<void> linkProvider(SignInMethodKind kind) async {
    _set(line: null, busy: kind.name);
    try {
      final result = _port.providerLinkResult();
      await _port.startProviderLink(kind);
      final code = await result;
      if (code == 'identity_already_exists') {
        _set(busy: null, move: SignInMove._(MoveStage.conflict, kind));
        return;
      }
      _set(
        busy: null,
        line: code == null ? '${kind.title} linked' : signInLinkCopy(code),
      );
      if (code == null) await load();
    } catch (e) {
      _set(busy: null, line: _copyOf(e));
    }
  }

  /// This phone's wallet onto this account, with its SIWS challenge.
  Future<void> linkWallet() async {
    final signer = wallet;
    if (signer == null) return;
    _set(line: null, busy: SignInMethodKind.wallet.name);
    try {
      final token = await _requireToken();
      final address = await signer.connect();
      final proof = await _bff.requestWalletLink(token, address: address);
      // The wallet signs exactly the server's message; the BFF takes base58.
      final signature = base58encode(
        base64Url.decode(await signer.sign(proof.message)),
      );
      await _bff.linkWallet(
        token,
        address: address,
        proof: proof,
        signature: signature,
      );
      _set(busy: null, line: 'Wallet linked');
      await load();
    } on SessionException catch (e) {
      if (e.error.code == 'WALLET_OWNED_BY_ANOTHER_USER' ||
          e.error.code == 'WALLET_REQUIRES_TRANSFER') {
        _set(
          busy: null,
          move: const SignInMove._(MoveStage.conflict, SignInMethodKind.wallet),
        );
      } else {
        _set(busy: null, line: e.error.message);
      }
    } catch (e) {
      _set(busy: null, line: _copyOf(e));
    }
  }

  /// Prove the other side of a move, then show what would happen.
  Future<void> prove() async {
    final move = _move;
    if (move == null || move.stage != MoveStage.conflict) return;
    final method = move.method;
    _set(line: null, move: SignInMove._(MoveStage.proving, method));
    String? proof;
    try {
      final token = await _requireToken();
      final issued = _bff.startSignInLink(token, method: method);
      issued.ignore(); // awaited below, after the proof
      if (method == SignInMethodKind.wallet) {
        final signer = wallet;
        if (signer == null) throw const SignInLinkStopped('cancelled');
        proof = await _port.proveWallet(signer);
      } else {
        proof = await _port.proveProvider(method);
      }
      final ticket = await issued;
      final preview = await _bff.previewSignInLink(
        token,
        otherAccessToken: proof,
        ticket: ticket,
      );
      if (_disposed) {
        unawaited(_port.release(proof));
        return;
      }
      _set(
        move: SignInMove._(
          MoveStage.preview,
          method,
          preview: preview,
          ticket: ticket,
          proof: proof,
        ),
      );
    } catch (e) {
      if (proof != null) unawaited(_port.release(proof));
      _set(move: null, line: _copyOf(e));
    }
  }

  /// Do what the preview said.
  Future<void> confirm() async {
    final move = _move;
    final ticket = move?.ticket;
    final proof = move?.proof;
    final preview = move?.preview;
    if (move == null ||
        move.stage != MoveStage.preview ||
        ticket == null ||
        proof == null ||
        preview == null) {
      return;
    }
    _set(
      move: SignInMove._(
        MoveStage.moving,
        move.method,
        preview: preview,
        ticket: ticket,
        proof: proof,
      ),
    );
    try {
      final token = await _requireToken();
      final outcome = await _bff.completeSignInLink(
        token,
        otherAccessToken: proof,
        ticket: ticket,
      );
      _set(
        move: null,
        line:
            outcome == 'folded'
                ? '${preview.from?.display ?? 'That account'} moved here'
                : '${move.method.title} linked',
      );
      await load();
    } catch (e) {
      _set(move: null, line: _copyOf(e));
    } finally {
      unawaited(_port.release(proof));
    }
  }

  /// Leave the move; nothing changes.
  void cancelMove() {
    final proof = _move?.proof;
    if (proof != null) unawaited(_port.release(proof));
    _set(move: null);
  }

  Future<void> unlink(SignInMethodRow row) async {
    final route = row.unlink;
    if (route == null) return;
    _set(line: null, busy: row.id);
    try {
      final identity = route.nativeIdentityId;
      if (identity != null) {
        await _port.unlinkIdentity(identity);
      } else {
        await _bff.unlinkSignIn(await _requireToken(), ref: route.serverRef!);
      }
      _set(busy: null, line: '${row.kind.title} unlinked');
      await load();
    } catch (e) {
      _set(busy: null, line: _copyOf(e));
    }
  }

  @override
  void dispose() {
    final proof = _move?.proof;
    if (proof != null) unawaited(_port.release(proof));
    _disposed = true;
    if (_ownsBff) _bff.close();
    super.dispose();
  }
}
