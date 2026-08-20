import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/config/app_config.dart';
import '../../core/network/http_api_client.dart';

class NotificationApiService {
  final HttpApiClient _http;
  WebSocketChannel? _channel;

  NotificationApiService({HttpApiClient? http})
    : _http = http ?? HttpApiClient();

  Future<List<Map<String, dynamic>>> getNotifications(String userEmail) async {
    final response = await _http.getJson(
      Uri.parse('${AppConfig.notificationUrl}/api/v1/notifications/$userEmail'),
    );
    return List<Map<String, dynamic>>.from(response as List? ?? []);
  }

  Future<void> markAsRead(String notificationId) async {
    await _http.patchJson(
      Uri.parse('${AppConfig.notificationUrl}/api/v1/notifications/$notificationId/read'),
    );
  }

  Stream<dynamic> connectToNotifications(String userEmail) {
    final wsUrl = AppConfig.notificationUrl.replaceFirst('http', 'ws');
    _channel = WebSocketChannel.connect(
      Uri.parse('$wsUrl/ws/notifications/$userEmail'),
    );
    return _channel!.stream;
  }

  void disconnect() {
    _channel?.sink.close();
  }
}
