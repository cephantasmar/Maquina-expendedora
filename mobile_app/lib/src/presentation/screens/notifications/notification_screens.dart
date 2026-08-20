import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/notification_controller.dart';
import '../../../domain/entities/app_notification.dart';

class NotificationListScreen extends StatelessWidget {
  const NotificationListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationController>();
    final notifications = controller.notifications;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (notifications.any((n) => !n.isRead))
            TextButton(
              onPressed: () {
                for (var n in notifications) {
                  if (!n.isRead) controller.markAsRead(n.id);
                }
              },
              child: const Text('Leer todas'),
            ),
        ],
      ),
      body: notifications.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No tienes notificaciones aún', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final n = notifications[index];
                return _NotificationTile(notification: n);
              },
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;

  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: notification.isRead ? 0 : 2,
      color: notification.isRead ? Colors.white : Colors.indigo.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getColor(notification.type).withOpacity(0.1),
          child: Icon(_getIcon(notification.type), color: _getColor(notification.type)),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
          ),
        ),
        subtitle: Text(
          notification.summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          _formatTime(notification.createdAt),
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        onTap: () {
          if (!notification.isRead) {
            context.read<NotificationController>().markAsRead(notification.id);
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NotificationDetailScreen(notification: notification),
            ),
          );
        },
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'success': return Icons.check_circle_outline;
      case 'warning': return Icons.warning_amber_rounded;
      case 'error': return Icons.error_outline;
      default: return Icons.info_outline;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case 'success': return Colors.green;
      case 'warning': return Colors.orange;
      case 'error': return Colors.red;
      default: return Colors.blue;
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${date.day}/${date.month}';
  }
}

class NotificationDetailScreen extends StatelessWidget {
  final AppNotification notification;

  const NotificationDetailScreen({super.key, required this.notification});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getIcon(notification.type),
                  color: _getColor(notification.type),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    notification.title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _formatDate(notification.createdAt),
              style: const TextStyle(color: Colors.grey),
            ),
            const Divider(height: 32),
            Text(
              notification.description,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'success': return Icons.check_circle_outline;
      case 'warning': return Icons.warning_amber_rounded;
      case 'error': return Icons.error_outline;
      default: return Icons.info_outline;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case 'success': return Colors.green;
      case 'warning': return Colors.orange;
      case 'error': return Colors.red;
      default: return Colors.blue;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
