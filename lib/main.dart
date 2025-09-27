import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

const String serverBaseUrl = "https://lol154.pythonanywhere.com";

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

// ---------------- ЭКРАН АВТОРИЗАЦИИ ----------------
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
          const SnackBar(content: Text("Неверный логин или пароль")),
        );
      }
    } catch (e) {
      debugPrint("Ошибка входа: $e");
    }

    setState(() => _loading = false);
  }

  void _goRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );
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
                  const Text("Вход в чат",
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
                      : Column(
                          children: [
                            ElevatedButton(
                                onPressed: _login, child: const Text("Войти")),
                            TextButton(
                                onPressed: _goRegister,
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

// ---------------- ЭКРАН РЕГИСТРАЦИИ ----------------
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

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Регистрация успешна, войдите")),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ошибка регистрации")),
        );
      }
    } catch (e) {
      debugPrint("Ошибка регистрации: $e");
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
                : ElevatedButton(
                    onPressed: _register, child: const Text("Зарегистрироваться")),
          ]),
        ),
      ),
    );
  }
}

// ---------------- ЧАТ ----------------
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

  @override
  void initState() {
    super.initState();
    _loadToken();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString("token");
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final res = await http.get(Uri.parse("$serverBaseUrl/messages"));
      if (res.statusCode == 200) {
        setState(() => messages = jsonDecode(res.body));
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
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    } catch (e) {
      debugPrint("Ошибка отправки: $e");
    }
  }

  Future<void> _deleteMessage(int id) async {
    try {
      await http.delete(
        Uri.parse("$serverBaseUrl/messages/$id"),
        headers: {if (_token != null) "Authorization": "Bearer $_token"},
      );
      await _loadMessages();
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
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text("Сохранить")),
        ],
      ),
    );

    if (newText == null || newText.trim().isEmpty) return;

    try {
      await http.put(
        Uri.parse("$serverBaseUrl/messages/$id"),
        headers: {
          "Content-Type": "application/json",
          if (_token != null) "Authorization": "Bearer $_token"
        },
        body: jsonEncode({"text": newText}),
      );
      await _loadMessages();
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
    final status = await Permission.storage.request();
    if (!status.isGranted) {
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

    return GestureDetector(
      onLongPress: mine && !deleted
          ? () {
              showModalBottomSheet(
                context: context,
                builder: (_) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.edit),
                        title: const Text("Редактировать"),
                        onTap: () {
                          Navigator.pop(context);
                          _editMessage(m['id'], m['text'] ?? "");
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete),
                        title: const Text("Удалить"),
                        onTap: () {
                          Navigator.pop(context);
                          _deleteMessage(m['id']);
                        },
                      ),
                    ],
                  ),
                ),
              );
            }
          : null,
      child: Align(
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
                          Flexible(child: Text(att, overflow: TextOverflow.ellipsis)),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat 2.2"),
        actions: [
          IconButton(
              onPressed: _pickAndSendFile, icon: const Icon(Icons.attach_file)),
          IconButton(onPressed: _loadMessages, icon: const Icon(Icons.refresh)),
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
