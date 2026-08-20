import '../../core/config/app_config.dart';
import '../../core/network/http_api_client.dart';

class OrchestratorApiService {
  final HttpApiClient _http;

  OrchestratorApiService({HttpApiClient? http})
    : _http = http ?? HttpApiClient();

  Future<Map<String, dynamic>> getTransaction(String transactionId) {
    return _http.getJson(
      Uri.parse(
        '${AppConfig.orchestratorUrl}/api/v1/transactions/$transactionId',
      ),
    );
  }

  Future<Map<String, dynamic>> initTransaction({
    required String machineId,
    String? productId,
    double? amount,
  }) {
    return _http.postJson(
      Uri.parse('${AppConfig.orchestratorUrl}/api/v1/transactions/init'),
      body: {
        'machine_id': machineId,
        'product_id': productId ?? 'PROD-1',
        'amount': amount,
      },
    );
  }

  Future<Map<String, dynamic>> confirmPayment(String transactionId) {
    return _http.postJson(
      Uri.parse(
        '${AppConfig.orchestratorUrl}/api/v1/transactions/$transactionId/payment-confirmed',
      ),
    );
  }

  Future<Map<String, dynamic>> generateQr(String transactionId) {
    return _http.postJson(
      Uri.parse(
        '${AppConfig.orchestratorUrl}/api/v1/transactions/$transactionId/generate-qr',
      ),
    );
  }

  Future<Map<String, dynamic>> getAdminStatsSummary() {
    return _http.getJson(
      Uri.parse('${AppConfig.orchestratorUrl}/api/v1/admin/stats/summary'),
    );
  }

  Future<Map<String, dynamic>> getTemperatureHistory({int intervalMinutes = 10}) {
    return _http.getJson(
      Uri.parse(
        '${AppConfig.orchestratorUrl}/api/v1/admin/stats/temperature-history?interval_minutes=$intervalMinutes',
      ),
    );
  }

  Future<Map<String, dynamic>> getDistanceHistory() {
    return _http.getJson(
      Uri.parse('${AppConfig.orchestratorUrl}/api/v1/admin/stats/distance-history'),
    );
  }


  Future<Map<String, dynamic>> getTopSellers(String machineId) {
    return _http.getJson(
      Uri.parse('${AppConfig.orchestratorUrl}/api/v1/admin/stats/top-sellers?machine_id=$machineId'),
    );
  }

  Future<Map<String, dynamic>> getFailedSlots(String machineId) {
    return _http.getJson(
      Uri.parse('${AppConfig.orchestratorUrl}/api/v1/admin/stats/failed-slots?machine_id=$machineId'),
    );
  }

  Future<Map<String, dynamic>> toggleLights(String machineId) {
    return _http.postJson(
      Uri.parse('${AppConfig.orchestratorUrl}/api/v1/admin/commands/$machineId/toggle-lights'),
    );
  }

  Future<Map<String, dynamic>> refreshConfig(String machineId) {
    return _http.postJson(
      Uri.parse('${AppConfig.orchestratorUrl}/api/v1/admin/commands/$machineId/refresh-config'),
    );
  }
}

