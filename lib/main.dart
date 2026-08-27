import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TeachTrackApp());
}

class TeachTrackApp extends StatelessWidget {
  const TeachTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teaching Routine Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const DashboardScreen(),
    );
  }
}

// Model Class
class Batch {
  String id;
  String name;
  String time;
  String days;
  String log;
  bool isCompleted;

  Batch({
    required this.id,
    required this.name,
    required this.time,
    required this.days,
    this.log = '',
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'time': time,
        'days': days,
        'log': log,
        'isCompleted': isCompleted,
      };

  factory Batch.fromJson(Map<String, dynamic> json) => Batch(
        id: json['id'],
        name: json['name'],
        time: json['time'],
        days: json['days'],
        log: json['log'] ?? '',
        isCompleted: json['isCompleted'] ?? false,
      );
}

// Dashboard Screen
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Batch> batches = [];
  bool isLoading = true;
  late SharedPreferences prefs;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('saved_batches');
    if (data != null) {
      Iterable decoded = jsonDecode(data);
      setState(() {
        batches = decoded.map((e) => Batch.fromJson(e)).toList();
      });
    }
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _saveData() async {
    await prefs.setString(
        'saved_batches', jsonEncode(batches.map((e) => e.toJson()).toList()));
  }

  void _addBatch(Batch batch) {
    setState(() {
      batches.add(batch);
    });
    _saveData();
  }

  void _updateLog(String id, String newLog) {
    setState(() {
      batches.firstWhere((b) => b.id == id).log = newLog;
    });
    _saveData();
  }

  void _toggleComplete(String id, bool status) {
    setState(() {
      batches.firstWhere((b) => b.id == id).isCompleted = status;
    });
    _saveData();
  }

  void _deleteBatch(String id) {
    setState(() {
      batches.removeWhere((b) => b.id == id);
    });
    _saveData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Batches'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('অফলাইন ডেটাবেস সফলভাবে সংযুক্ত!')),
              );
            },
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : batches.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.menu_book, size: 80, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'কোনো ব্যাচ যোগ করা হয়নি।\nনতুন ব্যাচ যোগ করতে + বাটনে ক্লিক করুন।',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: batches.length,
                  itemBuilder: (context, index) {
                    final batch = batches[index];
                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: Checkbox(
                          value: batch.isCompleted,
                          onChanged: (val) =>
                              _toggleComplete(batch.id, val ?? false),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                        ),
                        title: Text(
                          batch.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            decoration: batch.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text('সময়: ${batch.time}\nদিন: ${batch.days}'),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _deleteBatch(batch.id),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BatchDetailScreen(
                              batch: batch,
                              onSaveLog: (log) => _updateLog(batch.id, log),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddBatchDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Batch'),
      ),
    );
  }

  void _showAddBatchDialog() {
    final nameCtrl = TextEditingController();
    final timeCtrl = TextEditingController();
    final daysCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('নতুন ব্যাচ যুক্ত করুন'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'ব্যাচের নাম (যেমন: Class V)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: timeCtrl,
                decoration: const InputDecoration(
                    labelText: 'সময় (যেমন: সকাল ১০:০০)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: daysCtrl,
                decoration: const InputDecoration(
                    labelText: 'বার (যেমন: শনি, সোম, বুধ)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                _addBatch(Batch(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameCtrl.text,
                  time: timeCtrl.text.isEmpty ? 'নির্ধারিত নয়' : timeCtrl.text,
                  days: daysCtrl.text.isEmpty ? 'নির্ধারিত নয়' : daysCtrl.text,
                ));
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// Batch Details & Teaching Log Screen
class BatchDetailScreen extends StatefulWidget {
  final Batch batch;
  final Function(String) onSaveLog;

  const BatchDetailScreen(
      {super.key, required this.batch, required this.onSaveLog});

  @override
  State<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends State<BatchDetailScreen> {
  late TextEditingController _logCtrl;

  @override
  void initState() {
    super.initState();
    _logCtrl = TextEditingController(text: widget.batch.log);
  }

  @override
  void dispose() {
    _logCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.batch.name),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, color: Colors.indigo),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'সময়: ${widget.batch.time}\nদিন: ${widget.batch.days}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'টিচিং লগ (Teaching Log)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _logCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'আজ কী পড়িয়েছেন বা আগামী ক্লাসে কী পড়াবেন, তার বিস্তারিত এখানে লিখে রাখুন...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: () {
                  widget.onSaveLog(_logCtrl.text);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('টিচিং লগ সেভ করা হয়েছে!')),
                  );
                },
                icon: const Icon(Icons.save),
                label: const Text('Save Log', style: TextStyle(fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
