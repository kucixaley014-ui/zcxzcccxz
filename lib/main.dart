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
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

const String serverBaseUrl = "https://lol154.pythonanywhere.com";

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Chat 2.1",
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const AuthPage(),
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

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("username", _nameCtrl.text.trim());

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(username: _nameCtrl.text.trim()),
        ),
      );
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text("Вход в чат", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                      : ElevatedButton(
                          onPressed: _login,
                          child: const Text("Войти"),
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

  @override
  void initState() {
    super.initState();
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
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user": widget.username, "text": text}),
      );
      _ctrl.clear();
      await _loadMessages();
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    } catch (e) {
      debugPrint("Ошибка отправки: $e");
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
        "user": widget.username,
        "text": fileName,
      });

      await dio.post(
        "$serverBaseUrl/messages",
        data: formData,
        onSendProgress: (sent, total) {
          final progress = (sent / total * 100).toStringAsFixed(0);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Загрузка $progress%")),
          );
        },
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
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(0);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Скачивание $progress%")),
            );
          }
        },
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Файл сохранён: $savePath")),
      );
    } catch (e) {
      debugPrint("Ошибка скачивания: $e");
    }
  }

  void _showMessageOptions(Map msg) {
    final mine = msg['user'] == widget.username;
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text("Копировать"),
              onTap: () {
                Clipboard.setData(ClipboardData(text: msg['text']));
                Navigator.pop(context);
              },
            ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text("Изменить"),
                onTap: () {
                  Navigator.pop(context);
                  _ctrl.text = msg['text'];
                },
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text("Удалить"),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => msg['deleted'] = true);
                },
              ),
            if (msg['attachment'] != null)
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text("Скачать файл"),
                onTap: () {
                  Navigator.pop(context);
                  _downloadFile(msg['attachment']);
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildMessageTile(Map m) {
    final bool mine = m['user'] == widget.username;
    final bool deleted = m['deleted'] == true;
    final att = m['attachment'];

    final timeText = m['time'] != null
        ? DateFormat('HH:mm').format(DateTime.tryParse(m['time']) ?? DateTime.now())
        : "";

    return GestureDetector(
      onLongPress: () => _showMessageOptions(m),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
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
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                const Text("[удалено]", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.red))
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
                          const Icon(Icons.attach_file, size: 18, color: Colors.blue),
                          const SizedBox(width: 6),
                          Flexible(child: Text(att, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
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
        title: const Text("Chat 2.1"),
        actions: [
          IconButton(onPressed: _pickAndSendFile, icon: const Icon(Icons.attach_file)),
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
