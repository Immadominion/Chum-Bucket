import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/shared/models/friend_identifier.dart';
import 'package:chumbucket/shared/services/friend_connection_service.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

Future<void> showAddFriendSheet(
  BuildContext context, {
  required VoidCallback onFriendAdded,
}) => showChumbucketWavySheet<void>(
  context: context,
  builder: (_) => AddFriendSheet(onFriendAdded: onFriendAdded),
);

class AddFriendSheet extends StatefulWidget {
  const AddFriendSheet({super.key, required this.onFriendAdded, this.service});
  final VoidCallback onFriendAdded;
  final FriendConnectionService? service;
  @override
  State<AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<AddFriendSheet> {
  final _identifier = TextEditingController();
  final _name = TextEditingController();
  Timer? _debounce;
  int _revision = 0;
  FriendIdentifier? _target;
  String? _wallet, _error, _outcome;
  bool _resolving = false, _busy = false;
  late final FriendConnectionService _service =
      widget.service ??
      ExistingFriendConnectionService(
        context.read<MwaAuthProvider>(),
        () => context.read<ArenaProvider>(),
      );

  @override
  void dispose() {
    _debounce?.cancel();
    _identifier.dispose();
    _name.dispose();
    super.dispose();
  }

  void _detect(String input) {
    _debounce?.cancel();
    final revision = ++_revision;
    final target = FriendIdentifier.parse(input);
    setState(() {
      _target = target;
      _wallet =
          target?.kind == FriendIdentifierKind.wallet ? target!.value : null;
      _error =
          input.trim().isNotEmpty && target == null
              ? 'Enter a Solana wallet, X handle, or supported name such as you.skr.'
              : null;
      _resolving = target?.kind == FriendIdentifierKind.domain;
    });
    if (!_resolving) return;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      String? address;
      try {
        address = await _service.resolveDomain(target!.value);
      } catch (_) {
        /* Refusal below. */
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        _resolving = false;
        _wallet =
            address != null && FriendIdentifier.isWallet(address)
                ? address
                : null;
        _error =
            _wallet == null
                ? 'Could not find that name. Check it or paste their wallet.'
                : null;
      });
    });
  }

  bool get _canSubmit =>
      !_busy &&
      !_resolving &&
      _target != null &&
      (_target!.kind == FriendIdentifierKind.xHandle || _wallet != null);

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final target = _target!;
    final owner = _service.currentWallet;
    if (owner == null) {
      setState(() => _error = 'Connect your existing wallet to add a friend.');
      return;
    }
    final name =
        _name.text.trim().isEmpty ? target.suggestedName : _name.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var address = _wallet;
      if (target.kind == FriendIdentifierKind.xHandle) {
        final result = await _service.addHandle(target.value);
        if (!mounted) return;
        if (_service.currentWallet != owner) {
          setState(
            () =>
                _error =
                    'Your account changed. Review the request and try again.',
          );
          return;
        }
        if (!result.alreadyResolved) {
          setState(
            () =>
                _outcome =
                    '@${target.value} saved as pending. No linked wallet was found, and no notification has been sent to them.',
          );
          return;
        }
        address = result.resolvedWalletAddress;
      }
      if (address == null || !FriendIdentifier.isWallet(address)) {
        setState(() => _error = 'No valid wallet was found for this person.');
        return;
      }
      if (address == owner) {
        setState(() => _error = 'That’s your own account.');
        return;
      }
      final added = await _service.addWallet(
        owner: owner,
        name: name,
        address: address,
      );
      if (!mounted) return;
      if (_service.currentWallet != owner) {
        setState(
          () =>
              _error =
                  'Your account changed. Reopen Friends to check the result.',
        );
        return;
      }
      if (added) {
        setState(() => _outcome = '$name added to your friends.');
        widget.onFriendAdded();
      } else {
        setState(
          () =>
              _error =
                  'Could not add this friend. Your details are still here; try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error =
                  'The request didn’t finish. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHandle = _target?.kind == FriendIdentifierKind.xHandle;
    return CallJourneySheet(
      title: 'Add a friend',
      heightFactor: .72,
      busy: _busy,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (_outcome != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(_outcome!, style: callJourneyBody(16)),
            ),
            const SizedBox(height: 24),
            CallJourneyButton(
              label: 'Done',
              primary: true,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ] else ...[
            Text('Find your people.', style: callJourneyHeading(context, 20)),
            const SizedBox(height: 8),
            Text(
              'Paste their wallet or type their X handle. We’ll recognise it.',
              style: callJourneyBody(),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('friend-identifier'),
              controller: _identifier,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: _detect,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Wallet or X handle',
                hintText: '@username or wallet address',
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _resolving
                    ? 'Looking up ${_target!.value}…'
                    : switch (_target?.kind) {
                      FriendIdentifierKind.wallet => 'Solana wallet recognised',
                      FriendIdentifierKind.domain =>
                        _wallet == null
                            ? 'Name not resolved'
                            : 'Wallet found for ${_target!.value}',
                      FriendIdentifierKind.xHandle =>
                        'X handle · @${_target!.value}',
                      null => 'Also accepts X profile links and .skr names.',
                    },
                style: callJourneyBody(12),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('friend-name'),
              controller: _name,
              enabled: !_busy,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'How you know them',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: callJourneyBody().copyWith(color: AppColors.error),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (isHandle) ...[
              Text(
                'Your wallet confirms this request with a message, not a transaction. If no wallet is linked, the handle stays pending.',
                style: callJourneyBody(12),
              ),
              const SizedBox(height: 16),
            ],
            CallJourneyButton(
              label:
                  isHandle ? 'Continue with @${_target!.value}' : 'Add friend',
              primary: true,
              busy: _busy,
              onPressed: _canSubmit ? _submit : null,
            ),
          ],
        ],
      ),
    );
  }
}
