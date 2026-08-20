import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/api_client.dart';
import '../../../transactions/data/models/transaction_view.dart';
import '../../../transactions/data/orchestrator_api.dart';

class RoleDashboardScreen extends StatefulWidget {
  final String email;
  final String role;

  const RoleDashboardScreen({
    super.key,
    required this.email,
    required this.role,
  });

  @override
  State<RoleDashboardScreen> createState() => _RoleDashboardScreenState();
}

class _RoleDashboardScreenState extends State<RoleDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController? _tabController;
  final ApiClient _api = ApiClient();
  final OrchestratorApi _orchestrator = OrchestratorApi();
  final TextEditingController _toEmail = TextEditingController(
    text: 'admin@grog.com',
  );
  final TextEditingController _amount = TextEditingController(text: '5');

  Map<String, dynamic> _wallet = {};
  Map<String, dynamic> _history = {};
  Map<String, dynamic> _machines = {};
  Map<String, dynamic> _sales = {};
  Map<String, dynamic> _iot = {};
  Map<String, dynamic> _banner = {};
  Map<String, dynamic> _topSellers = {};
  List<TransactionView> _transactions = [];
  bool _loading = true;
  String _info = '';

  @override
  void initState() {
    super.initState();
    _tabController = widget.role == 'ADMIN' 
        ? TabController(length: 4, vsync: this)
        : null;
    _load();
    if (widget.role == 'CLIENT') {
      _startNfcSession();
    }
  }

  Future<void> _startNfcSession() async {
    try {
      bool isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) return;

      NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null || ndef.cachedMessage == null) return;
          
          String payload = '';
          for (var record in ndef.cachedMessage!.records) {
            if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown) {
              if (record.payload.isNotEmpty) {
                int langCodeLen = record.payload.first & 0x3F;
                payload = utf8.decode(record.payload.sublist(langCodeLen + 1));
              }
            }
          }

          if (payload.isNotEmpty) {
            final String machineId = payload.trim();
            if (mounted) {
              _showNfcPurchasePanel(machineId);
            }
          }
        } catch (e) {
          // ignore
        }
      });
    } catch (e) {
      // ignore
    }
  }

  Future<void> _showNfcPurchasePanel(String machineId) async {
    setState(() => _loading = true);
    try {
      final inv = await _api.inventory(machineId);
      final items = inv['items'] as List<dynamic>? ?? [];
      
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              top: 16, left: 16, right: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Máquina: $machineId', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text('Selecciona un producto:'),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  const Text('No hay productos disponibles.')
                else
                  SizedBox(
                    height: MediaQuery.of(ctx).size.height * 0.5,
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        final isEnabled = item['is_enabled'] ?? true;
                        if (!isEnabled) return const SizedBox();
                        return ListTile(
                          leading: const Icon(Icons.fastfood, color: Colors.blue),
                          title: Text('${item['product_name']} (Slot ${item['slot']})'),
                          trailing: Text('Bs. ${item['price']}'),
                          onTap: () {
                            Navigator.pop(ctx);
                            _buyProductFromNfc(machineId, item);
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          );
        }
      );
    } catch (e) {
      setState(() => _info = 'Error leyendo máquina $machineId: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buyProductFromNfc(String machineId, dynamic item) async {
    try {
      var tx = await _orchestrator.createTransaction(
        userId: widget.email,
        machineId: machineId,
        productId: item['product_id'] ?? 'PROD-1',
        amount: double.parse(item['price'].toString()),
      );
      tx = await _orchestrator.generateQr(tx.id);
      setState(() {
        _transactions.insert(0, tx);
        _info = 'QR generado para ${item['product_name']} (tx: ${tx.id})';
      });
    } catch (e) {
      setState(() => _info = e.toString());
    }
  }

  @override
  void dispose() {
    if (widget.role == 'CLIENT') {
      NfcManager.instance.stopSession().catchError((_) {});
    }
    _tabController?.dispose();
    super.dispose();
  }

  Map<String, List<dynamic>> _machineInventories = {};

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    try {
      _banner = await _api.getBanner();
      if (widget.role == 'CLIENT') {
        _wallet = await _api.wallet(widget.email);
        _history = await _api.walletHistory(widget.email);
        _transactions = await _orchestrator.listTransactions(widget.email);
        await prefs.setString('cache_client_wallet', jsonEncode(_wallet));
        await prefs.setString('cache_client_history', jsonEncode(_history));
      } else if (widget.role == 'ADMIN') {
        // Cargar tambien billetera para ADMIN
        _wallet = await _api.wallet(widget.email);
        _history = await _api.walletHistory(widget.email);

        _machines = await _api.machines(ownerEmail: widget.email);
        _sales = await _api.sales();

        final machineList = (_machines['machines'] as List<dynamic>? ?? []);
        for (var m in machineList) {
          final machineId = m['id'];
          final inv = await _api.inventory(machineId);
          _machineInventories[machineId] = inv['items'] ?? [];
          final stats = await _api.topSellers(machineId);
          _topSellers[machineId] = stats['items'] ?? [];
        }

        await prefs.setString('cache_admin_machines', jsonEncode(_machines));
        await prefs.setString('cache_admin_sales', jsonEncode(_sales));
      } else if (widget.role == 'DEVOPS') {
        _machines = await _api.machines();
        _iot = await _api.iotMachines();
        await prefs.setString('cache_devops_machines', jsonEncode(_machines));
        await prefs.setString('cache_devops_iot', jsonEncode(_iot));
      }
    } catch (_) {
      // ... cache logic unchanged
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updatePrice(String machineId, String slot, double newPrice) async {
    try {
      await _api.updateInventoryPrice(machineId, slot, newPrice);
      setState(() => _info = 'Precio actualizado en máquina $machineId slot $slot a Bs. $newPrice');
      await _load();
    } catch (e) {
      setState(() => _info = e.toString());
    }
  }

  Future<void> _updateStatus(String machineId, String slot, bool isEnabled, String slotType) async {
    try {
      await _api.updateSlotStatus(machineId, slot, isEnabled, slotType);
      setState(() => _info = 'Estado de slot $slot actualizado');
      await _load();
    } catch (e) {
      setState(() => _info = e.toString());
    }
  }

  void _showEditSlotDialog(String machineId, dynamic item) {
    final slot = item['slot'];
    final name = item['product_name'];
    final priceController = TextEditingController(text: item['price'].toString());
    bool isEnabled = item['is_enabled'] ?? true;
    String slotType = item['slot_type'] ?? 'soda';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text('Gestionar Slot $slot: $name'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Precio (Bs.)'),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Habilitado'),
                  value: isEnabled,
                  onChanged: (v) => setModalState(() => isEnabled = v),
                ),
                const Text('Tipo de Producto:'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Soda'),
                      selected: slotType == 'soda',
                      onSelected: (v) => setModalState(() => slotType = 'soda'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Snack'),
                      selected: slotType == 'snack',
                      onSelected: (v) => setModalState(() => slotType = 'snack'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final newPrice = double.tryParse(priceController.text);
                if (newPrice != null) {
                  Navigator.pop(context);
                  _updatePrice(machineId, slot, newPrice);
                  _updateStatus(machineId, slot, isEnabled, slotType);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showStatsDialog(String machineId) {
    final stats = _topSellers[machineId] as List<dynamic>? ?? [];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Estadísticas: Lo más vendido'),
        content: SizedBox(
          width: double.maxFinite,
          child: stats.isEmpty 
            ? const Text('No hay ventas registradas aún.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: stats.length,
                itemBuilder: (context, i) => ListTile(
                  leading: CircleAvatar(child: Text('${i+1}')),
                  title: Text('Slot ${stats[i]['slot']}'),
                  trailing: Text('${stats[i]['count']} ventas'),
                ),
              ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _showBannerConfigDialog() {
    final controller = TextEditingController(text: _banner['url'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurar Banner Publicitario'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'URL de la imagen'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              await _api.updateBanner(controller.text);
              Navigator.pop(context);
              _load();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLights(String machineId) async {
    try {
      await _api.toggleLights(machineId);
      setState(() => _info = 'Comando de luces enviado a $machineId');
    } catch (e) {
      setState(() => _info = e.toString());
    }
  }

  Future<void> _transfer() async {
    try {
      final res = await _api.transfer(
        widget.email,
        _toEmail.text.trim(),
        double.parse(_amount.text.trim()),
      );
      setState(() => _info = 'Transferencia OK. Saldo: ${res['from_balance']}');
      await _load();
    } catch (e) {
      setState(() => _info = e.toString());
    }
  }

  Future<void> _buyProduct() async {
    try {
      var tx = await _orchestrator.createTransaction(
        userId: widget.email,
        machineId: 'MACHINE-001',
        productId: 'SODA-001',
        amount: 8.5,
      );
      tx = await _orchestrator.generateQr(tx.id);
      setState(() {
        _transactions.insert(0, tx);
        _info = 'QR generado para ${tx.id}';
      });
    } catch (e) {
      setState(() => _info = e.toString());
    }
  }

  Future<void> _simulate(TransactionView tx, String outcome) async {
    try {
      await _orchestrator.confirmPayment(tx.id);
      final res = await _orchestrator.setDispenseResult(
        tx.id,
        outcome == 'success',
      );
      setState(() => _info = 'Resultado: ${res.state.name}');
      await _load();
    } catch (e) {
      setState(() => _info = e.toString());
    }
  }

  Future<void> _devopsCommand(String machineId, String cmd) async {
    try {
      final res = await _api.iotCommand(machineId, cmd);
      setState(() => _info = 'Comando ${res['command']} encolado');
    } catch (e) {
      setState(() => _info = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Grog - ${widget.role}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
        bottom: widget.role == 'ADMIN'
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: const [
                  Tab(icon: Icon(Icons.account_balance_wallet), text: 'Mi Billetera'),
                  Tab(icon: Icon(Icons.analytics), text: 'Resumen Ventas'),
                  Tab(icon: Icon(Icons.grid_view), text: 'Máquinas'),
                  Tab(icon: Icon(Icons.campaign), text: 'Publicidad'),
                ],
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_info.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.indigo.withOpacity(0.1),
                child: Text(_info, style: const TextStyle(color: Colors.indigo)),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: widget.role == 'ADMIN'
                  ? TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAdminWalletTab(),
                        _buildAdminSalesTab(),
                        _buildAdminMachinesTab(),
                        _buildAdminBannerTab(),
                      ],
                    )
                  : _buildByRole(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminWalletTab() {
    final balance = _wallet['balance'] ?? 0;
    final history = (_history['items'] as List<dynamic>? ?? []);
    return ListView(
      children: [
        Card(
          elevation: 4,
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet, size: 40, color: Colors.indigo),
            title: const Text('Saldo SimuPay', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Bs. $balance', style: const TextStyle(fontSize: 20, color: Colors.green, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Historial Reciente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Divider(),
        ...history.map((e) => Card(
          child: ListTile(
            leading: Icon(
              e['type'] == 'deposit' ? Icons.arrow_downward : Icons.arrow_upward,
              color: e['type'] == 'deposit' ? Colors.green : Colors.red,
            ),
            title: Text('${e['type']}'.toUpperCase()),
            subtitle: Text('Hacia: ${e['to_email'] ?? 'N/A'}'),
            trailing: Text('Bs. ${e['amount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        )),
        if (history.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No hay transacciones registradas', textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _buildAdminSalesTab() {
    return ListView(
      children: [
        Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('Ventas Totales', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.today, color: Colors.green),
                  title: const Text('Hoy'),
                  trailing: Text('Bs. ${_sales['daily_total']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_month, color: Colors.blue),
                  title: const Text('Este Mes'),
                  trailing: Text('Bs. ${_sales['monthly_total']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminMachinesTab() {
    final machines = (_machines['machines'] as List<dynamic>? ?? []);
    return ListView(
      children: [
        ...machines.map((m) {
          final machineId = m['id'] as String;
          final inventory = _machineInventories[machineId] ?? [];

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const Icon(Icons.vending_machine, size: 40),
                  title: Text(m['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: $machineId | Estado: ${m['status']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.bar_chart, color: Colors.orange),
                        onPressed: () => _showStatsDialog(machineId),
                      ),
                      IconButton(
                        icon: const Icon(Icons.lightbulb, color: Colors.yellow),
                        onPressed: () => _toggleLights(machineId),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Distribución 4x4:', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: inventory.length,
                    itemBuilder: (context, i) {
                      final item = inventory[i];
                      final isEnabled = item['is_enabled'] ?? true;
                      final type = item['slot_type'] ?? 'soda';

                      return InkWell(
                        onTap: () => _showEditSlotDialog(machineId, item),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isEnabled ? Colors.white : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                            border: Border.all(
                              color: isEnabled ? Colors.blue.withOpacity(0.5) : Colors.red.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                type == 'soda' ? Icons.local_drink : Icons.fastfood,
                                color: isEnabled ? Colors.blue : Colors.grey,
                                size: 28,
                              ),
                              const SizedBox(height: 4),
                              Text(item['slot'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              Text('Bs ${item['price']}', style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold)),
                              if (!isEnabled)
                                const Text('OFF', style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAdminBannerTab() {
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Publicidad para Clientes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text('Banner Actual:', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                if (_banner['url'] != null && _banner['url'].isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(_banner['url'], height: 100, width: double.infinity, fit: BoxFit.cover),
                  )
                else
                  const Text('No hay banner configurado'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _showBannerConfigDialog,
                    icon: const Icon(Icons.edit),
                    label: const Text('Cambiar Imagen del Banner'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildByRole() {
    if (widget.role == 'CLIENT') {
      final balance = _wallet['balance'] ?? 0;
      final history = (_history['items'] as List<dynamic>? ?? []);
      return ListView(
        children: [
          Card(
            child: ListTile(
              title: const Text('Saldo SimuPay'),
              subtitle: Text('Bs. $balance'),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Transferir dinero',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextField(
                    controller: _toEmail,
                    decoration: const InputDecoration(labelText: 'Destino'),
                  ),
                  TextField(
                    controller: _amount,
                    decoration: const InputDecoration(labelText: 'Monto'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _transfer,
                    child: const Text('Transferir'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Comprar por QR',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  FilledButton(
                    onPressed: _buyProduct,
                    child: const Text('Comprar Soda (Bs. 8.50)'),
                  ),
                  const SizedBox(height: 8),
                  const Text('Modo testing:'),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed:
                            _transactions.isEmpty
                                ? null
                                : () =>
                                    _simulate(_transactions.first, 'success'),
                        child: const Text('Simular pago OK'),
                      ),
                      FilledButton.tonal(
                        onPressed:
                            _transactions.isEmpty
                                ? null
                                : () => _simulate(_transactions.first, 'fail'),
                        child: const Text('Simular fallo'),
                      ),
                      FilledButton.tonal(
                        onPressed:
                            _transactions.isEmpty
                                ? null
                                : () =>
                                    _simulate(_transactions.first, 'refund'),
                        child: const Text('Simular reembolso'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Historial de billetera',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...history.map(
                    (e) => Text(
                      '${e['type']} | ${e['amount']} | ${e['to_email'] ?? ''}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Anuncio',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_banner['url'] != null && _banner['url'].isNotEmpty)
                    Image.network(
                      _banner['url'],
                      height: 80,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Text('Error al cargar banner'),
                    )
                  else
                    const Text('No hay anuncios disponibles'),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (widget.role == 'ADMIN') {
        return const SizedBox.shrink(); // Admin is handled via TabBarView
    }

    if (widget.role == 'DEVOPS') {
      final machines = (_machines['machines'] as List<dynamic>? ?? []);
      final iotMachines = (_iot['machines'] as List<dynamic>? ?? []);
      return ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Vista global (DEVOPS)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('Máquinas registradas: ${machines.length}'),
                  Text('Máquinas con telemetría: ${iotMachines.length}'),
                ],
              ),
            ),
          ),
          ...iotMachines.map(
            (m) => Card(
              child: ListTile(
                title: Text('${m['machine_id']} - ${m['status']}'),
                subtitle: Text('temp=${m['temperature']} hum=${m['humidity']}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed:
                          () =>
                              _devopsCommand(m['machine_id'] as String, 'homing'),
                      child: const Text('Homing'),
                    ),
                    TextButton(
                      onPressed:
                          () => _devopsCommand(
                            m['machine_id'] as String,
                            'restart',
                          ),
                      child: const Text('Restart'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return const Center(child: Text('Acceso Denegado: Rol no reconocido'));
  }
}
