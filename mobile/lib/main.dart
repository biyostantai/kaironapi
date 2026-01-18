import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'alarm_service.dart';
import 'home_widget.dart';
import 'login_page.dart';
import 'persona_page.dart';
import 'chat_page.dart';
import 'camera_page.dart';
import 'time_service.dart';


const String backendBaseUrl = 'https://kaironapi.onrender.com';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

const MethodChannel _systemAlarmChannel =
    MethodChannel('com.example.sep_lich/alarm');

Future<void> openSystemAlarmForSchedule(SubjectSchedule subject) async {
  int weekdayFromText(String text, int fallbackWeekday) {
    final normalized = text.trim().toLowerCase();
    if (normalized.contains('thứ 2')) return DateTime.monday;
    if (normalized.contains('thứ 3')) return DateTime.tuesday;
    if (normalized.contains('thứ 4')) return DateTime.wednesday;
    if (normalized.contains('thứ 5')) return DateTime.thursday;
    if (normalized.contains('thứ 6')) return DateTime.friday;
    if (normalized.contains('thứ 7')) return DateTime.saturday;
    if (normalized.contains('chủ nhật') || normalized.contains('cn')) {
      return DateTime.sunday;
    }
    return fallbackWeekday;
  }

  final parts = subject.startTime.split(':');
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
  final weekday = weekdayFromText(
    subject.dayOfWeek,
    DateTime.now().weekday,
  );

  try {
    await _systemAlarmChannel.invokeMethod<void>(
      'createAlarm',
      {
        'hour': hour,
        'minute': minute,
        'message': subject.name,
        'weekday': weekday,
      },
    );
  } on PlatformException {
    // Không làm gì thêm, nếu không mở được app Đồng hồ thì thôi.
  }
}


class SubjectSchedule {
  final String name;
  final String dayOfWeek;
  final String startTime;
  final String endTime;
  final String room;
  final String specificDate;

  const SubjectSchedule({
    required this.name,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.room,
    this.specificDate = '',
  });

  factory SubjectSchedule.fromJson(Map<String, dynamic> json) {
    return SubjectSchedule(
      name: json['name'] ?? '',
      dayOfWeek: json['day_of_week'] ?? '',
      startTime: json['start_time'] ?? '',
      endTime: json['end_time'] ?? '',
      room: json['room'] ?? '',
      specificDate: json['specific_date'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'day_of_week': dayOfWeek,
      'start_time': startTime,
      'end_time': endTime,
      'room': room,
      'specific_date': specificDate,
    };
  }
}


enum PersonaMode { serious, funny, angry }


enum AlarmRingtoneType { loud, normal, custom }


enum AppTheme { blue, dark }


class AlarmSettingsState extends ChangeNotifier {
  static const String _keyAlarmMode = 'alarm_mode_enabled';
  static const String _keyReminderMinutes = 'alarm_reminder_minutes';
  static const String _keyRingtoneType = 'alarm_ringtone_type';
  static const String _keyCustomSoundPath = 'alarm_custom_sound';

  bool _alarmModeEnabled = false;
  int _reminderMinutes = 15;
  AlarmRingtoneType _ringtoneType = AlarmRingtoneType.loud;
  String? _customSoundPath;

  bool get alarmModeEnabled => _alarmModeEnabled;
  int get reminderMinutes => _reminderMinutes;
  AlarmRingtoneType get ringtoneType => _ringtoneType;
  String? get customSoundPath => _customSoundPath;

  AlarmSettingsState() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _alarmModeEnabled = prefs.getBool(_keyAlarmMode) ?? false;
    _reminderMinutes = prefs.getInt(_keyReminderMinutes) ?? 15;
    final type = prefs.getString(_keyRingtoneType);
    if (type == 'normal') {
      _ringtoneType = AlarmRingtoneType.normal;
    } else if (type == 'custom') {
      _ringtoneType = AlarmRingtoneType.custom;
    } else {
      _ringtoneType = AlarmRingtoneType.loud;
    }
     _customSoundPath = prefs.getString(_keyCustomSoundPath);
    notifyListeners();
  }

  Future<void> setAlarmMode(bool value) async {
    _alarmModeEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAlarmMode, value);
  }

  Future<void> setReminderMinutes(int value) async {
    _reminderMinutes = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReminderMinutes, value);
  }

  Future<void> setRingtoneType(AlarmRingtoneType value) async {
    _ringtoneType = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyRingtoneType,
      value == AlarmRingtoneType.normal
          ? 'normal'
          : value == AlarmRingtoneType.custom
              ? 'custom'
              : 'loud',
    );
  }

  Future<void> setCustomSoundPath(String? path) async {
    _customSoundPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_keyCustomSoundPath);
    } else {
      await prefs.setString(_keyCustomSoundPath, path);
    }
  }
}


class ThemeState extends ChangeNotifier {
  static const String _key = 'app_theme';

  AppTheme _theme = AppTheme.blue;

  AppTheme get theme => _theme;

  bool get isDark => _theme == AppTheme.dark;

  ThemeState() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored == 'dark') {
      _theme = AppTheme.dark;
    } else {
      _theme = AppTheme.blue;
    }
    notifyListeners();
  }

  Future<void> setTheme(AppTheme value) async {
    _theme = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value == AppTheme.dark ? 'dark' : 'blue');
  }
}


class PersonaState extends ChangeNotifier {
  static const String _storageKey = 'persona_mode';

  PersonaMode? _persona;

  PersonaMode? get persona => _persona;

  PersonaState() {
    _loadFromStorage();
  }

  void setPersona(PersonaMode value) {
    _persona = value;
    notifyListeners();
    _saveToStorage();
    this._syncPersonaReminderWithSettings();
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored == null) return;
    switch (stored) {
      case 'funny':
        _persona = PersonaMode.funny;
        break;
      case 'angry':
        _persona = PersonaMode.angry;
        break;
      case 'serious':
      default:
        _persona = PersonaMode.serious;
        break;
    }
    notifyListeners();
  }

  Future<void> _saveToStorage() async {
    if (_persona == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, personaKey);
  }

  String get personaKey {
    switch (_persona) {
      case PersonaMode.funny:
        return 'funny';
      case PersonaMode.angry:
        return 'angry';
      case PersonaMode.serious:
      default:
        return 'serious';
    }
  }

  String get personaLabel {
    switch (_persona) {
      case PersonaMode.funny:
        return 'Hài hước';
      case PersonaMode.angry:
        return 'Giận dữ';
      case PersonaMode.serious:
      default:
        return 'Nghiêm túc';
    }
  }
}

const int _personaReminderBaseId = 4000;
const int _personaReminderMaxCount = 96;

Future<void> schedulePersonaReminders(int intervalMinutes) async {
  await cancelPersonaReminders();
  if (intervalMinutes <= 0) {
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final persona = prefs.getString('persona_mode') ?? 'serious';
  final user = FirebaseAuth.instance.currentUser;
  final displayName = (user?.displayName ?? '').trim();
  String callName;
  if (displayName.isEmpty) {
    callName = 'bạn';
  } else {
    final parts = displayName.split(' ');
    callName = parts.isNotEmpty ? parts.last : displayName;
  }
  final messages = _buildPersonaReminderMessages(
    persona: persona,
    callName: callName,
  );
  if (messages.isEmpty) {
    return;
  }
  final now = TimeService.now();
  final totalMinutes = 24 * 60;
  final count = totalMinutes ~/ intervalMinutes;
  for (int i = 0; i < count && i < _personaReminderMaxCount; i++) {
    final time =
        now.add(Duration(minutes: intervalMinutes * (i + 1)));
    final message = messages[i % messages.length];
    await AlarmService.scheduleReminder(
      id: _personaReminderBaseId + i,
      time: time,
      title: 'KaironAI',
      body: message,
    );
  }
}

Future<void> cancelPersonaReminders() async {
  for (int i = 0; i < _personaReminderMaxCount; i++) {
    await AlarmService.cancel(_personaReminderBaseId + i);
  }
}

List<String> _buildPersonaReminderMessages({
  required String persona,
  required String callName,
}) {
  switch (persona) {
    case 'funny':
      return [
        'Ê tính ra là bỏ tui hơi lâu rồi đó nha, tính làm "người lạ ơi" hay gì? Vào check thời gian biểu đi nè! 💀',
        'Cứu tui, cứu tui! Có đống lịch trình đang đợi mà chủ nhân đâu mất tiêu rồi? 😂',
        'Đừng để thời gian biểu trôi xa, vì Kairon vẫn luôn ở đây chờ $callName mà. Vào xem đi không cảm lạnh đó! 🤡☕',
      ];
    case 'angry':
      return [
        'Mày định để tao đợi đến bao giờ? Vào mà xem cái lịch trình của mày đi, đồ lười! 🙄',
        'Lại đi chơi rồi đúng không? Có cái app để nhắc học mà cũng không thèm ngó. Vào ngay! 💢',
        'Tao không có rảnh ngồi không đâu nhé. Vào check lịch nhanh không tao xóa hết bây giờ! 👊',
      ];
    default:
      return [
        'Thông báo: Đã đến lúc kiểm tra lại thời gian biểu của bạn để đảm bảo tiến độ. 📝',
        'KaironAI nhắc bạn: Việc duy trì kiểm tra thời gian biểu thường xuyên sẽ giúp bạn học tập và làm việc hiệu quả hơn. ✅',
        'Chào bạn, tôi đã sẵn sàng hỗ trợ bạn sắp xếp công việc tiếp theo. Mời bạn vào ứng dụng. 📝',
      ];
  }
}

extension on PersonaState {
  void _syncPersonaReminderWithSettings() {
    () async {
      final prefs = await SharedPreferences.getInstance();
      final minutes = prefs.getInt('ai_reminder_interval_minutes') ?? 0;
      if (minutes <= 0) {
        await cancelPersonaReminders();
      } else {
        await schedulePersonaReminders(minutes);
      }
    }();
  }
}


class ScheduleState extends ChangeNotifier {
  static const String _storageKeyPrefix = 'subjects_';
  static const String _pinnedKeyPrefix = 'pinned_subjects_';
  static const int _classReminderBaseId = 5000;
  static const int _classReminderMaxCount = 512;

  List<SubjectSchedule> _subjects = [];
  Set<String> _pinnedKeys = {};
  String _subjectsSignature = '';

  List<SubjectSchedule> get subjects => List.unmodifiable(_subjects);

  SubjectSchedule? get nextSubject => _findNextSubject(_subjects);

  ScheduleState() {
    _loadFromStorage();
  }

  String get _storageKey {
    final user = FirebaseAuth.instance.currentUser;
    final id = user?.uid ?? 'guest';
    return '$_storageKeyPrefix$id';
  }

  String get _pinnedKey {
    final user = FirebaseAuth.instance.currentUser;
    final id = user?.uid ?? 'guest';
    return '$_pinnedKeyPrefix$id';
  }

  String _subjectKey(SubjectSchedule subject) {
    return '${subject.name}|${subject.dayOfWeek}|${subject.startTime}';
  }

  String _buildSubjectsSignature(List<SubjectSchedule> subjects) {
    final list = subjects.map((e) => e.toJson()).toList();
    return jsonEncode(list);
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_storageKey);
    if (stored != null) {
      _subjects = stored
          .map(
            (e) => SubjectSchedule.fromJson(
              jsonDecode(e) as Map<String, dynamic>,
            ),
          )
          .toList();

      final now = TimeService.now();
      bool migrated = false;

      int weekdayFromText(String text, int fallbackWeekday) {
        final normalized = text.trim().toLowerCase();
        if (normalized.contains('thứ 2')) return DateTime.monday;
        if (normalized.contains('thứ 3')) return DateTime.tuesday;
        if (normalized.contains('thứ 4')) return DateTime.wednesday;
        if (normalized.contains('thứ 5')) return DateTime.thursday;
        if (normalized.contains('thứ 6')) return DateTime.friday;
        if (normalized.contains('thứ 7')) return DateTime.saturday;
        if (normalized.contains('chủ nhật') || normalized.contains('cn')) {
          return DateTime.sunday;
        }
        return fallbackWeekday;
      }

      _subjects = _subjects.map((subject) {
        if (subject.specificDate.isNotEmpty) {
          return subject;
        }

        final parts = subject.startTime.split(':');
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

        final weekday =
            weekdayFromText(subject.dayOfWeek, now.weekday);

        DateTime base = DateTime(
          now.year,
          now.month,
          now.day,
          hour,
          minute,
        );

        int diff = weekday - base.weekday;
        if (diff < 0 || (diff == 0 && base.isBefore(now))) {
          diff += 7;
        }
        final scheduled = base.add(Duration(days: diff));
        final specificDate =
            '${scheduled.year.toString().padLeft(4, '0')}-'
            '${scheduled.month.toString().padLeft(2, '0')}-'
            '${scheduled.day.toString().padLeft(2, '0')}';

        migrated = true;
        return SubjectSchedule(
          name: subject.name,
          dayOfWeek: subject.dayOfWeek,
          startTime: subject.startTime,
          endTime: subject.endTime,
          room: subject.room,
          specificDate: specificDate,
        );
      }).toList();

      if (migrated) {
        await _saveToStorage();
      }
    }
    final pinned = prefs.getStringList(_pinnedKey);
    if (pinned != null) {
      _pinnedKeys = pinned.toSet();
    }
    _subjectsSignature = _buildSubjectsSignature(_subjects);
    await _rescheduleClassReminders();
    notifyListeners();
  }

  Future<void> reloadForCurrentUser() async {
    await _loadFromStorage();
    await _loadFromFirestore();
  }

  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _subjects.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_storageKey, encoded);
    await prefs.setStringList(_pinnedKey, _pinnedKeys.toList());
  }

  Future<void> _loadFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('schedules')
        .get();
    final fetched = snapshot.docs
        .map(
          (doc) => SubjectSchedule.fromJson(
            doc.data(),
          ),
        )
        .toList();
    final previousSignature = _subjectsSignature;
    _subjects = fetched;
    final currentKeys = _subjects.map(_subjectKey).toSet();
    _pinnedKeys = _pinnedKeys.where(currentKeys.contains).toSet();
    _purgeExpired();
    final newSignature = _buildSubjectsSignature(_subjects);
    _subjectsSignature = newSignature;
    if (newSignature != previousSignature) {
      await _saveToStorage();
    }
    await _rescheduleClassReminders();
    notifyListeners();
  }

  DateTime _parseSubjectStart(SubjectSchedule subject, DateTime now) {
    if (subject.specificDate.isNotEmpty) {
      final parts = subject.startTime.split(':');
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

      final dateParts = subject.specificDate.split('-');
      if (dateParts.length == 3) {
        final year = int.tryParse(dateParts[0]) ?? now.year;
        final month = int.tryParse(dateParts[1]) ?? now.month;
        final day = int.tryParse(dateParts[2]) ?? now.day;
        return DateTime(year, month, day, hour, minute);
      }
    }

    int weekdayFromText(String text) {
      final normalized = text.trim().toLowerCase();
      if (normalized.contains('thứ 2')) return DateTime.monday;
      if (normalized.contains('thứ 3')) return DateTime.tuesday;
      if (normalized.contains('thứ 4')) return DateTime.wednesday;
      if (normalized.contains('thứ 5')) return DateTime.thursday;
      if (normalized.contains('thứ 6')) return DateTime.friday;
      if (normalized.contains('thứ 7')) return DateTime.saturday;
      if (normalized.contains('chủ nhật') || normalized.contains('cn')) {
        return DateTime.sunday;
      }
      return now.weekday;
    }

    final weekday = weekdayFromText(subject.dayOfWeek);
    final parts = subject.startTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    DateTime base = DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    int diff = weekday - now.weekday;
    if (diff < 0 || (diff == 0 && base.isBefore(now))) {
      diff += 7;
    }
    return base.add(Duration(days: diff));
  }

  void _purgeExpired() {
    if (_subjects.isEmpty) return;
    final now = TimeService.now();
    final List<SubjectSchedule> kept = [];
    for (final subject in _subjects) {
      final start = _parseSubjectStart(subject, now);
      final isPinnedSubject = _pinnedKeys.contains(_subjectKey(subject));
      if (isPinnedSubject || !start.isBefore(now)) {
        kept.add(subject);
      }
    }
    if (kept.length == _subjects.length) {
      return;
    }
    _subjects = kept;
  }

  void setSubjects(List<SubjectSchedule> subjects) {
    final previousSignature = _subjectsSignature;
    _subjects = List.from(subjects);
    final currentKeys = _subjects.map(_subjectKey).toSet();
    _pinnedKeys = _pinnedKeys.where(currentKeys.contains).toSet();
    _purgeExpired();
    final newSignature = _buildSubjectsSignature(_subjects);
    _subjectsSignature = newSignature;
    if (newSignature == previousSignature) {
      return;
    }
    _saveToStorage();
    _syncToFirestore();
    () async {
      await _rescheduleClassReminders();
    }();
    notifyListeners();
  }

  void mergeSubjects(List<SubjectSchedule> subjects) {
    if (subjects.isEmpty) return;
    final previousSignature = _subjectsSignature;
    _subjects = List.from(subjects);
    final currentKeys = _subjects.map(_subjectKey).toSet();
    _pinnedKeys = _pinnedKeys.where(currentKeys.contains).toSet();
    _purgeExpired();
    final newSignature = _buildSubjectsSignature(_subjects);
    _subjectsSignature = newSignature;
    if (newSignature == previousSignature) {
      return;
    }
    _saveToStorage();
    _syncToFirestore();
    () async {
      await _rescheduleClassReminders();
    }();
    notifyListeners();
  }

  Future<void> _syncToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final batch = FirebaseFirestore.instance.batch();
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('schedules');
    final existing = await col.get();
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }
    for (final subject in _subjects) {
      final ref = col.doc();
      batch.set(ref, subject.toJson());
    }
    await batch.commit();
  }

  bool isPinned(SubjectSchedule subject) {
    return _pinnedKeys.contains(_subjectKey(subject));
  }

  Future<void> togglePinned(SubjectSchedule subject) async {
    final key = _subjectKey(subject);
    if (_pinnedKeys.contains(key)) {
      _pinnedKeys.remove(key);
    } else {
      _pinnedKeys.add(key);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinnedKey, _pinnedKeys.toList());
    notifyListeners();
  }

  SubjectSchedule? _findNextSubject(List<SubjectSchedule> subjects) {
    if (subjects.isEmpty) return null;

    final now = TimeService.now();
    subjects.sort((a, b) {
      final at = _parseSubjectStart(a, now);
      final bt = _parseSubjectStart(b, now);
      return at.compareTo(bt);
    });

    for (final subject in subjects) {
      final start = _parseSubjectStart(subject, now);
      if (start.isAfter(now)) {
        return subject;
      }
    }

    return subjects.first;
  }

  Future<void> refreshClassReminders() async {
    await _rescheduleClassReminders();
  }

  Future<void> _rescheduleClassReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final alarmEnabled = prefs.getBool('alarm_mode_enabled') ?? false;
    final reminderMinutes = prefs.getInt('alarm_reminder_minutes') ?? 15;
    for (int i = 0; i < _classReminderMaxCount; i++) {
      await AlarmService.cancel(_classReminderBaseId + i);
    }
    if (!alarmEnabled || reminderMinutes <= 0) {
      return;
    }
    if (_subjects.isEmpty) {
      return;
    }
    final now = TimeService.now();
    final entries = _subjects
        .map(
          (subject) => MapEntry(
            subject,
            _parseSubjectStart(subject, now),
          ),
        )
        .where((entry) => entry.value.isAfter(now))
        .toList();
    if (entries.isEmpty) {
      return;
    }
    entries.sort((a, b) => a.value.compareTo(b.value));
    int idIndex = 0;
    for (final entry in entries) {
      if (idIndex >= _classReminderMaxCount) {
        break;
      }
      final subject = entry.key;
      final start = entry.value;
      final reminderTime = start.subtract(Duration(minutes: reminderMinutes));
      if (!reminderTime.isAfter(now)) {
        continue;
      }
      final id = _classReminderBaseId + idIndex;
      idIndex += 1;
      final roomText =
          subject.room.isNotEmpty ? ' tại ${subject.room}' : '';
      final title = 'Nhắc lịch học';
      final body =
          '${subject.name} lúc ${subject.startTime}$roomText';
      await AlarmService.scheduleReminder(
        id: id,
        time: reminderTime,
        title: title,
        body: body,
      );
    }
  }
}


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AlarmService.initialize();
  await TimeService.sync();
  Timer.periodic(const Duration(minutes: 1), (_) {
    TimeService.sync();
  });
  final user = FirebaseAuth.instance.currentUser;
  String initialRoute = '/login';
  if (user != null) {
    final prefs = await SharedPreferences.getInstance();
    final hasPersona = prefs.getString('persona_mode') != null;
    initialRoute = hasPersona ? '/home' : '/persona';
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PersonaState()),
        ChangeNotifierProvider(create: (_) => ScheduleState()),
        ChangeNotifierProvider(create: (_) => ThemeState()),
        ChangeNotifierProvider(create: (_) => AlarmSettingsState()),
        ChangeNotifierProvider(create: (_) => ChatState()),
      ],
      child: KaironApp(initialRoute: initialRoute),
    ),
  );
}


class KaironApp extends StatelessWidget {
  final String initialRoute;

  const KaironApp({super.key, this.initialRoute = '/login'});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final ColorScheme blueScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff4f46e5),
      brightness: Brightness.light,
    );
    final ColorScheme darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff0f172a),
      brightness: Brightness.dark,
    );

    final ThemeData blueTheme = ThemeData(
      colorScheme: blueScheme,
      useMaterial3: true,
    );

    final ThemeData darkTheme = ThemeData(
      colorScheme: darkScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xff020617),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Kairon',
      debugShowCheckedModeBanner: false,
      themeMode:
          themeState.theme == AppTheme.dark ? ThemeMode.dark : ThemeMode.light,
      theme: blueTheme,
      darkTheme: darkTheme,
      initialRoute: initialRoute,
      routes: {
        '/login': (_) => const LoginPage(),
        '/persona': (_) => const PersonaSelectionPage(),
        '/home': (_) => const KaironHomePage(),
        '/chat': (_) => const KaironChatPage(),
      },
    );
  }
}

Future<void> logoutAndReset(BuildContext context) async {
  await FirebaseAuth.instance.signOut();
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('persona_mode');
  if (!context.mounted) return;
  Navigator.of(context)
      .pushNamedAndRemoveUntil('/login', (route) => false);
}


class KaironHomePage extends StatefulWidget {
  const KaironHomePage({super.key});

  @override
  State<KaironHomePage> createState() => _KaironHomePageState();
}


class _KaironHomePageState extends State<KaironHomePage> {
  final bool _loading = false;
  String? _error;
  int _selectedWeekday = DateTime.monday;
  late final PageController _dayPageController;
  Timer? _cleanupTimer;
  DateTime _calendarFocusedDay = TimeService.now();
  DateTime? _calendarSelectedDay;
  Set<DateTime> _localEventDates = {};
  Set<DateTime> _remoteEventDates = {};
  void _showAccountSheet() {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Đã đăng nhập';
    final displayName = (user?.displayName ?? '').trim();
    final accountName = displayName.isNotEmpty
        ? displayName
        : (email.isNotEmpty ? email.split('@').first : 'Bạn');

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      child: Text(
                        accountName.isNotEmpty
                            ? accountName[0].toUpperCase()
                            : 'K',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tài khoản của bạn',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            accountName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Cài đặt'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AccountSettingsPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Hướng dẫn sử dụng'),
                  onTap: () {
                    Navigator.of(context).pop();
                    showModalBottomSheet<void>(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (context) {
                        return const SafeArea(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hướng dẫn sử dụng Kairon',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  '1. Thêm thời gian biểu ở trang chủ hoặc nhờ KaironAI tạo giúp.\n'
                                  '2. Nhấn vào biểu tượng đồng hồ để đặt báo thức trong ứng dụng Đồng hồ.\n'
                                  '3. Ghim các lịch quan trọng để không bị xóa khi đã qua giờ.\n'
                                  '4. Vào mục Cài đặt để đổi cá tính KaironAI, bật giao diện tối hoặc đăng xuất.\n'
                                  '5. Khung giờ 7h sáng đến 23h đêm: bạn chat thoải mái, nút Gửi sẽ chuyển thành nút Dừng để ngắt trả lời khi cần.\n'
                                  '6. Khung giờ sau 23h đến trước 7h sáng: mỗi tài khoản chỉ gửi được 1 tin nhắn mỗi phút và KaironAI sẽ trả lời ngắn gọn để tiết kiệm tài nguyên.',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addScheduleManually() async {
    final scheduleState = context.read<ScheduleState>();

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AddSchedulePage(),
      ),
    );

    if (result is! SubjectSchedule) return;

    final updated = List<SubjectSchedule>.from(scheduleState.subjects)
      ..add(result);
    scheduleState.setSubjects(updated);
    _rebuildLocalEventDates();

    final nextSubject = scheduleState.nextSubject;

    if (nextSubject != null) {
      final timeRange = nextSubject.endTime.isNotEmpty
          ? '${nextSubject.startTime} - ${nextSubject.endTime}'
          : nextSubject.startTime;
      await HomeWidgetService.updateNextSubject(
        name: nextSubject.name,
        timeRange: timeRange,
        room: nextSubject.room,
      );
    }
  }

  Future<void> _editSchedule(SubjectSchedule subject) async {
    final scheduleState = context.read<ScheduleState>();
    final index = scheduleState.subjects.indexOf(subject);
    if (index < 0) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddSchedulePage(initial: subject),
      ),
    );

    if (result is Map && result['delete'] == true) {
      await _deleteSchedule(subject);
    } else if (result is SubjectSchedule) {
      final updated = List<SubjectSchedule>.from(scheduleState.subjects)
        ..[index] = result;
      scheduleState.setSubjects(updated);
      _rebuildLocalEventDates();
    } else {
      return;
    }

    final nextSubject = scheduleState.nextSubject;
    if (nextSubject != null) {
      final timeRange = nextSubject.endTime.isNotEmpty
          ? '${nextSubject.startTime} - ${nextSubject.endTime}'
          : nextSubject.startTime;
      await HomeWidgetService.updateNextSubject(
        name: nextSubject.name,
        timeRange: timeRange,
        room: nextSubject.room,
      );
    }
  }

  Future<void> _deleteSchedule(SubjectSchedule subject) async {
    final scheduleState = context.read<ScheduleState>();
    final updated = List<SubjectSchedule>.from(scheduleState.subjects)
      ..remove(subject);
    scheduleState.setSubjects(updated);
    _rebuildLocalEventDates();

    final nextSubject = scheduleState.nextSubject;
    if (nextSubject != null) {
      final timeRange = nextSubject.endTime.isNotEmpty
          ? '${nextSubject.startTime} - ${nextSubject.endTime}'
          : nextSubject.startTime;
      await HomeWidgetService.updateNextSubject(
        name: nextSubject.name,
        timeRange: timeRange,
        room: nextSubject.room,
      );
    }
  }

  Future<void> _pinSchedule(SubjectSchedule subject) async {
    final scheduleState = context.read<ScheduleState>();
    await scheduleState.togglePinned(subject);
  }

  int _weekdayFromText(String text, int fallbackWeekday) {
    final normalized = text.trim().toLowerCase();
    if (normalized.contains('thứ 2')) return DateTime.monday;
    if (normalized.contains('thứ 3')) return DateTime.tuesday;
    if (normalized.contains('thứ 4')) return DateTime.wednesday;
    if (normalized.contains('thứ 5')) return DateTime.thursday;
    if (normalized.contains('thứ 6')) return DateTime.friday;
    if (normalized.contains('thứ 7')) return DateTime.saturday;
    if (normalized.contains('chủ nhật') || normalized.contains('cn')) {
      return DateTime.sunday;
    }
    return fallbackWeekday;
  }

  String _subjectSubtitle(SubjectSchedule subject) {
    String dayText = subject.dayOfWeek.trim();
    DateTime? date;
    if (subject.specificDate.isNotEmpty) {
      date = DateTime.tryParse(subject.specificDate);
    }

    if (dayText.isEmpty && date != null) {
      switch (date.weekday) {
        case DateTime.monday:
          dayText = 'Thứ 2';
          break;
        case DateTime.tuesday:
          dayText = 'Thứ 3';
          break;
        case DateTime.wednesday:
          dayText = 'Thứ 4';
          break;
        case DateTime.thursday:
          dayText = 'Thứ 5';
          break;
        case DateTime.friday:
          dayText = 'Thứ 6';
          break;
        case DateTime.saturday:
          dayText = 'Thứ 7';
          break;
        case DateTime.sunday:
        default:
          dayText = 'Chủ nhật';
          break;
      }
    }

    if (date != null) {
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      if (dayText.isNotEmpty) {
        dayText = '$dayText, $day/$month';
      } else {
        dayText = '$day/$month';
      }
    }

    final time = subject.startTime.trim();
    if (dayText.isEmpty) {
      return time;
    }
    if (time.isEmpty) {
      return dayText;
    }
    return '$dayText • $time';
  }

  @override
  void initState() {
    super.initState();
    final scheduleState = context.read<ScheduleState>();
    scheduleState.addListener(_rebuildLocalEventDates);
    final next = scheduleState.nextSubject;
    if (next != null) {
      _selectedWeekday =
          _weekdayFromText(next.dayOfWeek, DateTime.now().weekday);
    } else {
      _selectedWeekday = DateTime.now().weekday;
    }
    final initialIndex = _weekdayToIndex(_selectedWeekday);
    _dayPageController = PageController(initialPage: initialIndex);

    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final state = context.read<ScheduleState>();
      state.setSubjects(state.subjects);
    });
    _calendarFocusedDay = _normalizeDay(TimeService.now());
    _calendarSelectedDay = _calendarFocusedDay;
    _rebuildLocalEventDates();
    _loadRemoteEventDates();
  }

  int _weekdayToIndex(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 0;
      case DateTime.tuesday:
        return 1;
      case DateTime.wednesday:
        return 2;
      case DateTime.thursday:
        return 3;
      case DateTime.friday:
        return 4;
      case DateTime.saturday:
        return 5;
      case DateTime.sunday:
      default:
        return 6;
    }
  }

  int _indexToWeekday(int index) {
    switch (index) {
      case 0:
        return DateTime.monday;
      case 1:
        return DateTime.tuesday;
      case 2:
        return DateTime.wednesday;
      case 3:
        return DateTime.thursday;
      case 4:
        return DateTime.friday;
      case 5:
        return DateTime.saturday;
      case 6:
      default:
        return DateTime.sunday;
    }
  }

  @override
  void dispose() {
    final scheduleState = context.read<ScheduleState>();
    scheduleState.removeListener(_rebuildLocalEventDates);
    _dayPageController.dispose();
    _cleanupTimer?.cancel();
    super.dispose();
  }

  void _openSelectedDayDetail() {
    final scheduleState = context.read<ScheduleState>();
    final subjects = scheduleState.subjects;
    final weekday = _selectedWeekday;
    final daySubjects = subjects.where((subject) {
      final subjectWeekday = _weekdayFromText(
        subject.dayOfWeek,
        weekday,
      );
      return subjectWeekday == weekday;
    }).toList()
      ..sort((a, b) {
        int parseMinutes(String time) {
          final parts = time.split(':');
          final hour = int.tryParse(parts[0]) ?? 0;
          final minute =
              int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
          return hour * 60 + minute;
        }

        final am = parseMinutes(a.startTime);
        final bm = parseMinutes(b.startTime);
        return am.compareTo(bm);
      });

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        Icons.event_note,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Lịch trình trong ngày',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (daySubjects.isEmpty)
                  const Text(
                    'Không có lịch cho ngày này.',
                    style: TextStyle(fontSize: 14),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: daySubjects.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final subject = daySubjects[index];
                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.12),
                              child: Text(
                                subject.name.isNotEmpty
                                    ? subject.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                ),
                              ),
                            ),
                            title: Text(
                              subject.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              _subjectSubtitle(subject),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                  ),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _editSchedule(subject);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                  ),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _deleteSchedule(subject);
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  DateTime _normalizeDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  List<dynamic> _calendarEventLoader(DateTime day) {
    final normalized = _normalizeDay(day);
    if (_localEventDates.contains(normalized) ||
        _remoteEventDates.contains(normalized)) {
      return const ['event'];
    }
    return const [];
  }

  void _rebuildLocalEventDates() {
    final scheduleState = context.read<ScheduleState>();
    final Set<DateTime> dates = {};
    for (final subject in scheduleState.subjects) {
      if (subject.specificDate.isEmpty) {
        continue;
      }
      final parts = subject.specificDate.split('-');
      if (parts.length != 3) {
        continue;
      }
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);
      if (year == null || month == null || day == null) {
        continue;
      }
      dates.add(DateTime(year, month, day));
    }
    setState(() {
      _localEventDates = dates;
    });
  }

  Future<void> _loadRemoteEventDates() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('schedules')
          .get();
      final Set<DateTime> dates = {};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final specificDate = data['specific_date'] as String?;
        if (specificDate == null || specificDate.isEmpty) {
          continue;
        }
        final parts = specificDate.split('-');
        if (parts.length != 3) {
          continue;
        }
        final year = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final day = int.tryParse(parts[2]);
        if (year == null || month == null || day == null) {
          continue;
        }
        dates.add(DateTime(year, month, day));
      }
      if (!mounted) return;
      setState(() {
        _remoteEventDates = dates;
      });
    } catch (_) {}
  }

  Widget _buildMonthlyCalendar(BuildContext context) {
    final theme = Theme.of(context);
    final now = TimeService.now();
    final firstDay = DateTime(now.year - 1, 1, 1);
    final lastDay = DateTime(now.year + 1, 12, 31);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TableCalendar(
        firstDay: firstDay,
        lastDay: lastDay,
        focusedDay: _calendarFocusedDay,
        calendarFormat: CalendarFormat.month,
        startingDayOfWeek: StartingDayOfWeek.monday,
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
        ),
        availableGestures: AvailableGestures.horizontalSwipe,
        selectedDayPredicate: (day) => isSameDay(_calendarSelectedDay, day),
        eventLoader: _calendarEventLoader,
        calendarStyle: CalendarStyle(
          markerDecoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
          markersMaxCount: 3,
        ),
        calendarBuilders: CalendarBuilders(
          defaultBuilder: (context, day, focusedDay) {
            final normalized = _normalizeDay(day);
            final hasEvent = _localEventDates.contains(normalized) ||
                _remoteEventDates.contains(normalized);
            final today = _normalizeDay(TimeService.now());
            final isTodayDay = normalized == today;
            final style = TextStyle(
              fontWeight: hasEvent ? FontWeight.w700 : FontWeight.w400,
              color: isTodayDay
                  ? theme.colorScheme.primary
                  : theme.textTheme.bodyMedium?.color,
            );
            return Center(
              child: Text(
                '${day.day}',
                style: style,
              ),
            );
          },
          outsideBuilder: (context, day, focusedDay) {
            final normalized = _normalizeDay(day);
            final hasEvent = _localEventDates.contains(normalized) ||
                _remoteEventDates.contains(normalized);
            final style = TextStyle(
              fontWeight: hasEvent ? FontWeight.w700 : FontWeight.w400,
              color: Colors.grey.shade400,
            );
            return Center(
              child: Text(
                '${day.day}',
                style: style,
              ),
            );
          },
        ),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            final normalized = _normalizeDay(selectedDay);
            _calendarSelectedDay = normalized;
            _calendarFocusedDay = _normalizeDay(focusedDay);
            _selectedWeekday = selectedDay.weekday;
          });
          final normalized = _normalizeDay(selectedDay);
          final hasEvent = _localEventDates.contains(normalized) ||
              _remoteEventDates.contains(normalized);
          if (hasEvent) {
            _openSelectedDayDetail();
          }
        },
        onPageChanged: (focusedDay) {
          _calendarFocusedDay = _normalizeDay(focusedDay);
        },
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.camera_alt_outlined, size: 18),
          label: const Text('Quét ảnh TKB'),
          onPressed: () async {
            final result = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CameraPage(),
              ),
            );
            if (result is! XFile) {
              return;
            }
            final file = File(result.path);
            if (!mounted) return;
            if (!context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => KaironChatPage(
                  initialPrompt:
                      'Giúp mình đọc lịch/thời khóa biểu trong ảnh này và xếp thời gian biểu chi tiết.',
                  initialImages: [file],
                ),
              ),
            );
          },
        ),
        ActionChip(
          avatar: const Icon(Icons.calendar_view_week_outlined, size: 18),
          label: const Text('Xem lịch tuần này'),
          onPressed: () {
            final now = TimeService.now();
            final weekday = now.weekday;
            setState(() {
              _selectedWeekday = weekday;
              final index = _weekdayToIndex(weekday);
              _dayPageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            });
          },
        ),
        ActionChip(
          avatar: const Icon(Icons.add_circle_outline, size: 18),
          label: const Text('Thêm lịch mới'),
          onPressed: _addScheduleManually,
        ),
      ],
    );
  }

  Widget _buildSelectedDayCalendar(BuildContext context) {
    final now = TimeService.now();
    final weekdayNow = now.weekday;
    final monday =
        now.subtract(Duration(days: weekdayNow - DateTime.monday));
    final index = _weekdayToIndex(_selectedWeekday);
    final selectedDate = monday.add(Duration(days: index));

    String weekdayLabel;
    switch (_selectedWeekday) {
      case DateTime.monday:
        weekdayLabel = 'Thứ 2';
        break;
      case DateTime.tuesday:
        weekdayLabel = 'Thứ 3';
        break;
      case DateTime.wednesday:
        weekdayLabel = 'Thứ 4';
        break;
      case DateTime.thursday:
        weekdayLabel = 'Thứ 5';
        break;
      case DateTime.friday:
        weekdayLabel = 'Thứ 6';
        break;
      case DateTime.saturday:
        weekdayLabel = 'Thứ 7';
        break;
      case DateTime.sunday:
      default:
        weekdayLabel = 'Chủ nhật';
        break;
    }

    final dayText = selectedDate.day.toString().padLeft(2, '0');

    return InkWell(
      onTap: _openSelectedDayDetail,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context)
              .colorScheme
              .primary
              .withValues(alpha: 0.12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_note,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ngày $dayText',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  weekdayLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduleState = context.watch<ScheduleState>();
    final subjects = scheduleState.subjects;
    final nextSubject = scheduleState.nextSubject;
    final theme = Theme.of(context);
    final bool isDarkTheme = theme.brightness == Brightness.dark;

    Widget content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: nextSubject != null
                  ? _NextClassCard(
                      key: ValueKey(
                        '${nextSubject.name}|${nextSubject.dayOfWeek}|${nextSubject.startTime}',
                      ),
                      subject: nextSubject,
                    )
                  : const Padding(
                      key: ValueKey('no-next-subject'),
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Chưa có lịch sắp tới.\nHãy thêm thời gian biểu hoặc nhờ KaironAI tạo giúp.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            _buildMonthlyCalendar(context),
            const SizedBox(height: 8),
            const _KaironThinkingPrompts(),
            const SizedBox(height: 8),
            _buildQuickActions(context),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Thời gian biểu tuần',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton.icon(
                  onPressed: _loading ? null : _addScheduleManually,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Thêm thời gian biểu'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  {
                    'label': 'T2',
                    'weekday': DateTime.monday,
                  },
                  {
                    'label': 'T3',
                    'weekday': DateTime.tuesday,
                  },
                  {
                    'label': 'T4',
                    'weekday': DateTime.wednesday,
                  },
                  {
                    'label': 'T5',
                    'weekday': DateTime.thursday,
                  },
                  {
                    'label': 'T6',
                    'weekday': DateTime.friday,
                  },
                  {
                    'label': 'T7',
                    'weekday': DateTime.saturday,
                  },
                  {
                    'label': 'CN',
                    'weekday': DateTime.sunday,
                  },
                ].map((day) {
                  final weekday = day['weekday'] as int;
                  final label = day['label'] as String;
                  final selected = weekday == _selectedWeekday;
                  final hasSubjects = subjects.any((subject) {
                    final subjectWeekday = _weekdayFromText(
                      subject.dayOfWeek,
                      weekday,
                    );
                    return subjectWeekday == weekday;
                  });
                  final textStyle = TextStyle(
                    fontWeight: selected || hasSubjects
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: hasSubjects
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        label,
                        style: textStyle,
                      ),
                      selected: selected,
                      showCheckmark: false,
                      backgroundColor: hasSubjects
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: selected ? 0.24 : 0.12)
                          : null,
                      onSelected: (_) {
                        setState(() {
                          _selectedWeekday = weekday;
                          final index = _weekdayToIndex(weekday);
                          _dayPageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : subjects.isEmpty
                      ? const Center(
                          child: Text(
                            'Chưa có dữ liệu.\nNhờ KaironAI tạo lịch hoặc thêm tay.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : PageView.builder(
                          controller: _dayPageController,
                          itemCount: 7,
                          onPageChanged: (page) {
                            final weekday = _indexToWeekday(page);
                            if (weekday != _selectedWeekday) {
                              setState(() {
                                _selectedWeekday = weekday;
                              });
                            }
                          },
                          itemBuilder: (context, pageIndex) {
                            final weekday = _indexToWeekday(pageIndex);
                            final daySubjects = subjects.where((subject) {
                              final subjectWeekday = _weekdayFromText(
                                subject.dayOfWeek,
                                weekday,
                              );
                              return subjectWeekday == weekday;
                            }).toList()
                              ..sort((a, b) {
                                int parseMinutes(String time) {
                                  final parts = time.split(':');
                                  final hour = int.tryParse(parts[0]) ?? 0;
                                  final minute =
                                      int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
                                  return hour * 60 + minute;
                                }

                                final am = parseMinutes(a.startTime);
                                final bm = parseMinutes(b.startTime);
                                return am.compareTo(bm);
                              });
                            if (daySubjects.isEmpty) {
                              return _EmptyDayClock(
                                onTapAdd: _addScheduleManually,
                              );
                            }
                            return ListView.separated(
                              key: const ValueKey('subjects-list'),
                              itemCount: daySubjects.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final subject = daySubjects[index];
                                return TweenAnimationBuilder<double>(
                                  duration:
                                      const Duration(milliseconds: 250),
                                  tween: Tween<double>(begin: 0.9, end: 1.0),
                                  builder: (context, value, child) {
                                    return Transform.scale(
                                      scale: value,
                                      child: child,
                                    );
                                  },
                                  child: Card(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: Theme.of(context)
                                                .brightness ==
                                            Brightness.dark
                                        ? 4
                                        : 1,
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      leading: CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.12),
                                        child: Text(
                                          subject.name.isNotEmpty
                                              ? subject.name[0].toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        subject.name,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        _subjectSubtitle(subject),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                            onPressed: () =>
                                                _editSchedule(subject),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.alarm_on_outlined,
                                            ),
                                            onPressed: () =>
                                                openSystemAlarmForSchedule(
                                              subject,
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              scheduleState.isPinned(subject)
                                                  ? Icons.push_pin
                                                  : Icons.push_pin_outlined,
                                            ),
                                            onPressed: () =>
                                                _pinSchedule(subject),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kairon',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
            Text(
              'KaironAI • người trợ lý trung thành của bạn',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: _showAccountSheet,
              borderRadius: BorderRadius.circular(20),
              child: CircleAvatar(
                radius: 16,
                backgroundColor:
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                child: Icon(
                  Icons.person_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: isDarkTheme
          ? Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xff020617),
                    Color(0xff020617),
                    Color(0xff0b1120),
                    Color(0xff1d4ed8),
                    Color(0xff7c3aed),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: [
                    0.0,
                    0.2,
                    0.45,
                    0.75,
                    1.0,
                  ],
                ),
              ),
              child: content,
            )
          : content,
    );
  }
}


class _KaironMascotTeaser extends StatelessWidget {
  const _KaironMascotTeaser();

  @override
  Widget build(BuildContext context) {
    final personaState = context.watch<PersonaState>();
    final theme = Theme.of(context);

    String thoughtText;
    switch (personaState.persona) {
      case PersonaMode.funny:
        thoughtText =
            'Không biết hôm nay bạn đã có lịch gì chưa, để mình nghĩ cách sắp cho vui hơn.';
        break;
      case PersonaMode.angry:
        thoughtText =
            'Không lẽ hôm nay vẫn chưa có lịch? Mình đang nghĩ xem phải sắp cho bạn đỡ lười đây.';
        break;
      case PersonaMode.serious:
      default:
        thoughtText =
            'Mình đang suy nghĩ xem nên sắp lịch thế nào cho hợp lý nhất cho bạn.';
        break;
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).pushNamed('/chat');
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.16),
              ),
              child: Icon(
                Icons.smart_toy_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                thoughtText,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _KaironThinkingPrompts extends StatelessWidget {
  const _KaironThinkingPrompts();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheduleState = context.watch<ScheduleState>();
    final user = FirebaseAuth.instance.currentUser;
    final displayName = (user?.displayName ?? '').trim();
    String callName;
    if (displayName.isNotEmpty) {
      final parts = displayName.split(' ');
      callName = parts.isNotEmpty ? parts.last : displayName;
    } else {
      callName = 'bạn';
    }

    final now = TimeService.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final tomorrowKey =
        '${tomorrow.year.toString().padLeft(4, '0')}-'
        '${tomorrow.month.toString().padLeft(2, '0')}-'
        '${tomorrow.day.toString().padLeft(2, '0')}';

    SubjectSchedule? tomorrowSubject;
    for (final subject in scheduleState.subjects) {
      if (subject.specificDate == tomorrowKey) {
        if (tomorrowSubject == null) {
          tomorrowSubject = subject;
        } else {
          final partsA = tomorrowSubject.startTime.split(':');
          final partsB = subject.startTime.split(':');
          final hourA = int.tryParse(partsA[0]) ?? 0;
          final minuteA =
              int.tryParse(partsA.length > 1 ? partsA[1] : '0') ?? 0;
          final hourB = int.tryParse(partsB[0]) ?? 0;
          final minuteB =
              int.tryParse(partsB.length > 1 ? partsB[1] : '0') ?? 0;
          final totalA = hourA * 60 + minuteA;
          final totalB = hourB * 60 + minuteB;
          if (totalB < totalA) {
            tomorrowSubject = subject;
          }
        }
      }
    }

    final prompts = <String>[
      'Mình có thể giúp $callName xếp thời gian biểu tuần tới từ ảnh (lịch học, lịch làm việc, lịch cá nhân...).',
      if (tomorrowSubject != null)
        '$callName ơi, ngày mai bạn có lịch ${tomorrowSubject.name} lúc ${tomorrowSubject.startTime} đó.',
      'Hãy gửi ảnh lịch hoặc thời khóa biểu mới nhất để mình cập nhật nhé.',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withValues(alpha: 0.16),
            ),
            child: Icon(
              Icons.smart_toy_outlined,
              color: theme.colorScheme.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedTextKit(
              repeatForever: true,
              pause: const Duration(milliseconds: 1200),
              animatedTexts: prompts
                  .map(
                    (text) => TypewriterAnimatedText(
                      text,
                      textStyle: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface,
                      ),
                      speed: const Duration(milliseconds: 40),
                    ),
                  )
                  .toList(),
              onTap: () {
                Navigator.of(context).pushNamed('/chat');
              },
            ),
          ),
        ],
      ),
    );
  }
}


class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _widgetEnabled = false;
  int _reminderIntervalMinutes = 0;
  bool _classReminderEnabled = false;
  int _classReminderMinutes = 15;

  @override
  void initState() {
    super.initState();
    _loadWidgetSetting();
    _loadReminderSetting();
    _loadAlarmSettings();
  }

  Future<void> _loadWidgetSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('home_widget_enabled') ?? false;
    if (!mounted) return;
    setState(() {
      _widgetEnabled = enabled;
    });
  }

  Future<void> _loadReminderSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final minutes = prefs.getInt('ai_reminder_interval_minutes') ?? 0;
    if (!mounted) return;
    setState(() {
      _reminderIntervalMinutes = minutes;
    });
  }

  Future<void> _loadAlarmSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('alarm_mode_enabled') ?? false;
    final minutes = prefs.getInt('alarm_reminder_minutes') ?? 15;
    if (!mounted) return;
    setState(() {
      _classReminderEnabled = enabled;
      _classReminderMinutes = minutes <= 0 ? 15 : minutes;
    });
  }

  Future<void> _updateWidgetSetting(
    bool enabled,
    SubjectSchedule? nextSubject,
  ) async {
    await HomeWidgetService.setWidgetEnabled(enabled);
    if (!enabled) {
      return;
    }
    if (nextSubject == null) {
      return;
    }
    final timeRange = nextSubject.endTime.isNotEmpty
        ? '${nextSubject.startTime} - ${nextSubject.endTime}'
        : nextSubject.startTime;
    await HomeWidgetService.updateNextSubject(
      name: nextSubject.name,
      timeRange: timeRange,
      room: nextSubject.room,
    );
  }

  Future<void> _updateReminderSetting(int minutes) async {
    setState(() {
      _reminderIntervalMinutes = minutes;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ai_reminder_interval_minutes', minutes);
    if (minutes <= 0) {
      await cancelPersonaReminders();
    } else {
      await schedulePersonaReminders(minutes);
    }
  }

  Future<void> _updateClassReminderSettings({
    bool? enabled,
    int? minutes,
  }) async {
    final newEnabled = enabled ?? _classReminderEnabled;
    final newMinutes = minutes ?? _classReminderMinutes;
    setState(() {
      _classReminderEnabled = newEnabled;
      _classReminderMinutes = newMinutes;
    });
    final alarmSettings = context.read<AlarmSettingsState>();
    await alarmSettings.setAlarmMode(newEnabled);
    await alarmSettings.setReminderMinutes(newMinutes);
    final scheduleState = context.read<ScheduleState>();
    await scheduleState.refreshClassReminders();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final personaState = context.watch<PersonaState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.theater_comedy_outlined),
              title: const Text('Cá tính KaironAI'),
              subtitle: Text(personaState.personaLabel),
              onTap: () {
                Navigator.of(context).pushNamed('/persona');
              },
            ),
            SwitchListTile(
              value: themeState.theme == AppTheme.dark,
              title: const Text('Giao diện tối'),
              subtitle:
                  const Text('Tắt để dùng giao diện sáng mặc định'),
              onChanged: (value) {
                themeState.setTheme(
                  value ? AppTheme.dark : AppTheme.blue,
                );
              },
            ),
            SwitchListTile(
              value: _widgetEnabled,
              title: const Text('Widget lịch sắp tới'),
              subtitle: const Text(
                'Hiện môn tiếp theo trên màn hình chính (Android)',
              ),
              onChanged: (value) {
                setState(() {
                  _widgetEnabled = value;
                });
                final scheduleState = context.read<ScheduleState>();
                final nextSubject = scheduleState.nextSubject;
                _updateWidgetSetting(value, nextSubject);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Nhắc kiểm tra thời gian biểu'),
              subtitle: const Text(
                'Gửi thông báo theo cá tính KaironAI sau một khoảng thời gian',
              ),
            ),
            RadioListTile<int>(
              value: 0,
              groupValue: _reminderIntervalMinutes,
              title: const Text('Không'),
              onChanged: (value) {
                if (value == null) return;
                _updateReminderSetting(0);
              },
            ),
            RadioListTile<int>(
              value: 15,
              groupValue: _reminderIntervalMinutes,
              title: const Text('Sau mỗi 15 phút'),
              onChanged: (value) {
                if (value == null) return;
                _updateReminderSetting(15);
              },
            ),
            RadioListTile<int>(
              value: 30,
              groupValue: _reminderIntervalMinutes,
              title: const Text('Sau mỗi 30 phút'),
              onChanged: (value) {
                if (value == null) return;
                _updateReminderSetting(30);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.alarm_on_outlined),
              title: const Text('Nhắc trước giờ học'),
              subtitle: const Text(
                'Gửi thông báo trước khi đến giờ trong thời gian biểu',
              ),
            ),
            SwitchListTile(
              value: _classReminderEnabled,
              title: const Text('Bật nhắc trước giờ học'),
              subtitle: const Text('Tự động nhắc trước giờ bắt đầu mỗi lịch'),
              onChanged: (value) {
                _updateClassReminderSettings(enabled: value);
              },
            ),
            RadioListTile<int>(
              value: 15,
              groupValue: _classReminderMinutes,
              title: const Text('Nhắc trước 15 phút'),
              enabled: _classReminderEnabled,
              onChanged: _classReminderEnabled
                  ? (value) {
                      if (value == null) return;
                      _updateClassReminderSettings(minutes: 15);
                    }
                  : null,
            ),
            RadioListTile<int>(
              value: 30,
              groupValue: _classReminderMinutes,
              title: const Text('Nhắc trước 30 phút'),
              enabled: _classReminderEnabled,
              onChanged: _classReminderEnabled
                  ? (value) {
                      if (value == null) return;
                      _updateClassReminderSettings(minutes: 30);
                    }
                  : null,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.logout,
                color: Colors.redAccent,
              ),
              title: const Text(
                'Đăng xuất',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                await logoutAndReset(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}


class _NextClassCard extends StatefulWidget {
  final SubjectSchedule subject;

  const _NextClassCard({
    super.key,
    required this.subject,
  });

  @override
  State<_NextClassCard> createState() => _NextClassCardState();
}

class _NextClassCardState extends State<_NextClassCard> {
  Duration? _remaining;
  Timer? _timer;
  DateTime? _targetStart;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateRemaining() {
    final now = TimeService.now();
    final start = _buildStartTime(now);
    final diff = start.difference(now);
    setState(() {
      _remaining = diff;
      _targetStart = start;
    });
  }

  DateTime _buildStartTime(DateTime now) {
    int weekdayFromText(String text) {
      final normalized = text.trim().toLowerCase();
      if (normalized.contains('thứ 2')) return DateTime.monday;
      if (normalized.contains('thứ 3')) return DateTime.tuesday;
      if (normalized.contains('thứ 4')) return DateTime.wednesday;
      if (normalized.contains('thứ 5')) return DateTime.thursday;
      if (normalized.contains('thứ 6')) return DateTime.friday;
      if (normalized.contains('thứ 7')) return DateTime.saturday;
      if (normalized.contains('chủ nhật') || normalized.contains('cn')) {
        return DateTime.sunday;
      }
      return now.weekday;
    }

    final weekday = weekdayFromText(widget.subject.dayOfWeek);
    final parts = widget.subject.startTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    DateTime base = DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    int diff = weekday - now.weekday;
    if (diff < 0 || (diff == 0 && base.isBefore(now))) {
      diff += 7;
    }
    return base.add(Duration(days: diff));
  }

  String _formatRemaining() {
    final diff = _remaining;
    if (diff == null) {
      return '';
    }
    var totalSeconds = diff.inSeconds;
    if (totalSeconds <= 0) {
      return 'Đã đến giờ nhắc này.';
    }
    if (_targetStart != null) {
      final now = TimeService.now();
      final startDate = DateTime(
        _targetStart!.year,
        _targetStart!.month,
        _targetStart!.day,
      );
      final nowDate = DateTime(now.year, now.month, now.day);
      final dayDiff = startDate.difference(nowDate).inDays;
      if (dayDiff >= 1) {
        if (dayDiff == 1) {
          return 'Còn 1 ngày nữa đến giờ này.';
        }
        return 'Còn $dayDiff ngày nữa đến giờ này.';
      }
    }

    final totalMinutes = (totalSeconds / 60).ceil();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0 && minutes <= 0) {
      return 'Chỉ còn vài giây nữa đến giờ này.';
    }
    if (hours <= 0) {
      return 'Còn $minutes phút nữa đến giờ này.';
    }
    if (minutes <= 0) {
      return 'Còn $hours giờ nữa đến giờ này.';
    }
    return 'Còn $hours giờ $minutes phút nữa đến giờ này.';
  }

  @override
  Widget build(BuildContext context) {
    final remainingText = _formatRemaining();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xff4f46e5), Color(0xff22c55e)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lịch sắp tới',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.subject.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.subject.dayOfWeek} • ${widget.subject.startTime}',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                      ),
                      if (remainingText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          remainingText,
                          style: TextStyle(
                            color: colorScheme.secondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDayClock extends StatefulWidget {
  final VoidCallback onTapAdd;

  const _EmptyDayClock({
    required this.onTapAdd,
  });

  @override
  State<_EmptyDayClock> createState() => _EmptyDayClockState();
}

class _EmptyDayClockState extends State<_EmptyDayClock>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = TimeService.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _now = TimeService.now();
      });
    });
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _twoDigits(int value) {
    if (value >= 10) return '$value';
    return '0$value';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const text = 'bạn chưa thêm thời gian cho ngày này';
    final chars = text.split('');

    return GestureDetector(
      onTap: widget.onTapAdd,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary.withValues(alpha: 0.18),
                          colorScheme.secondary.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.7),
                        width: 2.5,
                      ),
                    ),
                  ),
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.brightness == Brightness.dark
                          ? const Color(0xff020617)
                          : Colors.white,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${_twoDigits(_now.hour)}:${_twoDigits(_now.minute)}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  RotationTransition(
                    turns: _controller,
                    child: Stack(
                      children: List.generate(chars.length, (index) {
                        final char = chars[index];
                        final angle = (2 * math.pi * index / chars.length) -
                            math.pi / 2;
                        const radius = 115.0;
                        final dx = radius * math.cos(angle);
                        final dy = radius * math.sin(angle);
                        return Transform.translate(
                          offset: Offset(dx, dy),
                          child: Transform.rotate(
                            angle: angle + math.pi / 2,
                            child: Text(
                              char,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color:
                                    colorScheme.secondary.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chạm để thêm thời gian biểu cho ngày này',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}


class AddSchedulePage extends StatefulWidget {
  final SubjectSchedule? initial;

  const AddSchedulePage({super.key, this.initial});

  @override
  State<AddSchedulePage> createState() => _AddSchedulePageState();
}

class _AddSchedulePageState extends State<AddSchedulePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _startTimeController = TextEditingController();
  String? _selectedDay;
  bool _useSpecificDate = false;
  DateTime? _pickedDate;
  bool _deleteOnSave = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _nameController.text = initial.name;
      _selectedDay = initial.dayOfWeek;
      _startTimeController.text = initial.startTime;
      if (initial.specificDate.isNotEmpty) {
        final parts = initial.specificDate.split('-');
        if (parts.length == 3) {
          final year = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final day = int.tryParse(parts[2]);
          if (year != null && month != null && day != null) {
            _pickedDate = DateTime(year, month, day);
            _useSpecificDate = true;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _startTimeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDay == null || _selectedDay!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chọn ngày / thứ cho thời gian biểu'),
        ),
      );
      return;
    }
    if (widget.initial != null && _deleteOnSave) {
      Navigator.of(context).pop({'delete': true});
      return;
    }

    final now = TimeService.now();
    final timeText = _startTimeController.text.trim();
    final timeParts = timeText.split(':');
    final hour = int.tryParse(timeParts[0]) ?? 0;
    final minute =
        int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0;

    DateTime scheduledDate;

    if (_useSpecificDate && _pickedDate != null) {
      scheduledDate = DateTime(
        _pickedDate!.year,
        _pickedDate!.month,
        _pickedDate!.day,
        hour,
        minute,
      );
    } else {
      int weekdayFromLabel(String label, int fallbackWeekday) {
        final normalized = label.trim().toLowerCase();
        if (normalized.contains('thứ 2')) return DateTime.monday;
        if (normalized.contains('thứ 3')) return DateTime.tuesday;
        if (normalized.contains('thứ 4')) return DateTime.wednesday;
        if (normalized.contains('thứ 5')) return DateTime.thursday;
        if (normalized.contains('thứ 6')) return DateTime.friday;
        if (normalized.contains('thứ 7')) return DateTime.saturday;
        if (normalized.contains('chủ nhật')) return DateTime.sunday;
        return fallbackWeekday;
      }

      final weekday = weekdayFromLabel(
        _selectedDay!.trim(),
        now.weekday,
      );

      DateTime base = DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      int diff = weekday - base.weekday;
      if (diff < 0 || (diff == 0 && base.isBefore(now))) {
        diff += 7;
      }
      scheduledDate = base.add(Duration(days: diff));
    }

    final specificDate =
        '${scheduledDate.year.toString().padLeft(4, '0')}-'
        '${scheduledDate.month.toString().padLeft(2, '0')}-'
        '${scheduledDate.day.toString().padLeft(2, '0')}';

    final subject = SubjectSchedule(
      name: _nameController.text.trim(),
      dayOfWeek: _selectedDay!.trim(),
      startTime: _startTimeController.text.trim(),
      endTime: '',
      room: '',
      specificDate: specificDate,
    );
    Navigator.of(context).pop(subject);
  }

  Future<void> _selectStartTime() async {
    int initialHour = TimeService.now().hour;
    int initialMinute = 0;
    if (_startTimeController.text.isNotEmpty) {
      final parts = _startTimeController.text.split(':');
      initialHour = int.tryParse(parts[0]) ?? initialHour;
      initialMinute =
          int.tryParse(parts.length > 1 ? parts[1] : '') ?? initialMinute;
    }

    int tempHour = initialHour;
    int tempMinute = initialMinute;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SizedBox(
          height: 260,
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Text(
                'Chọn giờ bắt đầu',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        magnification: 1.1,
                        itemExtent: 32,
                        scrollController: FixedExtentScrollController(
                          initialItem: initialHour,
                        ),
                        onSelectedItemChanged: (index) {
                          tempHour = index;
                        },
                        children: List<Widget>.generate(
                          24,
                          (index) => Center(
                            child: Text(
                              index.toString().padLeft(2, '0'),
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Text(
                      ':',
                      style: TextStyle(fontSize: 18),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        magnification: 1.1,
                        itemExtent: 32,
                        scrollController: FixedExtentScrollController(
                          initialItem: initialMinute,
                        ),
                        onSelectedItemChanged: (index) {
                          tempMinute = index;
                        },
                        children: List<Widget>.generate(
                          60,
                          (index) => Center(
                            child: Text(
                              index.toString().padLeft(2, '0'),
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final hh = tempHour.toString().padLeft(2, '0');
                      final mm = tempMinute.toString().padLeft(2, '0');
                      setState(() {
                        _startTimeController.text = '$hh:$mm';
                      });
                      Navigator.of(context).pop();
                    },
                    child: const Text('Xong'),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final now = TimeService.now();
    final initialDate = _pickedDate ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );
    if (date == null) return;
    setState(() {
      _pickedDate = date;
      switch (date.weekday) {
        case DateTime.monday:
          _selectedDay = 'Thứ 2';
          break;
        case DateTime.tuesday:
          _selectedDay = 'Thứ 3';
          break;
        case DateTime.wednesday:
          _selectedDay = 'Thứ 4';
          break;
        case DateTime.thursday:
          _selectedDay = 'Thứ 5';
          break;
        case DateTime.friday:
          _selectedDay = 'Thứ 6';
          break;
        case DateTime.saturday:
          _selectedDay = 'Thứ 7';
          break;
        case DateTime.sunday:
        default:
          _selectedDay = 'Chủ nhật';
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null
            ? 'Thêm thời gian biểu'
            : 'Sửa thời gian biểu'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên hoạt động',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nhập tên hoạt động';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Chọn ngày / thứ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    'Thứ 2',
                    'Thứ 3',
                    'Thứ 4',
                    'Thứ 5',
                    'Thứ 6',
                    'Thứ 7',
                    'Chủ nhật',
                  ].map((label) {
                    final selected = _selectedDay == label;
                    return ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _selectedDay = label;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _useSpecificDate,
                  onChanged: (value) {
                    setState(() {
                      _useSpecificDate = value ?? false;
                    });
                  },
                  title: const Text('Chọn ngày cụ thể'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (_useSpecificDate) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _pickedDate == null
                              ? 'Chưa chọn ngày'
                              : '${_pickedDate!.day.toString().padLeft(2, '0')}/'
                                  '${_pickedDate!.month.toString().padLeft(2, '0')}/'
                                  '${_pickedDate!.year}',
                        ),
                      ),
                      TextButton(
                        onPressed: _pickDate,
                        child: const Text('Chọn ngày'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _startTimeController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Giờ bắt đầu (HH:MM)',
                    helperText: 'Chạm để chọn giờ bằng đồng hồ xoay',
                    suffixIcon: Icon(Icons.access_time_outlined),
                  ),
                  onTap: _selectStartTime,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nhập giờ bắt đầu';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                if (widget.initial != null) ...[
                  CheckboxListTile(
                    value: _deleteOnSave,
                    onChanged: (value) {
                      setState(() {
                        _deleteOnSave = value ?? false;
                      });
                    },
                    title: const Text('Xóa thời gian biểu này'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Lưu thời gian biểu'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
