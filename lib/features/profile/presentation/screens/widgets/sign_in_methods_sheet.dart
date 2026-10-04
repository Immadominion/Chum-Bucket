import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/sign_in_link_port.dart';
import 'package:chumbucket/features/authentication/session/sign_in_methods.dart';
import 'package:chumbucket/features/authentication/session/sign_in_methods_controller.dart';
import 'package:chumbucket/features/authentication/session/solana_sign_in.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Settings → Sign-in methods: signed in with, then wallet, X and Google —
/// linked (with handle or short address), Link, or unlink where the server
/// allows it. A move (the identity or wallet is on another account) happens
/// right here, after the person proves the other side.
Future<void> showSignInMethodsSheet(BuildContext context) {
  final session = context.read<ChumbucketSession>();
  final mwa = context.read<MwaAuthProvider?>();
  return showChumbucketWavySheet<void>(
    context: context,
    builder:
        (_) => ChangeNotifierProvider<SignInMethodsController>(
          create:
              (_) => SignInMethodsController(
                accessToken: session.bffAuthToken,
                bff: SessionBffClient(),
                ownsBff: true,
                port: SupabaseSignInLinkPort(),
                // Mobile Wallet Adapter is Android's; elsewhere no wallet signs here.
                wallet:
                    mwa != null && Platform.isAndroid
                        ? MwaSolanaSignInWallet(mwa)
                        : null,
              )..load(),
          child: const SignInMethodsSheet(),
        ),
  );
}

/// Settings' Sign-in methods row, only when the server says linking is on
/// for THIS account (`auth.signInMethods`' `linking`; it may be on for admins
/// only). Off, or not known: nothing at all, exactly the app before linking.
class SignInMethodsEntry extends StatefulWidget {
  const SignInMethodsEntry({super.key, required this.child, this.load});

  /// The row itself.
  final Widget child;

  /// Reads the account's sign-in methods; tests replace it.
  final Future<SignInMethods?> Function()? load;

  @override
  State<SignInMethodsEntry> createState() => _SignInMethodsEntryState();
}

class _SignInMethodsEntryState extends State<SignInMethodsEntry> {
  bool _linking = false;

  @override
  void initState() {
    super.initState();
    final load = widget.load ?? _read(context.read<ChumbucketSession?>());
    load().then(
      (methods) {
        if (mounted && methods?.linking == true) {
          setState(() => _linking = true);
        }
      },
      onError: (_) {
        // Not known is off.
      },
    );
  }

  static Future<SignInMethods?> Function() _read(ChumbucketSession? session) =>
      () async {
        if (session == null || !session.isReady) return null;
        final token = await session.bffAuthToken();
        if (token == null) return null;
        final bff = SessionBffClient();
        try {
          return await bff.signInMethods(token);
        } finally {
          bff.close();
        }
      };

  @override
  Widget build(BuildContext context) =>
      _linking ? widget.child : const SizedBox.shrink();
}

class SignInMethodsSheet extends StatelessWidget {
  const SignInMethodsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SignInMethodsController>();
    final move = c.move;
    return PopScope(
      canPop: move?.stage != MoveStage.moving,
      child: ChumbucketWavySheet(
        title: 'Sign-in methods',
        canDismiss: move?.stage != MoveStage.moving,
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
          child:
              move != null
                  ? _MovePanel(move: move)
                  : _MethodList(controller: c),
        ),
      ),
    );
  }
}

class _KindMark extends StatelessWidget {
  const _KindMark(this.kind);
  final SignInMethodKind kind;

  @override
  Widget build(BuildContext context) => BasilIcon(
    kind.basilIcon,
    size: 24.w,
    color:
        kind == SignInMethodKind.wallet
            ? AppColors.primary
            : AppColors.textPrimary,
  );
}

class _MethodList extends StatefulWidget {
  const _MethodList({required this.controller});
  final SignInMethodsController controller;

  @override
  State<_MethodList> createState() => _MethodListState();
}

class _MethodListState extends State<_MethodList> {
  SignInMethodRow? _confirming;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final methods = c.methods;
    final confirming = _confirming;
    if (confirming != null) {
      return _Confirm(
        row: confirming,
        busy: c.busy == confirming.id,
        onUnlink: () async {
          await c.unlink(confirming);
          if (mounted) setState(() => _confirming = null);
        },
        onCancel: () => setState(() => _confirming = null),
      );
    }
    final current = methods?.current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (current != null)
          Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: Row(
              key: const ValueKey('signed-in-with'),
              children: [
                Text(
                  'Signed in with',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(width: 8.w),
                BasilIcon(current.kind.basilIcon, size: 16.w),
                SizedBox(width: 6.w),
                Flexible(
                  child: Text(
                    current.display,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (methods == null && c.line == null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24.h),
            child: const Center(child: CircularProgressIndicator()),
          ),
        for (final row in methods?.rows ?? const <SignInMethodRow>[])
          _Row(
            key: ValueKey('sign-in-${row.id}'),
            leading: _KindMark(row.kind),
            label: row.display,
            trailing:
                row.current
                    ? BasilIcon(
                      'check-solid',
                      size: 20.w,
                      color: AppColors.primary,
                    )
                    // The Chumbucket wallet follows the account: read-only.
                    : row.chumbucket
                    ? Text(
                      'Chumbucket wallet',
                      key: ValueKey('chumbucket-wallet-${row.id}'),
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    )
                    : (methods!.linking && row.unlink != null)
                    ? IconButton(
                      tooltip: 'Unlink ${row.kind.title}',
                      onPressed:
                          c.busy == null
                              ? () => setState(() => _confirming = row)
                              : null,
                      icon: BasilIcon(
                        'cross-outline',
                        size: 20.w,
                        color: AppColors.textSecondary,
                      ),
                    )
                    : null,
          ),
        for (final kind in c.linkable)
          _Row(
            key: ValueKey('link-${kind.name}'),
            leading: _KindMark(kind),
            label: kind.title,
            onTap:
                c.busy == null
                    ? () =>
                        kind == SignInMethodKind.wallet
                            ? c.linkWallet()
                            : c.linkProvider(kind)
                    : null,
            trailing:
                c.busy == kind.name
                    ? SizedBox(
                      width: 18.w,
                      height: 18.w,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(
                      'Link',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
          ),
        if (c.line != null)
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Text(
              c.line!,
              key: const ValueKey('sign-in-line'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.leading,
    required this.label,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(bottom: 8.h),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22.r),
      border: Border.all(color: AppColors.outlineVariant),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22.r),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 52.h),
          child: Padding(
            padding: EdgeInsets.only(left: 16.w, right: 8.w),
            child: Row(
              children: [
                leading,
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (trailing != null)
                  Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: trailing,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Confirm extends StatelessWidget {
  const _Confirm({
    required this.row,
    required this.busy,
    required this.onUnlink,
    required this.onCancel,
  });

  final SignInMethodRow row;
  final bool busy;
  final VoidCallback onUnlink;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _KindMark(row.kind),
          for (final k in row.alsoUnlinks) ...[
            SizedBox(width: 8.w),
            _KindMark(k),
          ],
        ],
      ),
      SizedBox(height: 12.h),
      Text(
        'Unlink ${row.display}?',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700),
      ),
      if (row.alsoUnlinks.isNotEmpty) ...[
        SizedBox(height: 6.h),
        Text(
          '${row.alsoUnlinks.map((k) => k.title).join(' and ')} goes too.',
          style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
        ),
      ],
      SizedBox(height: 18.h),
      ChumbucketPrimaryButton(label: 'Unlink', busy: busy, onPressed: onUnlink),
      ChumbucketTextAction(label: 'Cancel', onPressed: busy ? null : onCancel),
    ],
  );
}

class _MovePanel extends StatelessWidget {
  const _MovePanel({required this.move});
  final SignInMove move;

  @override
  Widget build(BuildContext context) {
    final c = context.read<SignInMethodsController>();
    final kind = move.method;
    final preview = move.preview;
    final title = TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700);
    final line = TextStyle(fontSize: 14.sp, color: AppColors.textSecondary);

    if (preview == null) {
      return Column(
        key: const ValueKey('move-conflict'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _KindMark(kind),
          SizedBox(height: 12.h),
          Text(
            'This ${kind.title} is on another account. Sign in with it to bring it here.',
            textAlign: TextAlign.center,
            style: line,
          ),
          SizedBox(height: 18.h),
          ChumbucketPrimaryButton(
            label: 'Continue with ${kind.title}',
            busy: move.stage == MoveStage.proving,
            onPressed: c.prove,
          ),
          ChumbucketTextAction(label: 'Not now', onPressed: c.cancelMove),
        ],
      );
    }

    if (preview.outcome == LinkOutcome.already) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('It already signs in here.', style: line),
          SizedBox(height: 18.h),
          ChumbucketPrimaryButton(label: 'Done', onPressed: c.cancelMove),
        ],
      );
    }

    final refusal =
        preview.outcome == LinkOutcome.fold ? preview.refusal : null;
    final folding = preview.outcome == LinkOutcome.fold;
    return Column(
      key: const ValueKey('move-preview'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // What was proven, then where it goes: "@handle → @account".
        Row(
          key: const ValueKey('link-proof'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _KindMark(preview.proofKind),
            SizedBox(width: 8.w),
            Flexible(
              child: Text(
                preview.proofDisplay,
                style: title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              child: BasilIcon('arrow-right-outline', size: 20.w),
            ),
            Flexible(
              child: Text(
                preview.into.display,
                style: title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (preview.from != null) ...[
          SizedBox(height: 6.h),
          Text(
            preview.from!.display,
            key: const ValueKey('link-from'),
            style: line,
          ),
        ],
        SizedBox(height: 12.h),
        Text(
          refusal != null
              ? signInLinkCopy(refusal)
              : folding
              ? 'Its sign-ins, wallets and follows move here. Its calls stay as made.'
              : '${kind.title} signs in here from now on.',
          textAlign: TextAlign.center,
          style: line,
        ),
        SizedBox(height: 18.h),
        if (refusal != null)
          ChumbucketPrimaryButton(label: 'Done', onPressed: c.cancelMove)
        else ...[
          ChumbucketPrimaryButton(
            label: folding ? 'Move here' : 'Link',
            busy: move.stage == MoveStage.moving,
            onPressed: c.confirm,
          ),
          ChumbucketTextAction(
            label: 'Not now',
            onPressed: move.stage == MoveStage.moving ? null : c.cancelMove,
          ),
        ],
      ],
    );
  }
}
