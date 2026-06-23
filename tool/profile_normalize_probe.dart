import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/models/profile.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/profile_normalize_probe.dart <path>');
    exit(1);
  }
  final file = File(args.first);
  final bytes = file.readAsBytesSync();
  final normalized = ProfileExtension.normalizeImportedConfigBytes(
    Uint8List.fromList(bytes),
  );
  stdout.write(String.fromCharCodes(normalized));
}
