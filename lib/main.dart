// main.dart
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationHelper.init();
  runApp(const MyApp());
}

const String serverBaseUrl = "https://lol154.pythonanywhere.com";

class NotificationHelper {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
  }

  static Future<void> show(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'chat_messages_channel',
      'Chat messages',
      channelDescription: 'Уведомления о новых сообщениях',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const iosDetails = DarwinNotificationDetails();
    await _plugin.show(0, title, body, const NotificationDetails(android: androidDetails, iOS: iosDetails));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Chat 2.2",
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const AuthPage(),
    );
  }
}

// ===================== AUTH =====================
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

  Future<void> _requestInitialPermissions() async {
    // Notifications (Android 13+ will actually prompt)
    await Permission.notification.request();
    // Storage (scoped) - ask generic storage permission; on modern Android apps it might be scoped storage
    await Permission.storage.request();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final res = await http.post(
        Uri.parse("$serverBaseUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": _nameCtrl.text.trim(),
          "password": _passCtrl.text.trim(),
        }),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("token", data["token"]);
        await prefs.setString("username", data["username"]);

        // запрашиваем разрешения (notification + storage)
        await _requestInitialPermissions();

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ChatPage(username: data["username"]),
            ),
          );
        }
      } else {
        String msg = "Неверный логин или пароль";
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body['error'] != null) msg = body['error'];
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      debugPrint("Ошибка входа: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ошибка соединения")));
    }

    setState(() => _loading = false);
  }

  void _goRegister() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text("Вход в чат", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Имя"), validator: (v) => v!.isEmpty ? "Введите имя" : null),
                  const SizedBox(height: 10),
                  TextFormField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Пароль"), validator: (v) => v!.isEmpty ? "Введите пароль" : null),
                  const SizedBox(height: 20),
                  _loading
                      ? const CircularProgressIndicator()
                      : Column(
                          children: [
                            ElevatedButton(onPressed: _login, child: const Text("Войти")),
                            TextButton(onPressed: _goRegister, child: const Text("Регистрация")),
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

// ===================== REGISTER =====================
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final res = await http.post(
        Uri.parse("$serverBaseUrl/register"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": _nameCtrl.text.trim(),
          "password": _passCtrl.text.trim(),
        }),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        // Авто-вход после успешной регистрации
        final loginRes = await http.post(
          Uri.parse("$serverBaseUrl/login"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "username": _nameCtrl.text.trim(),
            "password": _passCtrl.text.trim(),
          }),
        );
        if (loginRes.statusCode >= 200 && loginRes.statusCode < 300) {
          final data = jsonDecode(loginRes.body);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString("token", data["token"]);
          await prefs.setString("username", data["username"]);

          // запрос разрешений сразу после регистрации
          await Permission.notification.request();
          await Permission.storage.request();

          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatPage(username: data["username"])));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Зарегистрировано, но не удалось автоматически войти — войдите вручную")));
          Navigator.pop(context);
        }
      } else {
        String msg = "Ошибка регистрации";
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body['error'] != null) msg = body['error'];
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      debugPrint("Ошибка регистрации: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ошибка связи с сервером")));
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Регистрация")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(children: [
            TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Имя"), validator: (v) => v!.isEmpty ? "Введите имя" : null),
            const SizedBox(height: 10),
            TextFormField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Пароль"), validator: (v) => v!.isEmpty ? "Введите пароль" : null),
            const SizedBox(height: 20),
            _loading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _register, child: const Text("Зарегистрироваться")),
          ]),
        ),
      ),
    );
  }
}

// ===================== CHAT =====================
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
  int _lastId = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("token");
    await _loadMessages();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String _truncate(String s, [int max = 60]) {
    if (s == null) return "";
    return s.length <= max ? s : s.substring(0, max - 1) + '…';
  }

  Future<void> _loadMessages() async {
    try {
      final res = await http.get(Uri.parse("$serverBaseUrl/messages"));
      if (res.statusCode == 200) {
        final List<dynamic> remote = jsonDecode(res.body);
        // find new messages (by numeric id)
        int newMax = _lastId;
        for (var item in remote) {
          final id = item['id'] ?? 0;
          if (id is int && id > newMax) newMax = id;
        }
        // detect messages with id > _lastId and not from me => notify
        for (var item in remote) {
          final id = item['id'] ?? 0;
          final user = item['user'] ?? 'Anon';
          final text = item['text'] ?? '';
          if (id is int && id > _lastId && user != widget.username) {
            // show notification
            NotificationHelper.show(user, _truncate(text, 80));
          }
        }
        setState(() {
          messages = remote;
          _lastId = newMax;
        });
        // scroll to bottom safely
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Не удалось отправить сообщение")));
    }
  }

  Future<void> _deleteMessage(int id) async {
    try {
      final res = await http.delete(Uri.parse("$serverBaseUrl/messages/$id"), headers: {if (_token != null) "Authorization": "Bearer $_token"});
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _loadMessages();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ошибка удаления")));
      }
    } catch (e) {
      debugPrint("Ошибка удаления: $e");
    }
  }

  Future<void> _editMessage(int id, String oldText) async {
    final controller = TextEditingController(text: oldText);
    final newText = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Редактировать сообщение"),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Отмена")),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text("Сохранить")),
        ],
      ),
    );
    if (newText == null || newText.trim().isEmpty) return;
    try {
      final res = await http.put(Uri.parse("$serverBaseUrl/messages/$id"),
          headers: {"Content-Type": "application/json", if (_token != null) "Authorization": "Bearer $_token"}, body: jsonEncode({"text": newText}));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _loadMessages();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ошибка редактирования")));
      }
    } catch (e) {
      debugPrint("Ошибка редактирования: $e");
    }
  }

  Future<void> _pickAndSendFile() async {
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
      await dio.post("$serverBaseUrl/messages", data: formData, options: Options(headers: {if (_token != null) "Authorization": "Bearer $_token"}), onSendProgress: (s, t) {
        // optionally show progress
      });
      await _loadMessages();
    } catch (e) {
      debugPrint("Ошибка загрузки файла: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ошибка загрузки файла")));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<bool> _ensureStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      return status.isGranted;
    } else {
      return true;
    }
  }

  Future<void> _downloadFile(String filename) async {
    final ok = await _ensureStoragePermission();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Нет разрешения на запись")));
      return;
    }
    final dir = (await getExternalStorageDirectory()) ?? await getTemporaryDirectory();
    final savePath = "${dir.path}/$filename";
    final dio = Dio();
    try {
      await dio.download("$serverBaseUrl/files/$filename", savePath, onReceiveProgress: (r, t) {
        if (t > 0) {
          final p = (r / t * 100).toStringAsFixed(0);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Скачивание $p%")));
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Файл сохранён: $savePath")));
    } catch (e) {
      debugPrint("Ошибка скачивания: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ошибка скачивания файла")));
    }
  }

  void _onMessageLongPress(Map m) {
    final mine = m['user'] == widget.username;
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text("Копировать"),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m['text'] ?? ""));
                  Navigator.pop(context);
                },
              ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text("Изменить"),
                  onTap: () {
                    Navigator.pop(context);
                    _editMessage(m['id'], m['text'] ?? "");
                  },
                ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.delete),
                  title: const Text("Удалить"),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteMessage(m['id']);
                  },
                ),
              if (m['attachment'] != null)
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text("Скачать файл"),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadFile(m['attachment'] as String);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageTile(Map m) {
    final bool mine = m['user'] == widget.username;
    final bool deleted = m['deleted'] == true;
    final att = m['attachment'];
    final timeText = m['time'] != null ? DateFormat('HH:mm').format(DateTime.tryParse(m['time']) ?? DateTime.now()) : "";
    return GestureDetector(
      onLongPress: () => _onMessageLongPress(m),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: mine ? Colors.teal[400] : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 5, offset: const Offset(2, 3))],
          ),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(m['user'] ?? "Anon", style: TextStyle(fontWeight: FontWeight.bold, color: mine ? Colors.white : Colors.teal)),
              const SizedBox(height: 6),
              if (deleted)
                const Text("[удалено]", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.red))
              else ...[
                Text(m['text'] ?? "", style: TextStyle(color: mine ? Colors.white : Colors.black)),
                if (att != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InkWell(
                      onTap: () => _downloadFile(att as String),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.attach_file, size: 18, color: Colors.blue),
                        const SizedBox(width: 6),
                        Flexible(child: Text(att as String, overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                  ),
              ],
              const SizedBox(height: 4),
              Text(timeText, style: const TextStyle(fontSize: 10, color: Colors.black54)),
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
        title: const Text("Chat 2.2"),
        actions: [
          IconButton(onPressed: _pickAndSendFile, icon: const Icon(Icons.attach_file)),
          IconButton(onPressed: _loadMessages, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(controller: _scrollCtrl, itemCount: messages.length, itemBuilder: (_, i) => _buildMessageTile(messages[i] as Map)),
        ),
        if (_loading) const LinearProgressIndicator(),
        SafeArea(
          child: Row(children: [
            Expanded(
              child: TextField(controller: _ctrl, decoration: const InputDecoration(hintText: "Сообщение...", contentPadding: EdgeInsets.symmetric(horizontal: 12))),
            ),
            IconButton(icon: const Icon(Icons.send, color: Colors.teal), onPressed: () => _sendMessage(_ctrl.text)),
          ]),
        ),
      ]),
    );
  }
}
