import 'package:flutter/material.dart';
import 'package:shared_types/shared_types.dart';

class TransferScreen extends StatelessWidget {
  const TransferScreen({
    super.key,
    required this.transfers,
    this.onCancel,
    this.onOpenFile,
  });

  final List<TransferFile> transfers;
  final ValueChanged<String>? onCancel;
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (transfers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.upload_file,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No active transfers',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: transfers.length,
      itemBuilder: (context, index) {
        final transfer = transfers[index];
        return _TransferTile(
          transfer: transfer,
          onCancel: () => onCancel?.call(transfer.id),
          onOpenFile: () => onOpenFile?.call(transfer.id),
        );
      },
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({
    required this.transfer,
    this.onCancel,
    this.onOpenFile,
  });

  final TransferFile transfer;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(transfer.status, theme);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                transfer.direction == TransferDirection.sending
                    ? Icons.upload
                    : Icons.download,
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.name,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatSize(transfer.bytesTransferred) +
                          ' / ' +
                          _formatSize(transfer.size),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: transfer.status),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: transfer.progress.clamp(0.0, 1.0),
              minHeight: 4,
              color: statusColor,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 4),
          if (transfer.status == TransferStatus.inProgress)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Cancel'),
              ),
            ),
          if (transfer.status == TransferStatus.completed && transfer.localPath != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOpenFile,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Show in Finder'),
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor(TransferStatus status, ThemeData theme) {
    switch (status) {
      case TransferStatus.inProgress:
        return theme.colorScheme.primary;
      case TransferStatus.completed:
        return Colors.green;
      case TransferStatus.failed:
      case TransferStatus.cancelled:
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.outline;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final TransferStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String label = 'Unknown';
    Color color = theme.colorScheme.outline;

    switch (status) {
      case TransferStatus.pending:
        label = 'Waiting';
        color = theme.colorScheme.outline;
      case TransferStatus.inProgress:
        label = 'Sending';
        color = theme.colorScheme.primary;
      case TransferStatus.paused:
        label = 'Paused';
        color = theme.colorScheme.secondary;
      case TransferStatus.completed:
        label = 'Done';
        color = Colors.green;
      case TransferStatus.failed:
        label = 'Failed';
        color = theme.colorScheme.error;
      case TransferStatus.cancelled:
        label = 'Cancelled';
        color = theme.colorScheme.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
      ),
    );
  }
}
