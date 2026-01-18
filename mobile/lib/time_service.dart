import 'dart:convert';

import 'package:http/http.dart' as http;

class GlobalTime {
  static DateTime? _lastApiNow;
  static DateTime? _lastDeviceNow;

  static void update(DateTime apiNow, DateTime deviceNow) {
    _lastApiNow = apiNow;
    _lastDeviceNow = deviceNow;
  }

  static DateTime now() {
    if (_lastApiNow == null || _lastDeviceNow == null) {
      return DateTime.now();
    }
    final diff = DateTime.now().difference(_lastDeviceNow!);
    return _lastApiNow!.add(diff);
  }
}

class TimeService {
  static const String _endpoint =
      'http://worldtimeapi.org/timezone/Asia/Ho_Chi_Minh';

  static Future<void> sync() async {
    try {
      final response = await http
          .get(Uri.parse(_endpoint))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final datetimeStr = data['datetime'] as String?;
      if (datetimeStr == null) {
        return;
      }
      final apiNow = DateTime.parse(datetimeStr);
      GlobalTime.update(apiNow, DateTime.now());
    } catch (_) {}
  }

  static DateTime now() {
    return GlobalTime.now();
  }
}
