class AppConfig {
  static String _baseUrl = 'http://10.0.2.2';

  static String get baseUrl => _baseUrl;

  static set baseUrl(String value) {
    var formatted = value.trim();
    if (formatted.isEmpty) return;
    formatted = formatted.replaceAll('http;//', 'http://');
    formatted = formatted.replaceAll('https;//', 'https://');
    if (!formatted.startsWith('http://') && !formatted.startsWith('https://')) {
      formatted = 'http://$formatted';
    }

    final uri = Uri.tryParse(formatted);
    if (uri == null || uri.host.isEmpty) return;

    // Guardamos solo scheme + host para evitar puertos duplicados.
    _baseUrl = '${uri.scheme}://${uri.host}';
  }

  static String serviceUrl(int port) {
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null || uri.host.isEmpty) {
      return 'http://10.0.2.2:$port';
    }
    return '${uri.scheme}://${uri.host}:$port';
  }

  static String get authUrl => serviceUrl(8030);
  static String get orchestratorUrl => serviceUrl(8010);
  static String get simupayUrl => serviceUrl(8020);
  static String get simupayWebUrl => serviceUrl(5174);
  static String get vendingUrl => serviceUrl(8040);
  static String get iotUrl => serviceUrl(8050);
  static String get notificationUrl => serviceUrl(8070);
}
