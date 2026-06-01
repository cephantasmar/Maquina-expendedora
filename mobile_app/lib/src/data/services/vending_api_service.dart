import '../../core/config/app_config.dart';
import '../../core/network/http_api_client.dart';

class VendingApiService {
  final HttpApiClient _http;

  VendingApiService({HttpApiClient? http})
    : _http = http ?? HttpApiClient();

  Future<Map<String, dynamic>> listMachines({String? ownerEmail}) {
    final query = ownerEmail != null ? '?owner_email=$ownerEmail' : '';
    return _http.getJson(
      Uri.parse('${AppConfig.vendingUrl}/api/v1/machines$query'),
    );
  }

  Future<Map<String, dynamic>> getInventory(String machineId) {
    return _http.getJson(
      Uri.parse('${AppConfig.vendingUrl}/api/v1/machines/$machineId/inventory'),
    );
  }

  Future<Map<String, dynamic>> updateInventoryPrice(String machineId, String slotOrId, double price) {
    return _http.patchJson(
      Uri.parse('${AppConfig.vendingUrl}/api/v1/machines/$machineId/inventory/$slotOrId/price?price=$price'),
    );
  }

  Future<Map<String, dynamic>> updateSlotStatus(String machineId, String slotOrId, bool isEnabled, String? slotType) {
    return _http.patchJson(
      Uri.parse('${AppConfig.vendingUrl}/api/v1/machines/$machineId/inventory/$slotOrId/status'),
      body: {'is_enabled': isEnabled, 'slot_type': slotType},
    );
  }

  Future<Map<String, dynamic>> getBanner() {
    return _http.getJson(
      Uri.parse('${AppConfig.vendingUrl}/api/v1/settings/banner'),
    );
  }

  Future<Map<String, dynamic>> updateBanner(String url) {
    return _http.postJson(
      Uri.parse('${AppConfig.vendingUrl}/api/v1/admin/settings/banner'),
      body: {'url': url},
    );
  }
}
