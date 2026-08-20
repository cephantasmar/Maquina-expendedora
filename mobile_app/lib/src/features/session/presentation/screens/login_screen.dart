import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/network/api_client.dart';
import '../../../dashboard/presentation/screens/role_dashboard_screen.dart';class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _email = TextEditingController(
    text: 'client@grog.com',
  );
  final TextEditingController _password = TextEditingController(text: '123456');
  bool _loading = false;
  String _error = '';

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _canCheckBiometrics = false;
  bool _hasSavedCredentials = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    bool canCheckBiometrics = false;
    try {
      canCheckBiometrics = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (e) {
      canCheckBiometrics = false;
    }
    
    final savedEmail = await _secureStorage.read(key: 'saved_email');
    final savedPassword = await _secureStorage.read(key: 'saved_password');
    
    if (mounted) {
      setState(() {
        _canCheckBiometrics = canCheckBiometrics;
        _hasSavedCredentials = savedEmail != null && savedPassword != null;
      });
    }
  }

  Future<void> _authenticateBiometrics() async {
    bool authenticated = false;
    try {
      setState(() => _error = '');
      authenticated = await _auth.authenticate(
        localizedReason: 'Escanea tu huella dactilar para iniciar sesión',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      setState(() => _error = e.toString());
      return;
    }

    if (authenticated) {
      final savedEmail = await _secureStorage.read(key: 'saved_email');
      final savedPassword = await _secureStorage.read(key: 'saved_password');
      if (savedEmail != null && savedPassword != null) {
        setState(() {
          _email.text = savedEmail;
          _password.text = savedPassword;
        });
        await _submit();
      }
    }
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await _api.login(_email.text.trim(), _password.text.trim());
      await _secureStorage.write(key: 'saved_email', value: _email.text.trim());
      await _secureStorage.write(key: 'saved_password', value: _password.text.trim());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder:
              (_) => RoleDashboardScreen(
                email: res['email'] as String,
                role: res['role'] as String,
              ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 380,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Grog Login',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Text(_loading ? 'Ingresando...' : 'Ingresar'),
                    ),
                  ),
                  if (_canCheckBiometrics && _hasSavedCredentials) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _authenticateBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Iniciar sesión con huella'),
                    ),
                  ],
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_error, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
