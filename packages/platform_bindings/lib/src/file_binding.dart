import 'dart:async';
import 'package:flutter/services.dart';

const _fileChannel = MethodChannel('splurter/file');

class FileResult {
  const FileResult({
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
  });

  final String path;
  final String name;
  final int size;
  final String? mimeType;
}

class FileSaveResult {
  const FileSaveResult({
    required this.path,
    required this.success,
  });

  final String? path;
  final bool success;
}

/// Open a system file picker and return the selected file metadata.
/// Returns null if the user cancels.
Future<FileResult?> pickFile() async {
  final result = await _fileChannel.invokeMethod('pickFile');
  if (result == null) return null;
  return FileResult(
    path: result['path'] as String,
    name: result['name'] as String,
    size: result['size'] as int,
    mimeType: result['mimeType'] as String?,
  );
}

/// Open multiple files picker. Returns an empty list if the user cancels.
Future<List<FileResult>> pickFiles() async {
  final result = await _fileChannel.invokeMethod('pickFiles');
  if (result == null) return const [];
  return (result as List).map((item) {
    final m = item as Map;
    return FileResult(
      path: m['path'] as String,
      name: m['name'] as String,
      size: m['size'] as int,
      mimeType: m['mimeType'] as String?,
    );
  }).toList();
}

/// Show a save dialog and return the path the user chose.
/// Returns null if the user cancels.
Future<String?> saveFileDialog({
  required String suggestedName,
  String? mimeType,
}) async {
  final result = await _fileChannel.invokeMethod('saveFileDialog', {
    'suggestedName': suggestedName,
    'mimeType': mimeType,
  });
  return result != null ? result as String : null;
}
