import '../../core/config/app_config.dart';
import '../../core/network/http_api_client.dart';

class IotApiService {
  final HttpApiClient _http;

  IotApiService({HttpApiClient? http})
    : _http = http ?? HttpApiClient();

  Future<Map<String, dynamic>> listIotMachines() {
    return _http.getJson(
      Uri.parse('${AppConfig.iotUrl}/api/v1/iot/machines'),
    );
  }

  Future<Map<String, dynamic>> getTelemetry(String machineId) {
    return _http.getJson(
      Uri.parse('${AppConfig.iotUrl}/api/v1/iot/telemetry/$machineId'),
    );
  }

  Future<Map<String, dynamic>> sendCommand(String machineId, String command) {
    return _http.postJson(
      Uri.parse('${AppConfig.iotUrl}/api/v1/iot/commands/$machineId/$command'),
    );
  }
}
