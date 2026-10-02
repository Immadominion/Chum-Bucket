/// Settings → Export my data: the BFF's `auth.exportData` JSON, saved to a
/// file and handed to the system share sheet so the person can keep it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/trust/data/trust_repository.dart';

/// File name for an export taken at [at] (UTC date).
String exportFileName(DateTime at) {
  final d = at.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'chumbucket-export-${d.year}${two(d.month)}${two(d.day)}.json';
}

/// Pretty JSON, stable for a person to read.
String encodeExport(Map<String, dynamic> data) =>
    const JsonEncoder.withIndent('  ').convert(data);

Future<void> exportMyData(
  BuildContext context, {
  TrustRepository? repository,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final repo = repository ?? TrustRepository.of(context);
  messenger?.showSnackBar(
    const SnackBar(
      content: Text('Preparing your data…'),
      duration: Duration(seconds: 2),
    ),
  );
  try {
    final data = await repo.exportData();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${exportFileName(DateTime.now())}');
    await file.writeAsString(encodeExport(data), flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'My Chumbucket data',
      ),
    );
  } on CallsSignedOutException {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Sign in to export your data.')),
    );
  } on CallsException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Couldn\'t save the export on this device. Try again.'),
      ),
    );
  }
}
