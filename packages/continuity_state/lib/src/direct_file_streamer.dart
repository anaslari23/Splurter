import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:continuity_core/continuity_core.dart';
import 'package:shared_types/shared_types.dart';
import 'transfers_provider.dart';
import 'settings_provider.dart';
import 'relay_loop.dart';

class DirectFileStreamer {
  DirectFileStreamer._();
  static final DirectFileStreamer instance = DirectFileStreamer._();

  HttpServer? _server;
  final Map<String, File> _activeFileOffers = {};

  /// Start the local HTTP file server for high-speed chunked downloads
  Future<void> initServer() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 53318);
      _server?.listen(_handleHttpRequest);
    } catch (_) {}
  }

  void _handleHttpRequest(HttpRequest request) async {
    final path = request.uri.path;
    if (path.startsWith('/transfer/')) {
      final transferId = path.replaceFirst('/transfer/', '');
      final file = _activeFileOffers[transferId];
      if (file != null && await file.exists()) {
        final length = await file.length();
        request.response.headers.contentType = ContentType.binary;
        request.response.contentLength = length;
        await file.openRead().pipe(request.response);
        return;
      }
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  /// Offer and stream a file to paired device
  Future<void> sendFile({
    required String filePath,
    required String fileName,
    required int fileSize,
    required String uid,
    required String senderId,
    required String recipientId,
    required WidgetRef ref,
  }) async {
    await initServer();

    final transferId = 'transfer-${DateTime.now().millisecondsSinceEpoch}';
    final file = File(filePath);
    _activeFileOffers[transferId] = file;

    final transfer = TransferFile(
      id: transferId,
      name: fileName,
      path: filePath,
      size: fileSize,
      mimeType: 'application/octet-stream',
      direction: TransferDirection.sending,
      status: TransferStatus.inProgress,
      localPath: filePath,
      startTime: DateTime.now(),
    );
    ref.read(transfersProvider.notifier).add(transfer);

    final senderIp = await getLocalIpAddress() ?? '127.0.0.1';
    final downloadUrl = 'http://$senderIp:53318/transfer/$transferId';

    // Send file offer payload to receiver device
    await RelayLoop.instance.send(
      uid: uid,
      senderId: senderId,
      recipientId: recipientId,
      kind: RelayKind.transfer,
      payload: {
        'action': 'offer',
        'transferId': transferId,
        'name': fileName,
        'size': fileSize,
        'downloadUrl': downloadUrl,
      },
    );

    // Simulate progress updates for sending side
    var bytes = 0;
    const chunkSize = 64 * 1024;
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      bytes += chunkSize * 4;
      if (bytes >= fileSize) {
        bytes = fileSize;
        timer.cancel();
        ref.read(transfersProvider.notifier).updateProgress(transferId, bytes, TransferStatus.completed);
      } else {
        ref.read(transfersProvider.notifier).updateProgress(transferId, bytes, TransferStatus.inProgress);
      }
    });
  }

  /// Download incoming offered file from sender URL
  Future<void> receiveFile({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String downloadUrl,
    required WidgetRef ref,
  }) async {
    final tempDir = Directory.systemTemp;
    final saveFilePath = '${tempDir.path}/$fileName';

    final transfer = TransferFile(
      id: transferId,
      name: fileName,
      path: saveFilePath,
      size: fileSize,
      mimeType: 'application/octet-stream',
      direction: TransferDirection.receiving,
      status: TransferStatus.inProgress,
      startTime: DateTime.now(),
    );
    ref.read(transfersProvider.notifier).add(transfer);

    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(downloadUrl));
      final res = await req.close();

      final tempDir = Directory.systemTemp;
      final saveFile = File('${tempDir.path}/$fileName');
      final sink = saveFile.openWrite();

      var downloaded = 0;
      await res.forEach((chunk) {
        sink.add(chunk);
        downloaded += chunk.length;
        ref.read(transfersProvider.notifier).updateProgress(transferId, downloaded, TransferStatus.inProgress);
      });
      await sink.close();

      ref.read(transfersProvider.notifier).add(
        transfer.copyWith(
          bytesTransferred: fileSize,
          status: TransferStatus.completed,
          localPath: saveFile.path,
          endTime: DateTime.now(),
        ),
      );
    } catch (_) {
      ref.read(transfersProvider.notifier).updateProgress(transferId, 0, TransferStatus.failed);
    }
  }
}
