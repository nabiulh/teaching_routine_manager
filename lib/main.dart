// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz_data.initializeTimeZones();

  try {
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimezone.name));
  } catch (_) {
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {}
  }

  const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const settings = InitializationSettings(android: androidSettings);

  await notifications.initialize(
    settings,
    onDidReceiveNotificationResponse: (response) {},
  );

  await notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider()..initialize(),
      child: const TeachingRoutineApp(),
    ),
  );
}

// -----------------------------------------------------------------------------
// MODELS
// -----------------------------------------------------------------------------

class Batch {
  final String id;
  String title;
  int startMinutes;
  List<int> days;
  bool enabled;

  Batch({
    required this.id,
    required this.title,
    required this.startMinutes,
    required this.days,
    this.enabled = true,
  });

  String get timeLabel {
    final h = startMinutes ~/ 60;
    final m = startMinutes % 60;
    return DateFormat.jm().format(DateTime(2020, 1, 1, h, m));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startMinutes': startMinutes,
        'days': days,
        'enabled': enabled,
      };

  factory Batch.fromJson(Map<String, dynamic> json) {
    return Batch(
      id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? 'Untitled Batch',
      startMinutes: (json['startMinutes'] as num?)?.toInt() ?? 0,
      days: ((json['days'] as List?) ?? [])
          .map((e) => (e as num).toInt())
          .where((e) => e >= 1 && e <= 7)
          .toList(),
      enabled: json['enabled'] != false,
    );
  }
}

class TeachingLog {
  final String id;
  final String batchId;
  final DateTime date;
  final String text;

  TeachingLog({
    required this.id,
    required this.batchId,
    required this.date,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'batchId': batchId,
        'date': date.toIso8601String(),
        'text': text,
      };

  factory TeachingLog.fromJson(Map<String, dynamic> json) {
    return TeachingLog(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      batchId: json['batchId']?.toString() ?? '',
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      text: json['text']?.toString() ?? '',
    );
  }
}

// -----------------------------------------------------------------------------
// PROVIDER
// -----------------------------------------------------------------------------

class AppProvider extends ChangeNotifier {
  static const _dataKey = 'teaching_routine_data';
  static const _darkKey = 'dark_mode';

  final List<Batch> batches = [];
  final List<TeachingLog> logs = [];
  final Set<String> completedDates = {};

  bool darkMode = false;
  bool initialized = false;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    darkMode = prefs.getBool(_darkKey) ?? false;

    final raw = prefs.getString(_dataKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _loadJson(jsonDecode(raw));
      } catch (_) {}
    }

    initialized = true;
    notifyListeners();
    await rescheduleAllNotifications();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();

    final data = {
      'version': 1,
      'batches': batches.map((e) => e.toJson()).toList(),
      'logs': logs.map((e) => e.toJson()).toList(),
      'completedDates': completedDates.toList(),
    };

    await prefs.setString(_dataKey, jsonEncode(data));
  }

  void _loadJson(dynamic decoded) {
    if (decoded is! Map) return;

    batches
      ..clear()
      ..addAll(
        ((decoded['batches'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Batch.fromJson(Map<String, dynamic>.from(e))),
      );

    logs
      ..clear()
      ..addAll(
        ((decoded['logs'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => TeachingLog.fromJson(Map<String, dynamic>.from(e))),
      );

    completedDates
      ..clear()
      ..addAll(
        ((decoded['completedDates'] as List?) ?? [])
            .map((e) => e.toString()),
      );
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkKey, value);
  }

  void addBatch(Batch batch) {
    batches.add(batch);
    batches.sort(_sortBatches);
    notifyListeners();
    _save();
    rescheduleAllNotifications();
  }

  void updateBatch(Batch batch) {
    final index = batches.indexWhere((b) => b.id == batch.id);
    if (index == -1) return;

    batches[index] = batch;
    batches.sort(_sortBatches);
    notifyListeners();
    _save();
    rescheduleAllNotifications();
  }

  Future<void> deleteBatch(String id) async {
    batches.removeWhere((b) => b.id == id);
    logs.removeWhere((l) => l.batchId == id);
    notifyListeners();
    await _save();
    await rescheduleAllNotifications();
  }

  void addLog(String batchId, String text, DateTime date) {
    logs.insert(
      0,
      TeachingLog(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        batchId: batchId,
        date: date,
        text: text.trim(),
      ),
    );
    notifyListeners();
    _save();
  }

  void deleteLog(String id) {
    logs.removeWhere((l) => l.id == id);
    notifyListeners();
    _save();
  }

  List<Batch> get todaysBatches {
    final weekday = DateTime.now().weekday;

    return batches
        .where((b) => b.enabled && b.days.contains(weekday))
        .toList()
      ..sort(_sortBatches);
  }

  List<TeachingLog> logsForBatch(String batchId) {
    final result = logs.where((l) => l.batchId == batchId).toList();
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  bool isCompletedToday(String batchId) {
    return completedDates.contains(_completionKey(batchId, DateTime.now()));
  }

  Future<void> toggleCompleted(Batch batch) async {
    final key = _completionKey(batch.id, DateTime.now());

    if (completedDates.contains(key)) {
      completedDates.remove(key);
    } else {
      completedDates.add(key);
    }

    notifyListeners();
    await _save();
  }

  String _completionKey(String batchId, DateTime date) =>
      '$batchId-${DateFormat('yyyy-MM-dd').format(date)}';

  int _sortBatches(Batch a, Batch b) =>
      a.startMinutes.compareTo(b.startMinutes);

  // ---------------------------------------------------------------------------
  // EXPORT / IMPORT
  // ---------------------------------------------------------------------------

  Future<String?> exportData() async {
    final data = {
      'app': 'Teaching Routine & Batch Manager',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'batches': batches.map((e) => e.toJson()).toList(),
      'logs': logs.map((e) => e.toJson()).toList(),
      'completedDates': completedDates.toList(),
    };

    final jsonText =
        const JsonEncoder.withIndent('  ').convert(data);

    final directory = await getApplicationDocumentsDirectory();
    final defaultPath =
        '${directory.path}/teaching_routine_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';

    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Teaching Routine Backup',
      fileName: defaultPath.split(Platform.pathSeparator).last,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (selectedPath == null) return null;

    await File(selectedPath).writeAsString(jsonText);
    return selectedPath;
  }

  Future<bool> importData() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return false;

    final file = result.files.single;

    String content;

    if (file.bytes != null) {
      content = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      content = await File(file.path!).readAsString();
    } else {
      return false;
    }

    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) return false;

      _loadJson(decoded);
      batches.sort(_sortBatches);

      await _save();
      notifyListeners();
      await rescheduleAllNotifications();

      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // NOTIFICATIONS
  // ---------------------------------------------------------------------------

  Future<void> rescheduleAllNotifications() async {
    await notifications.cancelAll();

    for (final batch in batches.where((b) => b.enabled)) {
      await _scheduleBatchNotifications(batch);
    }
  }

  Future<void> _scheduleBatchNotifications(Batch batch) async {
    for (final weekday in batch.days) {
      final id = _notificationId(batch.id, weekday);

      final now = tz.TZDateTime.now(tz.local);

      var scheduled = _nextWeekdayTime(
        weekday: weekday,
        minutes: batch.startMinutes,
        from: now,
      );

      scheduled = scheduled.subtract(const Duration(minutes: 30));

      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 7));
      }

      try {
        await notifications.zonedSchedule(
          id,
          'Upcoming class',
          '${batch.title} starts in 30 minutes.',
          scheduled,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'teaching_classes',
              'Teaching Classes',
              channelDescription:
                  'Notifications for upcoming teaching batches.',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode:
              AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: batch.id,
        );
      } catch (_) {}
    }
  }

  tz.TZDateTime _nextWeekdayTime({
    required int weekday,
    required int minutes,
    required tz.TZDateTime from,
  }) {
    var date = tz.TZDateTime(
      tz.local,
      from.year,
      from.month,
      from.day,
      minutes ~/ 60,
      minutes % 60,
    );

    var difference = weekday - date.weekday;

    if (difference < 0 || (difference == 0 && date.isBefore(from))) {
      difference += 7;
    }

    date = date.add(Duration(days: difference));
    return date;
  }

  int _notificationId(String batchId, int weekday) {
    var hash = 0;
    for (final code in batchId.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return (hash % 100000) * 10 + weekday;
  }
}

// -----------------------------------------------------------------------------
// APP
// -----------------------------------------------------------------------------

class TeachingRoutineApp extends StatelessWidget {
  const TeachingRoutineApp({super.key});

  static const indigo = Color(0xFF303F9F);
  static const amber = Color(0xFFFFB300);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (_, provider, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Teaching Routine',
          themeMode:
              provider.darkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: indigo,
              brightness: Brightness.light,
            ).copyWith(
              secondary: amber,
            ),
            scaffoldBackgroundColor: const Color(0xFFF7F7FC),
            cardTheme: CardThemeData(
              elevation: 1,
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: indigo,
              brightness: Brightness.dark,
            ).copyWith(
              secondary: amber,
            ),
            cardTheme: CardThemeData(
              elevation: 1,
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          home: const DashboardPage(),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// DASHBOARD
// -----------------------------------------------------------------------------

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? timer;
  DateTime now = DateTime.now();

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final batches = provider.todaysBatches;

    final nextBatch = batches.cast<Batch?>().firstWhere(
          (batch) => !_isPast(batch!, now),
          orElse: () => null,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Teaching Routine',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Import / Export',
            onPressed: () => _showBackupMenu(context),
            icon: const Icon(Icons.import_export_rounded),
          ),
          IconButton(
            tooltip: 'Toggle theme',
            onPressed: () => provider.setDarkMode(!provider.darkMode),
            icon: Icon(
              provider.darkMode
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBatchForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Batch'),
      ),
      body: !provider.initialized
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: provider.rescheduleAllNotifications,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  _HeaderCard(
                    now: now,
                    nextBatch: nextBatch,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        "Today's Batches",
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        '${batches.length}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (batches.isEmpty)
                    _EmptyState(onAdd: () => _openBatchForm(context))
                  else
                    ...batches.map(
                      (batch) => _BatchCard(
                        batch: batch,
                        now: now,
                        completed:
                            provider.isCompletedToday(batch.id),
                        onTap: () => _openDetails(context, batch),
                        onComplete: () =>
                            provider.toggleCompleted(batch),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  bool _isPast(Batch batch, DateTime current) {
    final scheduled = DateTime(
      current.year,
      current.month,
      current.day,
      batch.startMinutes ~/ 60,
      batch.startMinutes % 60,
    );

    return scheduled.isBefore(current);
  }

  void _openBatchForm(BuildContext context, [Batch? batch]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchFormPage(batch: batch),
      ),
    );
  }

  void _openDetails(BuildContext context, Batch batch) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BatchDetailsPage(batchId: batch.id),
      ),
    );
  }

  void _showBackupMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_rounded),
              title: const Text('Export Backup'),
              subtitle: const Text('Save all data as JSON'),
              onTap: () async {
                Navigator.pop(context);
                final path =
                    await context.read<AppProvider>().exportData();

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      path == null
                          ? 'Export cancelled.'
                          : 'Backup exported successfully.',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Restore Backup'),
              subtitle: const Text('Import a JSON backup'),
              onTap: () async {
                Navigator.pop(context);
                final success =
                    await context.read<AppProvider>().importData();

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Backup restored successfully.'
                          : 'Could not restore the selected backup.',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final DateTime now;
  final Batch? nextBatch;

  const _HeaderCard({
    required this.now,
    required this.nextBatch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String countdown = 'No more classes today';

    if (nextBatch != null) {
      final target = DateTime(
        now.year,
        now.month,
        now.day,
        nextBatch!.startMinutes ~/ 60,
        nextBatch!.startMinutes % 60,
      );

      final difference = target.difference(now);

      if (difference.inSeconds > 0) {
        final hours = difference.inHours;
        final minutes = difference.inMinutes.remainder(60);
        final seconds = difference.inSeconds.remainder(60);

        countdown = hours > 0
            ? '${hours}h ${minutes}m ${seconds}s'
            : '${minutes}m ${seconds}s';
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primaryContainer,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE, d MMMM').format(now),
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              nextBatch?.title ?? 'You are all done!',
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (nextBatch != null) ...[
              const SizedBox(height: 4),
              Text(
                'Next class • ${nextBatch!.timeLabel}',
                style: TextStyle(
                  color: theme.colorScheme.onPrimary.withValues(alpha: .85),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    countdown,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  final Batch batch;
  final DateTime now;
  final bool completed;
  final VoidCallback onTap;
  final VoidCallback onComplete;

  const _BatchCard({
    required this.batch,
    required this.now,
    required this.completed,
    required this.onTap,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      batch.startMinutes ~/ 60,
      batch.startMinutes % 60,
    );

    final past = scheduled.isBefore(now);

    return Dismissible(
      key: ValueKey(batch.id),
      direction: completed
          ? DismissDirection.none
          : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onComplete();
        return false;
      },
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.only(right: 24),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.check_circle_rounded),
      ),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: completed
                        ? Colors.green.withValues(alpha: .12)
                        : theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    completed
                        ? Icons.check_rounded
                        : Icons.school_rounded,
                    color: completed
                        ? Colors.green
                        : theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(batch.timeLabel),
                          if (past && !completed) ...[
                            const SizedBox(width: 8),
                            const Text(
                              'Finished',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Teaching log',
                  onPressed: onTap,
                  icon: const Icon(Icons.notes_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Icon(Icons.event_available_rounded, size: 52),
            const SizedBox(height: 14),
            const Text(
              'No batches scheduled today',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 7),
            const Text(
              'Add a batch and select the days on which you teach.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Batch'),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// BATCH FORM
// -----------------------------------------------------------------------------

class BatchFormPage extends StatefulWidget {
  final Batch? batch;

  const BatchFormPage({super.key, this.batch});

  @override
  State<BatchFormPage> createState() => _BatchFormPageState();
}

class _BatchFormPageState extends State<BatchFormPage> {
  late final TextEditingController titleController;
  late TimeOfDay selectedTime;
  late Set<int> selectedDays;

  final days = const [
    (1, 'Mon'),
    (2, 'Tue'),
    (3, 'Wed'),
    (4, 'Thu'),
    (5, 'Fri'),
    (6, 'Sat'),
    (7, 'Sun'),
  ];

  @override
  void initState() {
    super.initState();

    final batch = widget.batch;

    titleController =
        TextEditingController(text: batch?.title ?? '');

    if (batch != null) {
      selectedTime = TimeOfDay(
        hour: batch.startMinutes ~/ 60,
        minute: batch.startMinutes % 60,
      );
      selectedDays = batch.days.toSet();
    } else {
      selectedTime = const TimeOfDay(hour: 17, minute: 0);
      selectedDays = {};
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.batch != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit Batch' : 'Add Batch'),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _deleteBatch,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Batch title',
              hintText: 'e.g. Class 8 Mathematics',
              prefixIcon: Icon(Icons.school_outlined),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.access_time_rounded),
              title: const Text('Class time'),
              subtitle: Text(
                selectedTime.format(context),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickTime,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Teaching days',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: days.map((day) {
              final selected = selectedDays.contains(day.$1);

              return FilterChip(
                label: Text(day.$2),
                selected: selected,
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      selectedDays.add(day.$1);
                    } else {
                      selectedDays.remove(day.$1);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 30),
          FilledButton.icon(
            onPressed: _saveBatch,
            icon: const Icon(Icons.save_rounded),
            label: Text(editing ? 'Save Changes' : 'Create Batch'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: selectedTime,
    );

    if (picked != null) {
      setState(() => selectedTime = picked);
    }
  }

  void _saveBatch() {
    final title = titleController.text.trim();

    if (title.isEmpty) {
      _error('Please enter a batch title.');
      return;
    }

    if (selectedDays.isEmpty) {
      _error('Select at least one teaching day.');
      return;
    }

    final batch = Batch(
      id: widget.batch?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      startMinutes: selectedTime.hour * 60 + selectedTime.minute,
      days: selectedDays.toList()..sort(),
      enabled: widget.batch?.enabled ?? true,
    );

    final provider = context.read<AppProvider>();

    if (widget.batch == null) {
      provider.addBatch(batch);
    } else {
      provider.updateBatch(batch);
    }

    Navigator.pop(context);
  }

  Future<void> _deleteBatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete batch?'),
        content: const Text(
          'This will also delete all teaching logs for this batch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AppProvider>().deleteBatch(widget.batch!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

// -----------------------------------------------------------------------------
// BATCH DETAILS / TEACHING LOG
// -----------------------------------------------------------------------------

class BatchDetailsPage extends StatelessWidget {
  final String batchId;

  const BatchDetailsPage({
    super.key,
    required this.batchId,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final batch = provider.batches
        .where((b) => b.id == batchId)
        .cast<Batch?>()
        .firstOrNull;

    if (batch == null) {
      return const Scaffold(
        body: Center(child: Text('Batch not found.')),
      );
    }

    final logs = provider.logsForBatch(batchId);

    return Scaffold(
      appBar: AppBar(
        title: Text(batch.title),
        actions: [
          IconButton(
            tooltip: 'Edit batch',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BatchFormPage(batch: batch),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addLog(context),
        icon: const Icon(Icons.add_comment_rounded),
        label: const Text('Add Log'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    child: const Icon(Icons.school_rounded),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          batch.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${batch.timeLabel} • ${_dayLabels(batch.days)}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Teaching Log',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.menu_book_outlined, size: 46),
                    SizedBox(height: 10),
                    Text(
                      'No teaching logs yet.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
          else
            ...logs.map(
              (log) => _LogCard(
                log: log,
                onDelete: () => provider.deleteLog(log.id),
              ),
            ),
        ],
      ),
    );
  }

  String _dayLabels(List<int> selected) {
    const names = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];

    return selected.map((e) => names[e - 1]).join(', ');
  }

  Future<void> _addLog(BuildContext context) async {
    final controller = TextEditingController();

    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Teaching Log'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText:
                'e.g. Taught Chapter 1\nHomework: Worksheet 2',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (text != null && text.isNotEmpty && context.mounted) {
      context.read<AppProvider>().addLog(
            batchId,
            text,
            DateTime.now(),
          );
    }
  }
}

class _LogCard extends StatelessWidget {
  final TeachingLog log;
  final VoidCallback onDelete;

  const _LogCard({
    required this.log,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_note_rounded,
                  size: 19,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 7),
                Text(
                  DateFormat('EEE, d MMM yyyy').format(log.date),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              log.text,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HELPERS
// -----------------------------------------------------------------------------

extension FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
