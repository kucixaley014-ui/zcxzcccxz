import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация уведомлений
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: android);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  runApp(const MyApp());
}

const String serverBaseUrl = "https://lol154.pythonanywhere.com";

// глобальная переменная уведомлений
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

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

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
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
  bool _loading = false;
  Timer? _timer; // автообновление
  Set<int> notifiedIds = {}; // чтобы не дублировать уведомления

  @override
  void initState() {
    super.initState();
    _loadToken();

    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadMessages();
    });
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

        // Проверяем новые сообщения для уведомлений
        for (var m in newMsgs) {
          if (m['id'] != null &&
              !notifiedIds.contains(m['id']) &&
              m['user'] != widget.username) {
            DateTime msgTime =
                DateTime.tryParse(m['time'] ?? "") ?? DateTime.now();
            msgTime = msgTime.add(const Duration(hours: 3));

            final now = DateTime.now();
            if (msgTime.year == now.year &&
                msgTime.month == now.month &&
                msgTime.day == now.day &&
                msgTime.hour == now.hour &&
                msgTime.minute == now.minute) {
              _showNotification(m['user'] ?? "Anon", m['text'] ?? "");
              notifiedIds.add(m['id']);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Ошибка загрузки: $e");
    }
  }

  Future<void> _showNotification(String title, String body) async {
    const android = AndroidNotificationDetails(
      'chat_channel',
      'Chat Notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const details = NotificationDetails(android: android);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
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

  Future<void> _deleteMessage(int id) async {
    try {
      final res = await http.delete(
        Uri.parse("$serverBaseUrl/messages/$id"),
        headers: {"Authorization": "Bearer $_token"},
      );
      if (res.statusCode == 200) {
        _loadMessages();
      }
    } catch (e) {
      debugPrint("Ошибка удаления: $e");
    }
  }

  Future<void> _editMessage(Map m) async {
    final ctrl = TextEditingController(text: m['text']);
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Изменить сообщение"),
          content: TextField(controller: ctrl),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Отмена")),
            ElevatedButton(
              onPressed: () async {
                try {
                  final res = await http.put(
                    Uri.parse("$serverBaseUrl/messages/${m['id']}"),
                    headers: {
                      "Content-Type": "application/json",
                      "Authorization": "Bearer $_token",
                    },
                    body: jsonEncode({"text": ctrl.text}),
                  );
                  if (res.statusCode == 200) {
                    Navigator.pop(ctx);
                    _loadMessages();
                  }
                } catch (e) {
                  debugPrint("Ошибка изменения: $e");
                }
              },
              child: const Text("Сохранить"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDayDivider(DateTime date) {
    final dayText = DateFormat("yyyy-MM-dd").format(date);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              dayText,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          const Expanded(child: Divider(thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildMessageTile(Map m) {
    final bool mine = m['user'] == widget.username;
    final bool deleted = m['deleted'] == true;

    DateTime msgTime =
        DateTime.tryParse(m['time'] ?? "") ?? DateTime.now();
    msgTime = msgTime.add(const Duration(hours: 3));
    final timeText = DateFormat('HH:mm').format(msgTime);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Card(
        color: mine ? Colors.teal[400] : Colors.white,
        elevation: 4,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                        fontStyle: FontStyle.italic, color: Colors.redAccent))
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
    );
  }

  @override
  Widget build(BuildContext context) {
    DateTime? lastDate;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat App"),
        actions: [
          IconButton(onPressed: _loadMessages, icon: const Icon(Icons.refresh)),
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

                Widget msgWidget = _buildMessageTile(m);

                if (lastDate == null ||
                    lastDate!.year != msgTime.year ||
                    lastDate!.month != msgTime.month ||
                    lastDate!.day != msgTime.day) {
                  lastDate = msgTime;
                  return Column(
                    children: [
                      _buildDayDivider(msgTime),
                      msgWidget,
                    ],
                  );
                }

                return msgWidget;
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
