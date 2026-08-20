import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../controllers/purchase_controller.dart';
import '../../controllers/wallet_controller.dart';
import '../../controllers/admin_dashboard_controller.dart';
import '../auth/login_screen.dart';
import '../purchase/payment_confirmation_screen.dart';
import '../purchase/qr_scanner_screen.dart';
import '../profile/profile_screen.dart';
import '../wallet/history_screen.dart';
import '../wallet/transfer_screen.dart';
import '../../../domain/entities/auth_session.dart';
import '../../controllers/notification_controller.dart';
import '../notifications/notification_screens.dart';
import 'admin_panel_tab.dart';
import 'devops_panel_tab.dart';
import '../settings/settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription<Uri>? _linkSubscription;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _linkSubscription = AppLinks().uriLinkStream.listen((uri) {
      if (uri.scheme == 'grog' &&
          uri.host == 'wallet' &&
          uri.path == '/callback') {
        final linkedEmail = uri.queryParameters['email'];
        _load(linkWallet: true, linkedEmail: linkedEmail);
      }
    });
  }

  Future<void> _load({bool linkWallet = false, String? linkedEmail}) async {
    final auth = context.read<AuthController>();
    final profile = context.read<ProfileController>();
    final wallet = context.read<WalletController>();
    final session = auth.session;
    if (session == null) return;

    await profile.load(session.email);

    if (linkWallet && linkedEmail != null) {
      await auth.linkSimupay(linkedEmail);
      await wallet.load(linkedEmail);
      return;
    }

    final targetEmail = session.simupayEmail ?? session.email;
    await wallet.load(targetEmail);
    
    if (context.mounted) {
      context.read<NotificationController>().loadNotifications(session.email);
    }
    
    // Cargar banner (a través del admin controller) para todos
    if (context.mounted) {
      context.read<AdminDashboardController>().loadStats();
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final profile = context.watch<ProfileController>();
    final wallet = context.watch<WalletController>();
    final session = auth.session;
    if (session == null) return const LoginScreen();

    final walletInfo = wallet.wallet;
    final linked = walletInfo?.linked ?? false;
    final isAdmin = session.role == 'ADMIN';
    final isDevOps = session.role == 'DEVOPS';

    return DefaultTabController(
      length: isAdmin ? 4 : (isDevOps ? 2 : 1),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FE),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Grog Wallet',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh, color: Colors.black54),
            ),
            Consumer<NotificationController>(
              builder: (context, ctrl, _) => Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NotificationListScreen()),
                      );
                    },
                    icon: const Icon(Icons.notifications_outlined, color: Colors.black54),
                  ),
                  if (ctrl.unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '${ctrl.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              icon: const Icon(Icons.person_outline, color: Colors.black54),
            ),
            IconButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.settings_outlined, color: Colors.black54),
            ),
            IconButton(
              onPressed: () async {
                await auth.logout();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              },
              icon: const Icon(Icons.logout, color: Colors.redAccent),
            ),
            const SizedBox(width: 8),
          ],
          bottom:
              isAdmin
                  ? const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Mi Billetera', icon: Icon(Icons.wallet)),
                      Tab(text: 'Ventas', icon: Icon(Icons.analytics)),
                      Tab(text: 'Máquinas', icon: Icon(Icons.grid_view)),
                      Tab(text: 'Publicidad', icon: Icon(Icons.campaign)),
                    ],
                    labelColor: Color(0xFF4F46E5),
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Color(0xFF4F46E5),
                  )
                  : (isDevOps
                      ? const TabBar(
                          tabs: [
                            Tab(text: 'IoT Telemetría', icon: Icon(Icons.sensors)),
                            Tab(text: 'Máquinas', icon: Icon(Icons.settings_remote)),
                          ],
                          labelColor: Color(0xFF4F46E5),
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: Color(0xFF4F46E5),
                        )
                      : null),
        ),
        body: isAdmin
            ? TabBarView(
                children: [
                  _buildMainDashboard(context, profile, wallet, session, linked, walletInfo),
                  _buildAdminSalesTab(context),
                  _buildAdminMachinesTab(context),
                  _buildAdminBannerTab(context),
                ],
              )
            : (isDevOps
                ? TabBarView(
                    children: [
                      const DevOpsPanelTab(),
                      _buildAdminMachinesTab(context),
                    ],
                  )
                : _buildMainDashboard(context, profile, wallet, session, linked, walletInfo)),
      ),
    );
  }

  Widget _buildAdminSalesTab(BuildContext context) {
    return const AdminPanelTab();
  }

  Widget _buildAdminMachinesTab(BuildContext context) {
    final controller = context.watch<AdminDashboardController>();
    if (controller.machines.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ...controller.machines.map((machine) {
          final machineId = machine['id'];
          final inventory = controller.inventories[machineId] ?? [];

          return Card(
            margin: const EdgeInsets.only(bottom: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF4F46E5),
                    child: Icon(Icons.settings_remote, color: Colors.white),
                  ),
                  title: Text(machine['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: $machineId | Status: ${machine['status']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.bar_chart, color: Colors.orange),
                        onPressed: () => _showTopSellersDialog(context, controller, machineId),
                      ),
                      IconButton(
                        icon: const Icon(Icons.lightbulb_outline, color: Colors.amber),
                        onPressed: () => controller.toggleLights(machineId),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Distribución 4x4:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: inventory.length,
                    itemBuilder: (context, i) {
                      final item = inventory[i];
                      final isEnabled = item['is_enabled'] ?? true;
                      final type = item['slot_type'] ?? 'soda';

                      return InkWell(
                        onTap: () => _showEditSlotDialog(context, controller, machineId, item),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isEnabled ? Colors.white : Colors.grey[100],
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                            ],
                            border: Border.all(
                              color: isEnabled ? const Color(0xFF4F46E5).withOpacity(0.3) : Colors.red.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                type == 'soda' ? Icons.local_drink : Icons.fastfood,
                                color: isEnabled ? const Color(0xFF4F46E5) : Colors.grey,
                                size: 28,
                              ),
                              const SizedBox(height: 4),
                              Text(item['slot'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Bs. ${item['price']}', style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                              if (!isEnabled)
                                const Text('OFF', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
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

  void _showEditSlotDialog(BuildContext context, AdminDashboardController controller, String machineId, dynamic item) {
    final priceController = TextEditingController(text: item['price'].toString());
    bool isEnabled = item['is_enabled'] ?? true;
    String slotType = item['slot_type'] ?? 'soda';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Gestionar Slot ${item['slot']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Precio (Bs.)', border: OutlineInputBorder()),
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
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final price = double.tryParse(priceController.text);
                if (price != null) {
                  Navigator.pop(context);
                  await controller.updatePrice(machineId, item['slot'], price);
                  await controller.updateSlotStatus(machineId, item['slot'], isEnabled, slotType);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTopSellersDialog(BuildContext context, AdminDashboardController controller, String machineId) {
    final stats = controller.topSellers[machineId] ?? [];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Lo más vendido'),
        content: SizedBox(
          width: double.maxFinite,
          child: stats.isEmpty
              ? const Text('No hay ventas registradas.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: stats.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text('Slot ${stats[i]['slot']}'),
                    trailing: Text('${stats[i]['count']} ventas', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _buildAdminBannerTab(BuildContext context) {
    final controller = context.watch<AdminDashboardController>();
    final bannerUrl = controller.banner['url'] ?? '';
    final urlController = TextEditingController(text: bannerUrl);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Banner Publicitario', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text('Este banner se mostrará a todos los clientes.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        if (bannerUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: bannerUrl.startsWith('data:') 
              ? Image.memory(
                  base64Decode(bannerUrl.split(',').last),
                  height: 120, width: double.infinity, fit: BoxFit.cover,
                )
              : Image.network(bannerUrl, height: 120, width: double.infinity, fit: BoxFit.cover),
          )
        else
          Container(
            height: 120,
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(20)),
            child: const Center(child: Text('No hay imagen configurada')),
          ),
        const SizedBox(height: 24),
        TextField(
          controller: urlController,
          decoration: const InputDecoration(labelText: 'URL de la imagen', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => controller.updateBanner(urlController.text),
                icon: const Icon(Icons.link),
                label: const Text('Usar URL'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final picker = ImagePicker();
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
                  if (image != null) {
                    final bytes = await image.readAsBytes();
                    final base64Image = 'data:image/${image.path.split('.').last};base64,${base64Encode(bytes)}';
                    await controller.updateBanner(base64Image);
                  }
                },
                icon: const Icon(Icons.image),
                label: const Text('Subir Imagen'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMainDashboard(
    BuildContext context,
    ProfileController profile,
    WalletController wallet,
    AuthSession session,
    bool linked,
    dynamic walletInfo,
  ) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        children: [
          // Profile & Balance Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _DashboardAvatar(
                      base64Image: profile.profile?.avatarBase64,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.profile?.displayName ??
                                session.email.split('@').first,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            session.email,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (session.role == 'ADMIN')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'ADMIN',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  'Saldo disponible',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      linked
                          ? 'Bs. ${walletInfo!.balance.toStringAsFixed(2)}'
                          : 'No vinculado',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (wallet.loading)
                      const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                  ],
                ),
                if (wallet.error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      wallet.error!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 32),

          if (!linked) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange.shade800,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Activa tu billetera',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Debes vincular tu cuenta con SimuPay para realizar pagos y transferencias.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      final uri = Uri.parse(
                        '${AppConfig.simupayWebUrl}/signup',
                      );
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Crear cuenta SimuPay'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          if (linked) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Vinculado a: ${walletInfo?.email}',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          const Text(
            'Operaciones',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),

          // Quick Actions Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.4,
            children: [
              _QuickActionTile(
                icon: Icons.qr_code_scanner_rounded,
                label: 'Pagar con QR',
                color: const Color(0xFF4F46E5),
                onTap:
                    linked
                        ? () async {
                          final rawCode = (await Navigator.of(
                            context,
                          ).push<String>(
                            MaterialPageRoute(
                              builder: (_) => const QrScannerScreen(),
                            ),
                          ))?.trim();

                          if (!context.mounted ||
                              rawCode == null ||
                              rawCode.isEmpty) {
                            return;
                          }

                          debugPrint('QR Detectado: $rawCode');

                          final purchase = context.read<PurchaseController>();
                          bool success = false;
                          bool openTransfer = false;

                          // Lógica inteligente de detección de QR
                          if (rawCode.contains('/init/')) {
                            // Es un QR de Máquina (Arduino)
                            final normalizedRawCode = rawCode
                                .replaceAll('http;//', 'http://')
                                .replaceAll('https;//', 'https://');
                            final uri = Uri.tryParse(normalizedRawCode);

                            String machineId;
                            String? productId;
                            double? amount;
                            if (uri != null && uri.path.contains('/init/')) {
                              machineId = uri.pathSegments.last;
                              productId = uri.queryParameters['product_id'];
                              amount = double.tryParse(
                                uri.queryParameters['amount'] ?? '',
                              );
                            } else {
                              final split = normalizedRawCode.split('/init/');
                              final machinePart = split.last.split('?').first;
                              machineId = machinePart;
                            }
                            
                            debugPrint('Iniciando TX Máquina: $machineId');
                            success = await purchase.initMachineTransaction(
                              machineId,
                              productId: productId,
                              amount: amount,
                            );
                          } else if (rawCode.startsWith('simupay://pay')) {
                            final uri = Uri.tryParse(rawCode);
                            final hasEnrollment =
                                (uri?.queryParameters['enrollment'] ?? '')
                                    .isNotEmpty;
                            final hasRecipient =
                                (uri?.queryParameters['to'] ?? '').isNotEmpty;

                            if (hasRecipient && !hasEnrollment) {
                              openTransfer = true;
                            } else {
                              // Es un QR de pago de sesión SimuPay
                              // Formato: simupay://pay?id=...&enrollment=TX_ID
                              try {
                                final txId = uri?.queryParameters['enrollment'];
                                if (txId != null && txId.isNotEmpty) {
                                  success = await purchase.loadTransaction(
                                    txId,
                                  );
                                } else {
                                  final id = uri?.queryParameters['id'];
                                  if (id != null && id.isNotEmpty) {
                                    success = await purchase.loadTransaction(
                                      id,
                                    );
                                  } else {
                                    success = await purchase.loadTransaction(
                                      rawCode,
                                    );
                                  }
                                }
                              } catch (e) {
                                success = await purchase.loadTransaction(
                                  rawCode,
                                );
                              }
                            }
                          } else if (rawCode.startsWith('simupay://user/')) {
                            openTransfer = true;
                          } else {
                            // Es un ID de transacción de plataforma directo
                            try {
                              success = await purchase.loadTransaction(rawCode);
                            } catch (e) {
                              openTransfer = true;
                            }
                          }

                          if (!context.mounted) return;

                          if (openTransfer) {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (_) => TransferScreen(
                                      initialQrData: rawCode,
                                    ),
                              ),
                            );
                            if (!context.mounted) return;
                            await _load();
                            return;
                          }

                          if (success && purchase.transaction != null) {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (_) => PaymentConfirmationScreen(
                                      transactionId: purchase.transaction!.id,
                                    ),
                              ),
                            );
                            if (!context.mounted) return;
                            await _load();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  purchase.error ?? 'Error al procesar QR',
                                ),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                        : null,
              ),
              _QuickActionTile(
                icon: Icons.send_to_mobile_rounded,
                label: 'Transferir',
                color: const Color(0xFF10B981),
                onTap:
                    linked
                        ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TransferScreen(),
                          ),
                        )
                        : null,
              ),
              _QuickActionTile(
                icon: Icons.history_rounded,
                label: 'Historial',
                color: const Color(0xFFF59E0B),
                onTap:
                    linked
                        ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const HistoryScreen(),
                          ),
                        )
                        : null,
              ),
              _QuickActionTile(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Vincular',
                color: const Color(0xFF6366F1),
                onTap: () async {
                  final uri = Uri.parse(
                    '${AppConfig.simupayWebUrl}/login?redirect=grog://wallet/callback',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  } else {
                    // Si no puede abrir la URL directa, intentamos con la base
                    await _load(linkWallet: true);
                  }
                },
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          // Banner Publicitario para Clientes
          Consumer<AdminDashboardController>(
            builder: (context, adminCtrl, _) {
              final bannerUrl = adminCtrl.banner['url'] ?? '';
              if (bannerUrl.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Anuncio',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: bannerUrl.startsWith('data:')
                      ? Image.memory(
                          base64Decode(bannerUrl.split(',').last),
                          height: 100, width: double.infinity, fit: BoxFit.cover,
                        )
                      : Image.network(
                          bannerUrl,
                          height: 100,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = onTap == null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      disabled ? Colors.grey.shade100 : color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: disabled ? Colors.grey : color,
                  size: 24,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: disabled ? Colors.grey : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardAvatar extends StatelessWidget {
  final String? base64Image;

  const _DashboardAvatar({required this.base64Image});

  @override
  Widget build(BuildContext context) {
    if (base64Image == null || base64Image!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.person, color: Colors.white, size: 24),
      );
    }
    final bytes = base64Decode(base64Image!);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: CircleAvatar(
        radius: 20,
        backgroundImage: MemoryImage(Uint8List.fromList(bytes)),
      ),
    );
  }
}
