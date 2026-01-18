import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';


class HomeWidgetService {
  static const String _widgetProvider = 'NextSubjectWidgetProvider';

  static Future<void> updateNextSubject({
    required String name,
    required String timeRange,
    required String room,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('home_widget_enabled') ?? false;
    if (!enabled) {
      return;
    }

    await HomeWidget.saveWidgetData<String>('next_subject_name', name);
    await HomeWidget.saveWidgetData<String>('next_subject_time', timeRange);
    await HomeWidget.saveWidgetData<String>('next_subject_room', room);

    await HomeWidget.updateWidget(
      name: _widgetProvider,
    );
  }

  static Future<void> setWidgetEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('home_widget_enabled', enabled);
    if (!enabled) {
      await HomeWidget.saveWidgetData<String>('next_subject_name', '');
      await HomeWidget.saveWidgetData<String>('next_subject_time', '');
      await HomeWidget.saveWidgetData<String>('next_subject_room', '');
      await HomeWidget.updateWidget(
        name: _widgetProvider,
      );
    }
  }
}
