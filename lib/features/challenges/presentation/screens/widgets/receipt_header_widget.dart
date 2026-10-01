import 'package:flutter/material.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_header.dart';

/// Compatibility wrapper; no private gradient or header geometry.
class ReceiptHeaderWidget extends StatelessWidget {
  const ReceiptHeaderWidget({super.key});
  @override
  Widget build(BuildContext context) =>
      const ChumbucketSheetHeader(title: 'Challenge receipt');
}
