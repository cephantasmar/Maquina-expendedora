import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthController extends ChangeNotifier {
  final AuthRepository _authRepository;

  AuthSession? _session;
  bool _loading = false;
  String? _error;

  AuthController({required AuthRepository authRepository})
    : _authRepository = authRepository;

  bool get isAuthenticated => _session != null;
  bool get loading => _loading;
  String? get error => _error;
  AuthSession? get session => _session;

  Future<void> bootstrap() async {
    _loading = true;
    notifyListeners();
    try {
      final ip = await _authRepository.loadIp();
      if (ip != null) {
        AppConfig.baseUrl = ip;
      }
      _session = await _authRepository.loadSession();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> login({
    required String email,
    required String password,
    String? serverIp,
  }) async {
    _setLoading();
    try {
      if (serverIp != null && serverIp.trim().isNotEmpty) {
        AppConfig.baseUrl = serverIp;
        await _authRepository.saveIp(serverIp);
      }
      final session = await _authRepository.login(email: email, password: password);
      
      // Validación estricta de roles
      const allowedRoles = ['CLIENT', 'ADMIN', 'DEVOPS'];
      if (!allowedRoles.contains(session.role.toUpperCase())) {
        await _authRepository.logout();
        throw Exception('Acceso denegado: El rol ${session.role} no tiene permisos.');
      }
      
      _session = session;
      _error = null;
      return true;
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('401') || errorStr.contains('invalid credentials') || errorStr.contains('contraseña incorrecta')) {
        _error = 'Contraseña incorrecta. Por favor, verifica tus datos.';
      } else if (errorStr.contains('404') || errorStr.contains('user not found') || errorStr.contains('usuario no encontrado')) {
        _error = 'El usuario no existe. Regístrate para comenzar.';
      } else if (errorStr.contains('socketexception') || errorStr.contains('connection refused')) {
        _error = 'No se pudo conectar con el servidor. Verifica la IP y tu conexión.';
      } else {
        _error = e.toString().replaceFirst('Exception: ', '').replaceFirst('AppException: ', '');
      }
      return false;
    } finally {
      _clearLoading();
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    String? serverIp,
  }) async {
    _setLoading();
    try {
      if (serverIp != null && serverIp.trim().isNotEmpty) {
        AppConfig.baseUrl = serverIp;
        await _authRepository.saveIp(serverIp);
      }
      final session = await _authRepository.register(
        email: email,
        password: password,
        fullName: fullName,
      );

      // Validación estricta de roles también en registro
      const allowedRoles = ['CLIENT', 'ADMIN', 'DEVOPS'];
      if (!allowedRoles.contains(session.role.toUpperCase())) {
        await _authRepository.logout();
        throw Exception('Registro fallido: Rol ${session.role} no permitido.');
      }

      _session = session;
      return true;
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('409') || errorStr.contains('already exists')) {
        _error = 'Este correo ya está registrado. Intenta iniciar sesión.';
      } else {
        _error = e.toString().replaceFirst('Exception: ', '').replaceFirst('AppException: ', '');
      }
      return false;
    } finally {
      _clearLoading();
    }
  }

  Future<bool> linkSimupay(String simupayEmail) async {
    if (_session == null) return false;
    _setLoading();
    try {
      _session = await _authRepository.linkSimupay(
        email: _session!.email,
        simupayEmail: simupayEmail,
      );
      _error = null;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _clearLoading();
    }
  }

  Future<void> logout() async {
    _loading = true;
    notifyListeners();
    await _authRepository.logout();
    _session = null;
    _loading = false;
    notifyListeners();
  }

  void _setLoading() {
    _loading = true;
    _error = null;
    notifyListeners();
  }

  void _clearLoading() {
    _loading = false;
    notifyListeners();
  }
}
