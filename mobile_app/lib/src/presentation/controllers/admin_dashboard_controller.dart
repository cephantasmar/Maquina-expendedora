import 'package:flutter/foundation.dart';
import '../../data/services/orchestrator_api_service.dart';
import '../../data/services/vending_api_service.dart';
import '../../data/services/iot_api_service.dart';

class AdminDashboardController extends ChangeNotifier {
  final OrchestratorApiService _api;
  final VendingApiService _vendingApi;
  final IotApiService _iotApi;

  bool loading = false;
  String? error;

  double totalSales = 0.0;
  Map<String, int> statusBreakdown = {};
  List<Map<String, dynamic>> tempHistory = [];
  List<Map<String, dynamic>> distanceHistory = [];
  
  List<dynamic> machines = [];
  List<dynamic> iotMachines = [];
  Map<String, List<dynamic>> inventories = {};
  Map<String, List<dynamic>> topSellers = {};
  Map<String, List<dynamic>> failedSlots = {};
  Map<String, dynamic> banner = {};

  AdminDashboardController({
    OrchestratorApiService? api,
    VendingApiService? vendingApi,
    IotApiService? iotApi,
  }) : _api = api ?? OrchestratorApiService(),
       _vendingApi = vendingApi ?? VendingApiService(),
       _iotApi = iotApi ?? IotApiService();

  Future<void> loadStats() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final summary = await _api.getAdminStatsSummary();
      totalSales = (summary['total_sales'] as num).toDouble();
      statusBreakdown = Map<String, int>.from(summary['status_breakdown'] ?? {});
      
      banner = await _vendingApi.getBanner();

      // Load machines
      final machinesData = await _vendingApi.listMachines();
      machines = machinesData['machines'] ?? [];

      // Load IoT machines for DEVOPS/Support
      final iotData = await _iotApi.listIotMachines();
      iotMachines = iotData['machines'] ?? [];
      
      // Load inventories and stats for all machines
      for (var machine in machines) {
        final machineId = machine['id'];
        final inventoryData = await _vendingApi.getInventory(machineId);
        inventories[machineId] = inventoryData['items'] ?? [];
        
        final topSellersData = await _api.getTopSellers(machineId);
        topSellers[machineId] = List<Map<String, dynamic>>.from(topSellersData['items'] ?? []);

        final failedSlotsData = await _api.getFailedSlots(machineId);
        failedSlots[machineId] = List<Map<String, dynamic>>.from(failedSlotsData['items'] ?? []);
      }
      
      notifyListeners();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> sendIotCommand(String machineId, String command) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      await _iotApi.sendCommand(machineId, command);
      // Recargar telemetría después de un comando si es necesario
      final iotData = await _iotApi.listIotMachines();
      iotMachines = iotData['machines'] ?? [];
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> updatePrice(String machineId, String slot, double newPrice) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      await _vendingApi.updateInventoryPrice(machineId, slot, newPrice);
      // Notificar a la máquina para que refresque su pantalla
      await _api.refreshConfig(machineId);
      
      // Reload inventory for this machine
      final inventoryData = await _vendingApi.getInventory(machineId);
      inventories[machineId] = inventoryData['items'] ?? [];
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> updateSlotStatus(String machineId, String slot, bool isEnabled, String? slotType) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      await _vendingApi.updateSlotStatus(machineId, slot, isEnabled, slotType);
      // Reload inventory for this machine
      final inventoryData = await _vendingApi.getInventory(machineId);
      inventories[machineId] = inventoryData['items'] ?? [];
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> updateBanner(String url) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      await _vendingApi.updateBanner(url);
      banner = await _vendingApi.getBanner();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> toggleLights(String machineId) async {
    try {
      await _api.toggleLights(machineId);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadTempHistory({int intervalMinutes = 10}) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final history = await _api.getTemperatureHistory(intervalMinutes: intervalMinutes);
      tempHistory = List<Map<String, dynamic>>.from(history['items'] ?? []);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadDistanceHistory() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final history = await _api.getDistanceHistory();
      distanceHistory = List<Map<String, dynamic>>.from(history['items'] ?? []);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
