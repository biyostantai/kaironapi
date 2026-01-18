import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'time_service.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

class AlarmService {
  static Future<void> initialize({
    Future<void> Function(NotificationResponse)? onDidReceiveNotificationResponse,
  }) async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
  }
  static NotificationDetails _buildDetails({
    required bool isReminder,
    required bool loud,
    required bool isCritical,
    String? soundPath,
    bool useCustomSound = false,
  }) {
    final actions = <AndroidNotificationAction>[];
    if (!isReminder) {
      actions.addAll([
        const AndroidNotificationAction(
          'DISMISS_ALARM',
          'Bỏ qua',
          cancelNotification: true,
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'SNOOZE_ALARM',
          'Tạm dừng',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ]);
    }
    final android = AndroidNotificationDetails(
      isReminder ? 'kairo_reminder_v2' : 'kairo_alarm_v2',
      isReminder ? 'Nhắc trước giờ học' : 'Báo thức Kairon',
      channelDescription: isReminder
          ? 'Thông báo nhắc trước giờ học cho Kairon'
          : 'Báo thức toàn màn hình của Kairon',
      importance: isReminder
          ? (isCritical ? Importance.max : Importance.high)
          : Importance.max,
      priority: isReminder
          ? (isCritical ? Priority.max : Priority.high)
          : Priority.max,
      fullScreenIntent: isReminder ? isCritical : true,
      category: AndroidNotificationCategory.alarm,
      playSound: true,
      sound: useCustomSound && soundPath != null
          ? UriAndroidNotificationSound(soundPath)
          : null,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(
        [0, 500, 300, 700],
      ),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      ongoing: !isReminder,
      autoCancel: isReminder,
      actions: actions.isEmpty ? null : actions,
    );
    return NotificationDetails(android: android);
  }

  static Future<void> scheduleReminder({
    required int id,
    required DateTime time,
    required String title,
    required String body,
    bool isCritical = false,
  }) async {
    final now = TimeService.now();
    final scheduled = time.isBefore(now) ? now : time;
    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduled, tz.local),
      _buildDetails(
        isReminder: true,
        loud: false,
        isCritical: isCritical,
      ),
      androidScheduleMode: isCritical
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }

  static Future<void> scheduleAlarm({
    required int id,
    required DateTime time,
    required String title,
    required String body,
    required bool loud,
    String? soundPath,
    bool useCustomSound = false,
  }) async {
    final now = TimeService.now();
    final scheduled = time.isBefore(now) ? now : time;
    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduled, tz.local),
      _buildDetails(
        isReminder: false,
        loud: loud,
        isCritical: true,
        soundPath: soundPath,
        useCustomSound: useCustomSound,
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
      payload: 'alarm|$title|$body',
    );
  }

  static Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }

  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  static Future<void> previewRingtone({
    required bool loud,
    String? soundPath,
    bool useCustomSound = false,
  }) async {
    final details = _buildDetails(
      isReminder: false,
      loud: loud,
      isCritical: true,
      soundPath: soundPath,
      useCustomSound: useCustomSound,
    );
    await _notifications.show(
      9999,
      'KaironAI',
      'Xem thử nhạc chuông',
      details,
    );
  }
}
