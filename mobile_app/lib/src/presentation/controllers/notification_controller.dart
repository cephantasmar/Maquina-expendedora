import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../data/services/notification_api_service.dart';
import '../../domain/entities/app_notification.dart';

class NotificationController extends ChangeNotifier {
  final NotificationApiService _api;
  List<AppNotification> _notifications = [];
  bool _loading = false;
  String? _error;
  StreamSubscription? _wsSubscription;

  NotificationController({NotificationApiService? api})
    : _api = api ?? NotificationApiService();

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadNotifications(String userEmail) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.getNotifications(userEmail);
      _notifications = data.map((n) => AppNotification.fromJson(n)).toList();
      _startWebSocket(userEmail);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _startWebSocket(String userEmail) {
    _wsSubscription?.cancel();
    _wsSubscription = _api.connectToNotifications(userEmail).listen((data) {
      final Map<String, dynamic> json = jsonDecode(data);
      final newNotif = AppNotification.fromJson(json);
      
      // Añadir al principio si no existe
      if (!_notifications.any((n) => n.id == newNotif.id)) {
        _notifications.insert(0, newNotif);
        notifyListeners();
      }
    }, onError: (err) {
      debugPrint('Notification WebSocket Error: $err');
    });
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _api.markAsRead(notificationId);
      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1) {
        _notifications[index] = _notifications[index].copyWith(isRead: true);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _api.disconnect();
    super.dispose();
  }
}
