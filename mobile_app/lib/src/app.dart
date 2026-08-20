import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/repositories/auth_repository_impl.dart';
import 'data/repositories/profile_repository_impl.dart';
import 'data/repositories/purchase_repository_impl.dart';
import 'data/repositories/wallet_repository_impl.dart';
import 'presentation/controllers/auth_controller.dart';
import 'presentation/controllers/profile_controller.dart';
import 'presentation/controllers/purchase_controller.dart';
import 'presentation/controllers/wallet_controller.dart';
import 'presentation/controllers/admin_dashboard_controller.dart';
import 'presentation/controllers/notification_controller.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';

class GrogApp extends StatelessWidget {
  const GrogApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authRepository = AuthRepositoryImpl();
    final profileRepository = ProfileRepositoryImpl();
    final walletRepository = WalletRepositoryImpl();
    final purchaseRepository = PurchaseRepositoryImpl();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create:
              (_) =>
                  AuthController(authRepository: authRepository)..bootstrap(),
        ),
        ChangeNotifierProvider(
          create: (_) => WalletController(walletRepository: walletRepository),
        ),
        ChangeNotifierProvider(
          create:
              (_) => ProfileController(profileRepository: profileRepository),
        ),
        ChangeNotifierProvider(
          create:
              (_) => PurchaseController(purchaseRepository: purchaseRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => AdminDashboardController(),
        ),
        ChangeNotifierProvider(
          create: (_) => NotificationController(),
        ),
      ],
      child: MaterialApp(
        title: 'Grog Wallet',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5)),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        if (auth.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (auth.isAuthenticated) {
          return const DashboardScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
