import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
    // Уведомления
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
      title: "Chat 2.3",
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[100],
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text("Добро пожаловать",
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
  bool _loading = false;
  String? _token;
  Timer? _timer;
  bool _notifyEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("token");
    _notifyEnabled = prefs.getBool("notify_enabled") ?? true;
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

        // уведомления, если новые и чат не на экране
        if (_notifyEnabled && messages.isNotEmpty) {
          if (newMessages.length > messages.length) {
            final last = newMessages.last;
            if (last['user'] != widget.username) {
              _showNotification(
                  "${last['user']}",
                  "${last['text']}"
                      .substring(0, last['text'].length.clamp(0, 30)));
            }
          }
        }

        final atBottom = _scrollCtrl.hasClients &&
            _scrollCtrl.position.pixels >=
                _scrollCtrl.position.maxScrollExtent - 50;

        setState(() => messages = newMessages);

        if (atBottom && _scrollCtrl.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          });
        }
      }
    } catch (e) {
      debugPrint("Ошибка загрузки: $e");
    }
  }

  Future<void> _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'chat_channel',
      'Chat Messages',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
        0, title, body, details, payload: "chat");
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

  Future<void> _pickAndSendFile() async {
    if (!await Permission.storage.request().isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Нет доступа к памяти")));
      return;
    }

    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    final filePath = result.files.single.path!;
    final fileName = result.files.single.name;

    setState(() => _loading = true);

    try {
      final dio = Dio();
      final formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(filePath, filename: fileName),
        "text": fileName,
      });

      await dio.post(
        "$serverBaseUrl/messages",
        data: formData,
        options: Options(headers: {
          if (_token != null) "Authorization": "Bearer $_token"
        }),
      );

      await _loadMessages();
    } catch (e) {
      debugPrint("Ошибка загрузки файла: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _downloadFile(String filename) async {
    if (!await Permission.storage.request().isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Нет доступа к памяти")),
      );
      return;
    }

    final dir = await getExternalStorageDirectory();
    final savePath = "${dir!.path}/$filename";

    final dio = Dio();
    try {
      await dio.download(
        "$serverBaseUrl/files/$filename",
        savePath,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Файл сохранён: $savePath")),
      );
    } catch (e) {
      debugPrint("Ошибка скачивания: $e");
    }
  }

  Widget _buildMessageTile(Map m) {
    final bool mine = m['user'] == widget.username;
    final bool deleted = m['deleted'] == true;
    final att = m['attachment'];

    final timeText = m['time'] != null
        ? DateFormat('HH:mm')
            .format(DateTime.tryParse(m['time']) ?? DateTime.now())
        : "";

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.all(12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: mine ? Colors.teal[400] : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 5,
              offset: const Offset(2, 3),
            ),
          ],
        ),
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
                      fontStyle: FontStyle.italic, color: Colors.red))
            else ...[
              Text(
                m['text'] ?? "",
                style: TextStyle(color: mine ? Colors.white : Colors.black),
              ),
              if (att != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InkWell(
                    onTap: () => _downloadFile(att),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.attach_file,
                            size: 18, color: Colors.blue),
                        const SizedBox(width: 6),
                        Flexible(child: Text(att,
                            overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 4),
            Text(timeText,
                style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat 2.3"),
        actions: [
          IconButton(
              onPressed: _pickAndSendFile, icon: const Icon(Icons.attach_file)),
          IconButton(onPressed: _loadMessages, icon: const Icon(Icons.refresh)),
          IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SettingsPage()), // ⚙️
                ).then((_) => _loadToken());
              },
              icon: const Icon(Icons.settings)),
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

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notifyEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifyEnabled = prefs.getBool("notify_enabled") ?? true;
    });
  }

  Future<void> _toggle(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("notify_enabled", v);
    setState(() => _notifyEnabled = v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Настройки")),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text("Уведомления"),
            subtitle: const Text("Получать уведомления, когда вы не в чате"),
            value: _notifyEnabled,
            onChanged: _toggle,
          ),
        ],
      ),
    );
  }
}
