import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/wallet_movement.dart';

class TransactionDetailScreen extends StatelessWidget {
  final WalletMovement movement;

  const TransactionDetailScreen({super.key, required this.movement});

  @override
  Widget build(BuildContext context) {
    final isIncome = movement.type.toLowerCase() == 'deposit' || 
                     (movement.type.toLowerCase() == 'transfer' && movement.toEmail == null); // Simplified logic
    
    final color = isIncome ? Colors.green : Colors.redAccent;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text('Detalle de Transacción'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Card Principal tipo Recibo
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                      color: color,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    movement.type.toUpperCase(),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${isIncome ? '+' : '-'} Bs. ${movement.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 32),
                  
                  _buildDetailRow('ID Transacción', movement.id.substring(0, 8).toUpperCase()),
                  _buildDetailRow('Fecha', DateFormat('dd/MM/yyyy HH:mm').format(movement.createdAt.toLocal())),
                  _buildDetailRow('Estado', 'Completado', valueColor: Colors.green),
                  
                  if (movement.fromEmail != null)
                    _buildDetailRow('Origen', movement.fromEmail!),
                  
                  if (movement.toEmail != null)
                    _buildDetailRow('Destino', movement.toEmail!),
                ],
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Volver al historial', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
