import 'package:flutter/material.dart';
import 'package:shared_types/shared_types.dart';

class ClipboardHistoryScreen extends StatelessWidget {
  const ClipboardHistoryScreen({
    super.key,
    required this.clipItems,
    this.onItemTap,
    this.onItemDelete,
  });

  final List<ClipItem> clipItems;
  final void Function(ClipItem)? onItemTap;
  final void Function(ClipItem)? onItemDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (clipItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.content_paste_off,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No clipboard history yet',
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
      itemCount: clipItems.length,
      itemBuilder: (context, index) {
        final item = clipItems[index];
        return _ClipboardTile(
          item: item,
          onTap: () => onItemTap?.call(item),
          onDelete: () => onItemDelete?.call(item),
        );
      },
    );
  }
}

class _ClipboardTile extends StatelessWidget {
  const _ClipboardTile({
    required this.item,
    this.onTap,
    this.onDelete,
  });

  final ClipItem item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = item.content.length > 120
        ? '${item.content.substring(0, 120)}...'
        : item.content;

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete?.call(),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MimeTypeIcon(mimeType: item.mimeType),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      display,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (item.deviceName != null) ...[
                          Text(
                            item.deviceName!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _formatTime(item.timestamp),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _MimeTypeIcon extends StatelessWidget {
  const _MimeTypeIcon({required this.mimeType});

  final String mimeType;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    if (mimeType.startsWith('image/')) {
      icon = Icons.image;
      color = Colors.purple;
    } else if (mimeType.startsWith('text/html')) {
      icon = Icons.html;
      color = Colors.orange;
    } else {
      icon = Icons.text_fields;
      color = Colors.blue;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
