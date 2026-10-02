import 'package:flutter/material.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_header.dart';

/// Compatibility wrapper; sheet chrome and wave remain shared.
class ResolveSheetHeader extends StatelessWidget {
  const ResolveSheetHeader({super.key, required this.amountText});
  final String amountText;
  // This is the reference composition itself: a muted "Bet Amount" caption
  // over the amount as the hero. It is the sheet's only number, so it is the
  // sheet's largest thing — not a subtitle under a title.
  @override
  Widget build(BuildContext context) =>
      ChumbucketSheetHeader(title: 'Bet Amount', value: '$amountText SOL');
}
