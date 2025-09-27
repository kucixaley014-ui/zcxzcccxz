import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() {
  runApp(const MyApp());
}

const String serverBaseUrl = "https://lol154.pythonanywhere.com";

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _initialized = false;
  Widget _startPage = const AuthPage();

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    const AndroidInitializationSettings initSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: initSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    final username = prefs.getString("username");

    setState(() {
      _initialized = true;
      if (token != null && username != null) {
        _startPage = ChatPage(username: username);
      } else {
        _startPage = const AuthPage();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      title: "Chat 2.5",
      theme: ThemeData(
        primarySwatch: Colors.teal,
      ),
      home: _startPage,
    );
  }
}

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

  Future<void> _loginOrRegister(bool register) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final res = await http.post(
        Uri.parse("$serverBaseUrl/${register ? 'register' : 'login'}"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": _nameCtrl.text.trim(),
          "password": _passCtrl.text.trim(),
        }),
      );

      if (res.statusCode == 200) {
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
          SnackBar(
              content: Text(register
                  ? "Ошибка регистрации"
                  : "Неверный логин или пароль")),
        );
      }
    } catch (e) {
      debugPrint("Ошибка: $e");
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
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text("Вход или регистрация",
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: "Имя"),
                    validator: (v) => v!.isEmpty ? "Введите имя" : null,
                  ),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Пароль"),
                    validator: (v) => v!.isEmpty ? "Введите пароль" : null,
                  ),
                  const SizedBox(height: 20),
                  _loading
                      ? const CircularProgressIndicator()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            ElevatedButton(
                                onPressed: () => _loginOrRegister(false),
                                child: const Text("Войти")),
                            ElevatedButton(
                                onPressed: () => _loginOrRegister(true),
                                child: const Text("Регистрация")),
                          ],
                        ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
  String? _replyToText;
  String? _replyToId;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("token");
    _loadMessages();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages());
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthPage()),
      );
    }
  }

  Future<void> _loadMessages() async {
    try {
      final res = await http.get(Uri.parse("$serverBaseUrl/messages"));
      if (res.statusCode == 200) {
        final newMessages = jsonDecode(res.body);

        // сохраняем позицию
        final pos = _scrollCtrl.hasClients ? _scrollCtrl.position.pixels : null;
        final max = _scrollCtrl.hasClients ? _scrollCtrl.position.maxScrollExtent : null;

        setState(() => messages = newMessages);

        if (pos != null && max != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollCtrl.jumpTo(pos.clamp(0, _scrollCtrl.position.maxScrollExtent));
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
        body: jsonEncode({"text": text, "reply_to": _replyToId}),
      );
      _ctrl.clear();
      setState(() {
        _replyToText = null;
        _replyToId = null;
      });
      await _loadMessages();
    } catch (e) {
      debugPrint("Ошибка отправки: $e");
    }
  }

  Future<void> _deleteMessage(String id) async {
    try {
      final res = await http.delete(
        Uri.parse("$serverBaseUrl/messages/$id"),
      );
      if (res.statusCode == 200) {
        await _loadMessages();
      }
    } catch (e) {
      debugPrint("Ошибка удаления: $e");
    }
  }

  void _onMessageLongPress(Map m) {
    final bool mine = m['user'] == widget.username;
    final bool deleted = m['deleted'] == true;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Wrap(children: [
        ListTile(
          leading: const Icon(Icons.reply),
          title: const Text("Ответить"),
          onTap: () {
            Navigator.pop(ctx);
            setState(() {
              _replyToText = m['text'];
              _replyToId = m['id'];
            });
          },
        ),
        if (mine && !deleted)
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text("Удалить"),
            onTap: () {
              Navigator.pop(ctx);
              _deleteMessage(m['id']);
            },
          ),
      ]),
    );
  }

  Widget _buildMessageTile(Map m) {
    final bool mine = m['user'] == widget.username;
    final bool deleted = m['deleted'] == true;

    final timeText = m['time'] != null
        ? DateFormat('HH:mm')
            .format(DateTime.tryParse(m['time']) ?? DateTime.now())
        : "";

    String? replyText;
    if (m['reply_to'] != null) {
      final replied = messages.firstWhere(
          (mm) => mm['id'] == m['reply_to'],
          orElse: () => null);
      if (replied != null) replyText = replied['text'];
    }

    return GestureDetector(
      onLongPress: () => _onMessageLongPress(m),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mine ? Colors.teal[400] : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(m['user'] ?? "Anon",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: mine ? Colors.white : Colors.teal)),
              if (replyText != null)
                Text("↪ $replyText",
                    style: const TextStyle(
                        fontStyle: FontStyle.italic, color: Colors.grey)),
              if (deleted)
                const Text("[удалено]",
                    style:
                        TextStyle(fontStyle: FontStyle.italic, color: Colors.red))
              else
                Text(m['text'] ?? "",
                    style: TextStyle(
                        color: mine ? Colors.white : Colors.black)),
              Text(timeText,
                  style: const TextStyle(fontSize: 10, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat 2.5"),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              itemCount: messages.length,
              itemBuilder: (_, i) => _buildMessageTile(messages[i]),
            ),
          ),
          if (_replyToText != null)
            Container(
              color: Colors.teal[50],
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(child: Text("Ответ: $_replyToText")),
                  IconButton(
                      onPressed: () {
                        setState(() {
                          _replyToText = null;
                          _replyToId = null;
                        });
                      },
                      icon: const Icon(Icons.close))
                ],
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
