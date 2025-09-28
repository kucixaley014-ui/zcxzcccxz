import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

const String serverBaseUrl = "https://lol154.pythonanywhere.com";

// --- Notifications
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == "sendScheduledMessage") {
      final text = inputData?["text"] ?? "";
      final token = inputData?["token"];
      if (text.isNotEmpty && token != null) {
        try {
          await http.post(
            Uri.parse("$serverBaseUrl/messages"),
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer $token"
            },
            body: jsonEncode({"text": text}),
          );
        } catch (_) {}
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init notifications
  const AndroidInitializationSettings initSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: initSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // Init WorkManager
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);

  runApp(const MyApp());
}

// -------------------- APP --------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _getStartPage() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString("username");
    if (username != null) {
      return ChatPage(username: username);
    }
    return const AuthPage();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Chat App",
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: FutureBuilder(
        future: _getStartPage(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snap.data as Widget;
        },
      ),
    );
  }
}

// -------------------- AUTH --------------------

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _auth(String endpoint) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final res = await http.post(
        Uri.parse("$serverBaseUrl/$endpoint"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": _nameCtrl.text.trim(),
          "password": _passCtrl.text.trim(),
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["status"] == "ok") {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString("token", data["token"]);
          await prefs.setString("username", data["username"]);

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ChatPage(username: data["username"]),
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Ошибка: ${data["message"] ?? res.body}")),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ошибка: ${res.body}")),
        );
      }
    } catch (e) {
      debugPrint("Ошибка входа: $e");
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text("Вход в чат",
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: "Имя"),
                    validator: (v) => v!.isEmpty ? "Введите имя" : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Пароль"),
                    validator: (v) => v!.isEmpty ? "Введите пароль" : null,
                  ),
                  const SizedBox(height: 20),
                  _loading
                      ? const CircularProgressIndicator()
                      : Column(children: [
                          ElevatedButton(
                              onPressed: () => _auth("login"),
                              child: const Text("Войти")),
                          TextButton(
                              onPressed: () => _auth("register"),
                              child: const Text("Регистрация")),
                        ])
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- CHAT --------------------

class ChatPage extends StatefulWidget {
  final String username;
  const ChatPage({super.key, required this.username});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List messages = [];
  String? _token;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadToken();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("token");
    _loadMessages();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthPage()),
        (_) => false,
      );
    }
  }

  Future<void> _loadMessages() async {
    try {
      final res = await http.get(Uri.parse("$serverBaseUrl/messages"));
      if (res.statusCode == 200) {
        final newMsgs = jsonDecode(res.body);

        if (!mounted) return;

        // уведомления
        if (messages.isNotEmpty) {
          for (var msg in newMsgs) {
            if (!messages.any((m) => m["id"] == msg["id"]) &&
                msg["user"] != widget.username) {
              flutterLocalNotificationsPlugin.show(
                msg["id"],
                "Новое сообщение от ${msg["user"]}",
                msg["text"],
                const NotificationDetails(
                  android: AndroidNotificationDetails(
                    "chat_channel",
                    "Chat Messages",
                    importance: Importance.high,
                    priority: Priority.high,
                  ),
                ),
              );
            }
          }
        }

        final scrollPos = _scrollCtrl.position.pixels;
        final maxScroll = _scrollCtrl.position.maxScrollExtent;
        final atBottom = scrollPos >= (maxScroll - 50);

        setState(() => messages = newMsgs);

        if (atBottom) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollCtrl.hasClients) {
              _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Ошибка загрузки: $e");
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await http.post(
        Uri.parse("$serverBaseUrl/messages"),
        headers: {
          "Content-Type": "application/json",
          if (_token != null) "Authorization": "Bearer $_token"
        },
        body: jsonEncode({"text": text}),
      );
      _ctrl.clear();
      await _loadMessages();
    } catch (e) {
      debugPrint("Ошибка отправки: $e");
    }
  }

  Future<void> _scheduleMessage() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (selectedDate == null) return;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (selectedTime == null) return;

    final scheduledDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");

    Workmanager().registerOneOffTask(
      DateTime.now().millisecondsSinceEpoch.toString(),
      "sendScheduledMessage",
      initialDelay: scheduledDate.difference(DateTime.now()),
      inputData: {"text": _ctrl.text, "token": token},
    );

    _ctrl.clear();

    flutterLocalNotificationsPlugin.show(
      0,
      "Запланировано",
      "Сообщение отправится в ${DateFormat("HH:mm dd.MM.yyyy").format(scheduledDate)}",
      const NotificationDetails(
        android: AndroidNotificationDetails("channelId", "channelName",
            importance: Importance.high, priority: Priority.high),
      ),
    );
  }

  Widget _buildMessageTile(Map m, {bool showDateHeader = false}) {
    final bool mine = m['user'] == widget.username;
    final bool deleted = m['deleted'] == true;

    // время с прибавкой +3 часа
    DateTime msgTime = DateTime.tryParse(m['time'] ?? "") ?? DateTime.now();
    msgTime = msgTime.add(const Duration(hours: 3));
    final timeText = DateFormat('HH:mm').format(msgTime);

    return Column(
      children: [
        if (showDateHeader)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              DateFormat("yyyy-MM-dd").format(msgTime),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
        GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: m['text'] ?? ""));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Скопировано")),
            );
          },
          child: Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Card(
              color: mine ? Colors.teal[400] : Colors.white,
              elevation: 4,
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment:
                      mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['user'] ?? "Anon",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: mine ? Colors.white : Colors.teal,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (deleted)
                      const Text("[удалено]",
                          style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.redAccent))
                    else
                      Text(
                        m['text'] ?? "",
                        style: TextStyle(
                            color: mine ? Colors.white : Colors.black,
                            fontSize: 16),
                      ),
                    const SizedBox(height: 4),
                    Text(timeText,
                        style: TextStyle(
                            fontSize: 11,
                            color: mine ? Colors.white70 : Colors.black54)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String? lastDate;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat App"),
        actions: [
          IconButton(
              onPressed: _loadMessages, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final m = messages[i];
                DateTime msgTime =
                    DateTime.tryParse(m['time'] ?? "") ?? DateTime.now();
                msgTime = msgTime.add(const Duration(hours: 3));
                final msgDate = DateFormat("yyyy-MM-dd").format(msgTime);

                final showDateHeader = lastDate != msgDate;
                lastDate = msgDate;

                return _buildMessageTile(m, showDateHeader: showDateHeader);
              },
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: "Сообщение...",
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.teal),
                  onPressed: () => _sendMessage(_ctrl.text),
                ),
                IconButton(
                  icon: const Icon(Icons.schedule, color: Colors.orange),
                  onPressed: _scheduleMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
