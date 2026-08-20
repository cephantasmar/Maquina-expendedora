import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/admin_dashboard_controller.dart';

class DevOpsPanelTab extends StatelessWidget {
  const DevOpsPanelTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDashboardController>();
    final iotMachines = controller.iotMachines;

    return RefreshIndicator(
      onRefresh: () => controller.loadStats(),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Panel de Telemetría IoT',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Monitoreo técnico y control de hardware en tiempo real.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          
          if (iotMachines.isEmpty && !controller.loading)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.sensors_off, size: 48, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No hay máquinas con telemetría activa'),
                  ],
                ),
              ),
            ),

          ...iotMachines.map((m) => _buildIotMachineCard(context, controller, m)),
        ],
      ),
    );
  }

  Widget _buildIotMachineCard(
    BuildContext context,
    AdminDashboardController controller,
    dynamic m,
  ) {
    final String machineId = m['machine_id'] ?? 'N/A';
    final String status = m['status'] ?? 'unknown';
    final double temp = (m['temperature'] ?? 0.0).toDouble();
    final double hum = (m['humidity'] ?? 0.0).toDouble();
    final bool isOnline = status.toLowerCase() == 'online';

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isOnline ? Colors.green.shade100 : Colors.red.shade100,
                  child: Icon(
                    Icons.settings_input_component,
                    color: isOnline ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Máquina: $machineId',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        'Estado: ${status.toUpperCase()}',
                        style: TextStyle(
                          color: isOnline ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.blue),
                  onPressed: () => controller.loadStats(),
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(Icons.thermostat, 'Temperatura', '$temp°C', Colors.orange),
                _buildStatItem(Icons.water_drop, 'Humedad', '$hum%', Colors.blue),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmCommand(context, controller, machineId, 'homing'),
                    icon: const Icon(Icons.home_repair_service),
                    label: const Text('Homing Motors'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                      side: const BorderSide(color: Colors.indigo),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmCommand(context, controller, machineId, 'restart'),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reiniciar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ],
    );
  }

  void _confirmCommand(
    BuildContext context,
    AdminDashboardController controller,
    String machineId,
    String command,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmar $command'),
        content: Text('¿Estás seguro de enviar el comando $command a la máquina $machineId?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              controller.sendIotCommand(machineId, command);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Comando $command enviado a $machineId')),
              );
            },
            child: Text(command.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
