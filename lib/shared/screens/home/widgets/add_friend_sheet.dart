import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart'
    show visibleDisplayName, visibleHandle;
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/person_finder.dart';
import 'package:chumbucket/features/people/presentation/widgets/people_format.dart';
import 'package:chumbucket/shared/models/friend_identifier.dart';
import 'package:chumbucket/shared/services/add_friend_service.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

/// Add a friend: type who, see who it is, then add them.
///
/// Adding a friend follows a real Chumbucket person (`people.find`, then
/// `people.follow`), keyed by the signed-in session — wallet, Google or X
/// alike. Nothing is added before the card is confirmed, and no wallet is
/// ever asked to sign. Someone who isn't on Chumbucket yet gets an invite
/// link; nothing is saved for them.
///
/// Signed out, this opens sign-in instead.
Future<void> showAddFriendSheet(
  BuildContext context, {
  required VoidCallback onFriendAdded,
  AddFriendService? service,
}) {
  final friends =
      service ?? CallsAddFriendService(context.read<CallsProvider?>());
  if (!friends.isSignedIn) {
    requestCallSignIn(context);
    return Future<void>.value();
  }
  return showChumbucketWavySheet<void>(
    context: context,
    builder:
        (_) => AddFriendSheet(
          service: friends,
          onFriendAdded: onFriendAdded,
          onSignIn: () => requestCallSignIn(context),
        ),
  );
}

enum _Stage { input, results, added, unfollowed }

class AddFriendSheet extends StatefulWidget {
  const AddFriendSheet({
    super.key,
    required this.onFriendAdded,
    this.service,
    this.onSignIn,
  });

  final VoidCallback onFriendAdded;

  /// Defaults to the app's calls session.
  final AddFriendService? service;

  /// Opens sign-in once this sheet has closed (the session ran out).
  final VoidCallback? onSignIn;

  @override
  State<AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<AddFriendSheet> {
  final _input = TextEditingController();
  late final AddFriendService _service =
      widget.service ?? CallsAddFriendService(context.read<CallsProvider?>());

  _Stage _stage = _Stage.input;
  FriendIdentifier? _typed;
  FriendIdentifier? _searched;
  PersonLookup? _lookup;
  PersonMatch? _done;
  bool _busy = false;
  String? _busyPersonId;
  String? _error;
  bool _needsSignIn = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {
      _typed = FriendIdentifier.parse(value);
      _error = null;
      _needsSignIn = false;
    });
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      switch (error) {
        case CallsSignedOutException():
          _needsSignIn = true;
          _error = 'Sign in to your Chumbucket account to add friends.';
        case PersonFinderUnavailable():
          _error =
              'Adding friends isn’t available on the server yet. Please try '
              'again later.';
        case CallsOfflineException():
          _error = 'You’re offline. Check your connection and try again.';
        case CallsException(:final message):
          _error = message;
        default:
          _error = 'That didn’t finish. Check your connection and try again.';
      }
    });
  }

  Future<void> _find() async {
    final target = FriendIdentifier.parse(_input.text);
    if (target == null || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _needsSignIn = false;
    });
    try {
      var query = target.query;
      if (target.kind == FriendIdentifierKind.domain) {
        String? wallet;
        try {
          wallet = await _service.resolveName(target.value);
        } catch (_) {
          /* Said below. */
        }
        if (!mounted) return;
        if (wallet == null || !FriendIdentifier.isWallet(wallet)) {
          setState(
            () =>
                _error =
                    'We couldn’t find a wallet for ${target.value}. Check the '
                    'name, or paste their wallet or X handle.',
          );
          return;
        }
        query = wallet;
      }
      final lookup = await _service.find(query!);
      if (!mounted) return;
      setState(() {
        _searched = target;
        _lookup = lookup;
        _stage = _Stage.results;
      });
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setFollowing(PersonMatch match, bool following) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyPersonId = match.person.id;
      _error = null;
      _needsSignIn = false;
    });
    try {
      final confirmed = await _service.setFollowing(match.person.id, following);
      if (!mounted) return;
      setState(() {
        _done = match.copyWith(viewerIsFollowing: confirmed);
        _stage = confirmed ? _Stage.added : _Stage.unfollowed;
      });
      if (confirmed) widget.onFriendAdded();
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyPersonId = null;
        });
      }
    }
  }

  Future<void> _invite() async {
    final handle =
        _lookup?.notOnChumbucket?.xHandle ??
        (_searched?.canBeXHandle == true ? _searched!.value : null);
    final hello = handle == null ? 'Hey' : 'Hey @$handle';
    try {
      await _service.share(
        '$hello, I’m making calls on Chumbucket. Join me so we can follow '
        'each other’s calls: ${_service.inviteLink}',
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Sharing didn’t open. Please try again.');
      }
    }
  }

  void _searchAgain() => setState(() {
    _stage = _Stage.input;
    _lookup = null;
    _done = null;
    _error = null;
    _needsSignIn = false;
  });

  void _addAnother() {
    _input.clear();
    setState(() {
      _typed = null;
      _searched = null;
    });
    _searchAgain();
  }

  Future<void> _signIn() async {
    final onSignIn = widget.onSignIn;
    // Close this sheet first: maybePop decides after a frame, and opening
    // sign-in before then would leave this sheet under it.
    await Navigator.of(context).maybePop();
    onSignIn?.call();
  }

  String get _title {
    switch (_stage) {
      case _Stage.input:
        return 'Add a friend';
      case _Stage.added:
        return 'Friend added';
      case _Stage.unfollowed:
        return 'Unfollowed';
      case _Stage.results:
        final lookup = _lookup!;
        if (lookup.matches.length > 1) return 'Which one is them?';
        if (lookup.matches.length == 1) return 'Is this them?';
        // Short: a long word in a 2x title would break mid-word. The card
        // carries the full "Not on Chumbucket yet".
        return lookup.notOnChumbucket != null ? 'Not here yet' : 'No one found';
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallJourneySheet(
      title: _title,
      busy: _busy,
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: switch (_stage) {
          _Stage.input => _inputStage(),
          _Stage.results => _resultsStage(),
          _Stage.added || _Stage.unfollowed => _doneStage(),
        },
      ),
    );
  }

  List<Widget> _errorLine() => [
    if (_error != null) ...[
      const SizedBox(height: 16),
      Semantics(
        liveRegion: true,
        child: Text(
          _error!,
          key: const Key('add-friend-error'),
          style: callJourneyBody().copyWith(color: AppColors.error),
        ),
      ),
      if (_needsSignIn) ...[
        const SizedBox(height: 8),
        ChumbucketTextAction(label: 'Sign in', onPressed: _signIn),
      ],
    ],
  ];

  // ── 1. who ────────────────────────────────────────────────────────────────

  List<Widget> _inputStage() {
    final typed = _typed;
    final empty = _input.text.trim().isEmpty;
    final hint = switch (typed?.kind) {
      null =>
        empty
            ? 'Also works with an X profile link, a wallet or a .skr name.'
            : 'Enter an X handle, a Chumbucket @username, an X profile link '
                'or a wallet.',
      FriendIdentifierKind.xLink => 'X account @${typed!.value}',
      FriendIdentifierKind.handle =>
        typed!.canBeXHandle
            ? 'X handle or Chumbucket @username: @${typed.value}'
            : 'Chumbucket @username: @${typed.value}',
      FriendIdentifierKind.wallet => 'Solana wallet ${typed!.label}',
      FriendIdentifierKind.domain => 'Wallet name ${typed!.value}',
    };
    return [
      Text(
        'Type their X handle or Chumbucket @username. You’ll see who it is '
        'before anything is added.',
        style: callJourneyBody(),
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('friend-identifier'),
        controller: _input,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        onSubmitted: (_) => _find(),
        decoration: const InputDecoration(
          labelText: 'X handle, @username or wallet',
          hintText: '@username',
        ),
      ),
      const SizedBox(height: 8),
      // Not a live region: it changes on every keystroke, and announcing each
      // change would talk over someone typing. It is read in order after the
      // field; the result of Find is what gets announced.
      Text(
        hint,
        key: const Key('friend-identifier-hint'),
        style: callJourneyBody(12).copyWith(
          color:
              typed == null && !empty
                  ? AppColors.pinkInk
                  : AppColors.textSecondary,
        ),
      ),
      ..._errorLine(),
      const SizedBox(height: 20),
      ChumbucketPrimaryButton(
        label: 'Find',
        busy: _busy,
        busyLabel: 'Looking…',
        onPressed: typed == null ? null : _find,
      ),
      const SizedBox(height: 12),
      Text(
        'Adding a friend follows them. No wallet signature needed.',
        textAlign: TextAlign.center,
        style: callJourneyBody(12),
      ),
    ];
  }

  // ── 2. is this them? ─────────────────────────────────────────────────────

  List<Widget> _resultsStage() {
    final lookup = _lookup!;
    final matches = lookup.matches;
    if (matches.isEmpty) return _nobodyStage(lookup);
    if (matches.length == 1) {
      final match = matches.single;
      return [
        FriendMatchCard(match: match),
        const SizedBox(height: 16),
        _singleExplanation(match),
        ..._errorLine(),
        const SizedBox(height: 20),
        ..._matchActions(match, single: true),
      ];
    }
    return [
      Text(
        '${matches.length} people match ${_searched?.label ?? 'that'}. Add '
        'the one you know.',
        style: callJourneyBody(),
      ),
      const SizedBox(height: 16),
      for (final match in matches) ...[
        FriendMatchCard(match: match),
        const SizedBox(height: 12),
        ..._matchActions(match, single: false, name: _actionName(match)),
        const SizedBox(height: 16),
      ],
      ..._errorLine(),
      const SizedBox(height: 4),
      ChumbucketTextAction(
        label: 'None of these',
        color: AppColors.textSecondary,
        onPressed: _busy ? null : _searchAgain,
      ),
    ];
  }

  Widget _singleExplanation(PersonMatch match) {
    final name = friendName(match);
    final text =
        match.isViewer
            ? 'That’s your own account.'
            : match.isFollowing
            ? 'You already follow $name. Their calls are in your Following '
                'feed.'
            : 'Adding $name follows them: their calls show up in your '
                'Following feed.';
    return Text(text, style: callJourneyBody());
  }

  /// What an action button calls a match when several are listed: their
  /// name, or — when another match shares it ("Irfan" on X and "Irfan" by
  /// @username) — the handle that tells them apart, so no two buttons (and
  /// no two screen-reader labels) say the same thing.
  String _actionName(PersonMatch match) {
    final name = friendName(match);
    final shared = _lookup!.matches.where((m) => friendName(m) == name).length;
    if (shared < 2) return name;
    final handle = visibleHandle(match.person.handle);
    if (handle != null) return '@$handle';
    return match.xHandle != null ? '@${match.xHandle} on X' : name;
  }

  List<Widget> _matchActions(
    PersonMatch match, {
    required bool single,
    String? name,
  }) {
    final busyHere = _busy && _busyPersonId == match.person.id;
    name ??= friendName(match);
    if (match.isViewer) {
      return [
        if (single)
          ChumbucketPrimaryButton(
            label: 'Search again',
            onPressed: _busy ? null : _searchAgain,
          ),
      ];
    }
    if (match.isFollowing) {
      return [
        if (single) ...[
          ChumbucketPrimaryButton(
            label: 'Done',
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: 4),
        ],
        ChumbucketTextAction(
          label:
              busyHere
                  ? 'Unfollowing…'
                  : single
                  ? 'Unfollow'
                  : 'Unfollow $name',
          color: AppColors.textSecondary,
          onPressed: _busy ? null : () => _setFollowing(match, false),
        ),
      ];
    }
    return [
      ChumbucketPrimaryButton(
        key: ValueKey('add-friend-${match.person.id}'),
        label: single ? 'Add friend' : 'Add $name',
        busy: busyHere,
        busyLabel: 'Adding…',
        onPressed: _busy ? null : () => _setFollowing(match, true),
      ),
      if (single) ...[
        const SizedBox(height: 4),
        ChumbucketTextAction(
          label: 'Not them',
          color: AppColors.textSecondary,
          onPressed: _busy ? null : _searchAgain,
        ),
      ],
    ];
  }

  List<Widget> _nobodyStage(PersonLookup lookup) {
    final notHere = lookup.notOnChumbucket;
    final searched = _searched;
    final what = switch (searched?.kind) {
      FriendIdentifierKind.wallet => 'that wallet',
      FriendIdentifierKind.domain => searched!.value,
      _ => searched?.label ?? 'that',
    };
    return [
      if (notHere != null) ...[
        NotOnChumbucketCard(person: notHere),
        const SizedBox(height: 16),
      ],
      Semantics(
        liveRegion: true,
        child: Text(
          notHere != null
              ? 'No one on Chumbucket uses @${notHere.xHandle} yet. Invite '
                  'them, then add them once they join.'
              : 'No one on Chumbucket uses $what yet. Check it, or invite '
                  'them to join.',
          style: callJourneyBody(),
        ),
      ),
      ..._errorLine(),
      const SizedBox(height: 20),
      ChumbucketPrimaryButton(
        label:
            notHere != null ? 'Invite @${notHere.xHandle}' : 'Invite a friend',
        onPressed: _busy ? null : _invite,
      ),
      const SizedBox(height: 4),
      ChumbucketTextAction(
        label: 'Search again',
        color: AppColors.textSecondary,
        onPressed: _busy ? null : _searchAgain,
      ),
    ];
  }

  // ── 3. done ───────────────────────────────────────────────────────────────

  List<Widget> _doneStage() {
    final match = _done!;
    final name = friendName(match);
    final added = _stage == _Stage.added;
    return [
      FriendMatchCard(match: match),
      const SizedBox(height: 16),
      Semantics(
        liveRegion: true,
        child: Text(
          added
              ? 'You’re following $name. Their calls show up in your '
                  'Following feed, and they’re listed under Following.'
              : 'You no longer follow $name.',
          style: callJourneyBody(16),
        ),
      ),
      const SizedBox(height: 24),
      ChumbucketPrimaryButton(
        label: 'Done',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      if (added) ...[
        const SizedBox(height: 4),
        ChumbucketTextAction(
          label: 'Add another friend',
          color: AppColors.textSecondary,
          onPressed: _addAnother,
        ),
      ],
    ];
  }
}

/// Their own display name, or null. The server falls back to the handle when
/// an account has no name (`full_name ?? handle`), and a "name" that only
/// repeats the @username is not a name: the card says "@name" once instead.
String? _ownName(PersonCard p) {
  final name = visibleDisplayName(p.displayName);
  final handle = visibleHandle(p.handle);
  if (name == null) return null;
  // Exactly the handle, as the fallback writes it. "Irfan" beside @irfan is
  // a name someone chose, and stays.
  if (handle != null && (name == handle || name == '@$handle')) return null;
  return name;
}

/// The name a card leads with: their display name, else their @username,
/// else their X handle. A placeholder is never shown as a name.
String friendName(PersonMatch match) {
  final p = match.person;
  final handle = visibleHandle(p.handle);
  return _ownName(p) ??
      (handle != null ? '@$handle' : null) ??
      (match.xHandle != null ? '@${match.xHandle}' : 'this person');
}

/// The initials a card draws when no picture loads: from the same name the
/// card leads with, so a placeholder (`user-1a2b3c4d`) never becomes "U".
String friendInitials(PersonMatch match) {
  final p = match.person;
  final name = _ownName(p) ?? visibleHandle(p.handle) ?? match.xHandle;
  if (name == null) return '?';
  final parts = name.trim().split(RegExp(r'\s+'));
  final first = parts.first.characters.take(1).toString();
  if (parts.length < 2) return first.isEmpty ? '?' : first;
  return '$first${parts.last.characters.take(1)}';
}

/// Who a match is: their real picture, name, @username, X handle and record.
class FriendMatchCard extends StatelessWidget {
  const FriendMatchCard({super.key, required this.match});

  final PersonMatch match;

  @override
  Widget build(BuildContext context) {
    final p = match.person;
    final handle = visibleHandle(p.handle);
    final name = friendName(match);
    final record = PeopleFormat.recordShort(p.record);
    final status =
        match.isViewer
            ? 'You'
            : match.isFollowing
            ? 'Following'
            : null;
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 21;
    final align = stacked ? TextAlign.center : TextAlign.start;
    final details = Column(
      crossAxisAlignment:
          stacked ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          name,
          textAlign: align,
          style: AppTextStyles.marketRowQuestion.copyWith(fontSize: 18),
        ),
        if (handle != null && '@$handle' != name) ...[
          const SizedBox(height: 2),
          Text(
            '@$handle on Chumbucket',
            textAlign: align,
            style: callJourneyBody().copyWith(color: AppColors.textPrimary),
          ),
        ],
        if (match.xHandle != null) ...[
          const SizedBox(height: 2),
          Text(
            '@${match.xHandle} on X',
            textAlign: align,
            style: callJourneyBody(),
          ),
        ],
        const SizedBox(height: 6),
        Text(record, textAlign: align, style: callJourneyBody(13)),
        if (status != null) ...[
          const SizedBox(height: 8),
          _StatusPill(label: status),
        ],
      ],
    );
    return Semantics(
      container: true,
      label: [
        name,
        if (handle != null && '@$handle' != name) '@$handle on Chumbucket',
        if (match.xHandle != null) '@${match.xHandle} on X',
        record,
        if (match.isViewer) 'This is you',
        if (match.isFollowing) 'You follow them',
      ].join(', '),
      excludeSemantics: true,
      child: _CardFrame(
        stacked: stacked,
        picture: FriendPicture(
          sources: match.pictures,
          initials: friendInitials(match),
          size: 64,
        ),
        details: details,
      ),
    );
  }
}

/// An X handle nobody on Chumbucket has: their public X picture when the
/// server found one (initials otherwise), clearly labelled.
class NotOnChumbucketCard extends StatelessWidget {
  const NotOnChumbucketCard({super.key, required this.person});

  final NotOnChumbucket person;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 21;
    final align = stacked ? TextAlign.center : TextAlign.start;
    return Semantics(
      container: true,
      label: '@${person.xHandle} on X, not on Chumbucket yet',
      excludeSemantics: true,
      child: _CardFrame(
        stacked: stacked,
        picture: FriendPicture(
          sources: [if (person.xAvatarUrl != null) person.xAvatarUrl!],
          initials: person.xHandle.substring(0, 1),
          size: 64,
        ),
        details: Column(
          crossAxisAlignment:
              stacked ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text(
              '@${person.xHandle}',
              textAlign: align,
              style: AppTextStyles.marketRowQuestion.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 2),
            Text('On X', textAlign: align, style: callJourneyBody()),
            const SizedBox(height: 8),
            const _StatusPill(label: 'Not on Chumbucket yet'),
          ],
        ),
      ),
    );
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({
    required this.stacked,
    required this.picture,
    required this.details,
  });

  /// Above ~1.5x text the picture sits above the words rather than
  /// squeezing them.
  final bool stacked;
  final Widget picture;
  final Widget details;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.outlineVariant),
    ),
    child:
        stacked
            ? Column(children: [picture, const SizedBox(height: 12), details])
            : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                picture,
                const SizedBox(width: 16),
                Expanded(child: details),
              ],
            ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: callJourneyBody(
        12,
      ).copyWith(color: AppColors.pinkInk, fontWeight: FontWeight.w600),
    ),
  );
}

/// A person's real picture: the first of [sources] that loads (an https
/// picture or a bundled avatar), over their initials. Nothing stands in for
/// a picture that does not load — the initials stay.
class FriendPicture extends StatelessWidget {
  const FriendPicture({
    super.key,
    required this.sources,
    required this.initials,
    this.size = 64,
  });

  final List<String> sources;
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pixels = (size * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 3))
        .ceil()
        .clamp(1, 512);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: AppColors.primaryContainer,
                child: Center(
                  // A picture of the name, not reading text: the name is
                  // beside it, at full scale.
                  child: MediaQuery.withNoTextScaling(
                    child: Text(
                      initials.toUpperCase(),
                      style: AppTextStyles.marketRowQuestion.copyWith(
                        fontSize: size * .36,
                        color: AppColors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
              _picture(0, pixels),
            ],
          ),
        ),
      ),
    );
  }

  Widget _picture(int index, int pixels) {
    if (index >= sources.length) return const SizedBox.shrink();
    final source = sources[index];
    final ImageProvider base =
        source.startsWith('assets/')
            ? AssetImage(source)
            : NetworkImage(source);
    return Image(
      key: ValueKey('friend-picture-$source'),
      image: ResizeImage(base, width: pixels, policy: ResizeImagePolicy.fit),
      fit: BoxFit.cover,
      width: size,
      height: size,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _picture(index + 1, pixels),
    );
  }
}
