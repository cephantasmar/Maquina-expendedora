import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/admin_dashboard_controller.dart';

class AdminPanelTab extends StatefulWidget {
  const AdminPanelTab({super.key});

  @override
  State<AdminPanelTab> createState() => _AdminPanelTabState();
}

class _AdminPanelTabState extends State<AdminPanelTab> {
  int _tempInterval = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
  }

  void _refresh() {
    context.read<AdminDashboardController>().loadStats();
    context.read<AdminDashboardController>().loadTempHistory(intervalMinutes: _tempInterval);
    context.read<AdminDashboardController>().loadDistanceHistory();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDashboardController>();

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSalesCard(controller.totalSales),
          const SizedBox(height: 24),
          _buildTopSellersChart(controller.topSellers),
          const SizedBox(height: 24),
          _buildFailedSlotsChart(controller.failedSlots),
          const SizedBox(height: 24),
          _buildInventoryManagement(controller),
          const SizedBox(height: 24),
          _buildQrOutcomeChart(controller.statusBreakdown),
          const SizedBox(height: 24),
          _buildTemperatureDashboard(controller),
          const SizedBox(height: 24),
          _buildDistanceDashboard(controller),
        ],
      ),
    );
  }

  Widget _buildTopSellersChart(Map<String, List<dynamic>> topSellers) {
    if (topSellers.isEmpty) return const SizedBox.shrink();
    // Assuming one machine for now, simplify for UI demonstration
    final data = topSellers.values.first; 
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('Productos Más Vendidos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  barGroups: data.asMap().entries.map((e) => BarChartGroupData(x: e.key, barRods: [BarChartRodData(toY: (e.value['count'] as num).toDouble(), color: Colors.blue)])).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedSlotsChart(Map<String, List<dynamic>> failedSlots) {
    if (failedSlots.isEmpty) return const SizedBox.shrink();
    // Assuming one machine for now
    final data = failedSlots.values.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('Ranuras con Fallas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  barGroups: data.asMap().entries.map((e) => BarChartGroupData(x: e.key, barRods: [BarChartRodData(toY: (e.value['count'] as num).toDouble(), color: Colors.red)])).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistanceDashboard(AdminDashboardController controller) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comparativa de Sensores (M1 vs M2)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'M1 (Celeste): Inicial | M2 (Morado): Final',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (controller.distanceHistory.isEmpty)
              const Center(child: Text('No hay datos de transacciones.'))
            else
              SizedBox(
                height: 250,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: true),
                    titlesData: const FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
                    lineBarsData: [
                      LineChartBarData(
                        spots: controller.distanceHistory.asMap().entries.map((e) {
                          return FlSpot(e.key.toDouble(), (e.value['m1'] as num).toDouble());
                        }).toList(),
                        isCurved: false,
                        color: Colors.cyan,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                      ),
                      LineChartBarData(
                        spots: controller.distanceHistory.asMap().entries.map((e) {
                          return FlSpot(e.key.toDouble(), (e.value['m2'] as num).toDouble());
                        }).toList(),
                        isCurved: false,
                        color: Colors.purple,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendItem(color: Colors.cyan, label: 'M1 (Inicial)'),
                const SizedBox(width: 20),
                _LegendItem(color: Colors.purple, label: 'M2 (Final)'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryManagement(AdminDashboardController controller) {
    if (controller.machines.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: Text('Cargando máquinas...')),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gestión de Precios e Inventario',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...controller.machines.map((machine) {
          final machineId = machine['id'];
          final inventory = controller.inventories[machineId] ?? [];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ExpansionTile(
              leading: Icon(
                Icons.settings_remote,
                color: machine['status'] == 'online' ? Colors.green : Colors.grey,
              ),
              title: Text(machine['name'] ?? 'Máquina'),
              subtitle: Text('ID: $machineId | ${machine['status']}'),
              children: [
                if (inventory.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No hay productos registrados.'),
                  )
                else
                  ...inventory.map((item) {
                    return ListTile(
                      title: Text(item['product_name'] ?? 'Producto'),
                      subtitle: Text('Stock: ${item['stock']} | Precio: Bs. ${item['price']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showPriceEditDialog(
                          controller,
                          machineId,
                          item['slot'],
                          item['product_name'],
                          item['price'],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _showPriceEditDialog(
    AdminDashboardController controller,
    String machineId,
    String slot,
    String productName,
    dynamic currentPrice,
  ) {
    final textController = TextEditingController(text: currentPrice.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar Precio: $productName'),
        content: TextField(
          controller: textController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Nuevo Precio (Bs.)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPrice = double.tryParse(textController.text);
              if (newPrice != null) {
                Navigator.pop(context);
                await controller.updatePrice(machineId, slot, newPrice);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesCard(double total) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.blue.shade700, Colors.blue.shade500],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.monetization_on, color: Colors.white, size: 28),
                SizedBox(width: 8),
                Text(
                  'Ventas Totales Realizadas',
                  style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Bs. ${total.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Suma de todas las transacciones completadas con éxito.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrOutcomeChart(Map<String, int> breakdown) {
    if (breakdown.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Efectividad de Códigos QR',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Distribución de resultados tras el escaneo.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: [
                    if (breakdown.containsKey('COMPLETED'))
                      PieChartSectionData(
                        value: breakdown['COMPLETED']!.toDouble(),
                        title: 'Éxito',
                        color: Colors.green,
                        radius: 50,
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    if (breakdown.containsKey('REFUNDED'))
                      PieChartSectionData(
                        value: breakdown['REFUNDED']!.toDouble(),
                        title: 'Devuelto',
                        color: Colors.red,
                        radius: 50,
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    if (breakdown.containsKey('FAILED'))
                      PieChartSectionData(
                        value: breakdown['FAILED']!.toDouble(),
                        title: 'Falla',
                        color: Colors.orange,
                        radius: 50,
                        titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildLegend(),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _LegendItem(color: Colors.green, label: 'Confirmadas'),
        _LegendItem(color: Colors.red, label: 'Devueltas'),
        _LegendItem(color: Colors.orange, label: 'Sin Acción'),
      ],
    );
  }

  Widget _buildTemperatureDashboard(AdminDashboardController controller) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monitoreo de Temperatura',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Historial de la cadena de frío.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                DropdownButton<int>(
                  value: _tempInterval,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 min')),
                    DropdownMenuItem(value: 10, child: Text('10 min')),
                    DropdownMenuItem(value: 60, child: Text('1 hora')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _tempInterval = val);
                      controller.loadTempHistory(intervalMinutes: val);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (controller.tempHistory.isEmpty)
              const Center(child: Text('No hay datos suficientes.'))
            else
              SizedBox(
                height: 250,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: true),
                    titlesData: const FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
                    lineBarsData: [
                      LineChartBarData(
                        spots: controller.tempHistory.asMap().entries.map((e) {
                          return FlSpot(e.key.toDouble(), (e.value['temperature'] as num).toDouble());
                        }).toList(),
                        isCurved: true,
                        color: Colors.orange,
                        barWidth: 3,
                        belowBarData: BarAreaData(show: true, color: Colors.orange.withOpacity(0.1)),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Eje X: Tiempo (Relativo) | Eje Y: Grados Celsius',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
