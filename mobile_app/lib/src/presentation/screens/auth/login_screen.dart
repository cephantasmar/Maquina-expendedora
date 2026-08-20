import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../controllers/auth_controller.dart';
import '../dashboard/dashboard_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _ipCtrl = TextEditingController(text: AppConfig.baseUrl);
  final _formKey = GlobalKey<FormState>();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  bool _rememberPassword = false;
  bool _fingerprintAvailable = false;
  bool _fingerprintEnabled = false;
  bool _hasSavedCredentials = false;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = await _secureStorage.read(key: 'saved_email');
    final savedPassword = await _secureStorage.read(key: 'saved_password');
    final savedIp = await _secureStorage.read(key: 'saved_ip');

    bool fingerAvailable = false;
    try {
      fingerAvailable = await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
    } catch (_) {}

    final fingerEnabled = prefs.getBool('fingerprint_enabled') ?? false;
    final hasCreds = savedEmail != null && savedPassword != null;

    if (mounted) {
      setState(() {
        _fingerprintAvailable = fingerAvailable;
        _fingerprintEnabled = fingerEnabled;
        _hasSavedCredentials = hasCreds;

        if (hasCreds) {
          _emailCtrl.text = savedEmail!;
          _passwordCtrl.text = savedPassword!;
          _rememberPassword = true;
        }
        if (savedIp != null) {
          _ipCtrl.text = savedIp;
        }
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    final ok = await auth.login(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text.trim(),
      serverIp: _ipCtrl.text.trim(),
    );
    if (!mounted) return;

    if (ok) {
      // Save or clear credentials based on checkbox
      if (_rememberPassword) {
        await _secureStorage.write(key: 'saved_email', value: _emailCtrl.text.trim());
        await _secureStorage.write(key: 'saved_password', value: _passwordCtrl.text.trim());
        await _secureStorage.write(key: 'saved_ip', value: _ipCtrl.text.trim());
      } else {
        await _secureStorage.delete(key: 'saved_email');
        await _secureStorage.delete(key: 'saved_password');
        await _secureStorage.delete(key: 'saved_ip');
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(auth.error ?? 'No se pudo iniciar sesión'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loginWithFingerprint() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Escanea tu huella dactilar para iniciar sesión',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (!authenticated) return;

      final savedEmail = await _secureStorage.read(key: 'saved_email');
      final savedPassword = await _secureStorage.read(key: 'saved_password');
      final savedIp = await _secureStorage.read(key: 'saved_ip');

      if (savedEmail != null && savedPassword != null) {
        setState(() {
          _emailCtrl.text = savedEmail;
          _passwordCtrl.text = savedPassword;
          if (savedIp != null) _ipCtrl.text = savedIp;
        });
        await _submit();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final theme = Theme.of(context);
    final showFingerprintButton = _fingerprintAvailable && _fingerprintEnabled && _hasSavedCredentials;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // IP Field at the top
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.dns, size: 20, color: Colors.indigo),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _ipCtrl,
                              decoration: const InputDecoration(
                                hintText: 'IP del Servidor (ej: 192.168.1.5)',
                                labelText: 'Servidor',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              style: const TextStyle(fontSize: 14),
                              validator:
                                  (v) =>
                                      (v == null || v.isEmpty)
                                          ? 'Requerido'
                                          : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    const Icon(
                      Icons.local_drink_rounded,
                      size: 80,
                      color: Color(0xFF4F46E5),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Grog Wallet',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bienvenido de nuevo. Ingresa tus datos.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 40),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Correo Electrónico',
                        prefixIcon: const Icon(Icons.email_outlined),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator:
                          (v) =>
                              (v == null || !v.contains('@'))
                                  ? 'Ingresa un correo válido'
                                  : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator:
                          (v) =>
                              (v == null || v.length < 6)
                                  ? 'Mínimo 6 caracteres'
                                  : null,
                    ),
                    const SizedBox(height: 8),

                    // Checkbox: Recordar contraseña
                    Row(
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _rememberPassword,
                            onChanged: (v) => setState(() => _rememberPassword = v ?? false),
                            activeColor: const Color(0xFF4F46E5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() => _rememberPassword = !_rememberPassword),
                          child: const Text(
                            'Recordar contraseña',
                            style: TextStyle(fontSize: 14, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: auth.loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child:
                          auth.loading
                              ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Text(
                                'Iniciar Sesión',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                    ),

                    // Botón huella dactilar
                    if (showFingerprintButton) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: auth.loading ? null : _loginWithFingerprint,
                        icon: const Icon(Icons.fingerprint, size: 28),
                        label: const Text('Iniciar sesión con huella'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFF4F46E5)),
                          foregroundColor: const Color(0xFF4F46E5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('¿No tienes cuenta?'),
                        TextButton(
                          onPressed:
                              auth.loading
                                  ? null
                                  : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const RegisterScreen(),
                                      ),
                                    );
                                  },
                          child: const Text(
                            'Regístrate',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
