import 'package:flutter/material.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_header.dart';

/// Compatibility wrapper; sheet chrome and wave remain shared.
class ResolveSheetHeader extends StatelessWidget {
  const ResolveSheetHeader({super.key, required this.amountText});
  final String amountText;
  @override
  Widget build(BuildContext context) =>
      ChumbucketSheetHeader(title: 'Bet Amount', subtitle: '$amountText SOL');
}
