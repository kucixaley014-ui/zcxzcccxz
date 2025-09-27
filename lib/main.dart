// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const ChatApp());
}

const String serverBaseUrl = "https://lol154.pythonanywhere.com"; // <- твой сервер

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat v2.0',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      debugShowCheckedModeBanner: false,
      home: const EntryDecider(),
    );
  }
}

class EntryDecider extends StatefulWidget {
  const EntryDecider({super.key});
  @override
  State<EntryDecider> createState() => _EntryDeciderState();
}

class _EntryDeciderState extends State<EntryDecider> {
  String? token;
  String? username;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadCreds();
  }

  Future<void> _loadCreds() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      token = prefs.getString('token');
      username = prefs.getString('username');
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (token == null) return const AuthPage();
    return ChatPage(token: token!, username: username ?? 'Anon');
  }
}

/// ---------- AUTH PAGE ----------
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool loading = false;

  Future<void> _register() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      _snack("Введите имя и пароль");
      return;
    }
    setState(() => loading = true);
    try {
      final res = await http.post(Uri.parse("$serverBaseUrl/register"),
          headers: {"Content-Type": "application/json"},
          body: json.encode({"username": user, "password": pass}));
      if (res.statusCode == 201) {
        _snack("Регистрация успешна — войдите");
      } else {
        final j = jsonDecode(res.body);
        _snack("Ошибка: ${j['error'] ?? res.statusCode}");
      }
    } catch (e) {
      _snack("Ошибка сети: $e");
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _login() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      _snack("Введите имя и пароль");
      return;
    }
    setState(() => loading = true);
    try {
      final res = await http.post(Uri.parse("$serverBaseUrl/login"),
          headers: {"Content-Type": "application/json"},
          body: json.encode({"username": user, "password": pass}));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        final token = j['token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        await prefs.setString('username', user);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatPage(token: token, username: user)));
      } else {
        final j = jsonDecode(res.body);
        _snack("Ошибка: ${j['error'] ?? res.statusCode}");
      }
    } catch (e) {
      _snack("Ошибка сети: $e");
    } finally {
      setState(() => loading = false);
    }
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Войти / Регистрация — Chat v2.0")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          TextField(controller: _userCtrl, decoration: const InputDecoration(labelText: "Имя")),
          const SizedBox(height: 8),
          TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Пароль")),
          const SizedBox(height: 16),
          if (loading) const CircularProgressIndicator(),
          if (!loading)
            Row(children: [
              Expanded(child: ElevatedButton(onPressed: _login, child: const Text("Войти"))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton(onPressed: _register, child: const Text("Регистрация"))),
            ]),
        ]),
      ),
    );
  }
}

/// ---------- CHAT PAGE ----------
class ChatPage extends StatefulWidget {
  final String token;
  final String username;
  const ChatPage({required this.token, required this.username, super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<dynamic> messages = [];
  final _msgCtrl = TextEditingController();
  Timer? _poller;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _poller = Timer.periodic(const Duration(seconds: 4), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final res = await http.get(Uri.parse("$serverBaseUrl/messages"));
      if (res.statusCode == 200) {
        setState(() => messages = json.decode(res.body));
      }
    } catch (e) {
      debugPrint("load error: $e");
    }
  }

  Future<void> _sendText() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await http.post(Uri.parse("$serverBaseUrl/messages"),
          headers: {"Content-Type": "application/json", "Authorization": "Bearer ${widget.token}"},
          body: json.encode({"text": text}));
      if (res.statusCode == 201) {
        _msgCtrl.clear();
        await _loadMessages();
      } else {
        debugPrint("send text failed ${res.statusCode} ${res.body}");
      }
    } catch (e) {
      debugPrint("send text error $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null) return;
    final filePath = result.files.single.path!;
    final fileName = result.files.single.name;
    setState(() => _loading = true);
    try {
      final req = http.MultipartRequest("POST", Uri.parse("$serverBaseUrl/upload"));
      req.headers['Authorization'] = "Bearer ${widget.token}";
      req.files.add(await http.MultipartFile.fromPath("file", filePath, filename: fileName));
      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 201) {
        final j = json.decode(res.body);
        final fname = j['filename'];
        // create message referencing that file by posting message with attachment via /messages multipart:
        final mreq = http.MultipartRequest("POST", Uri.parse("$serverBaseUrl/messages"));
        mreq.headers['Authorization'] = "Bearer ${widget.token}";
        mreq.fields['text'] = result.files.single.name;
        mreq.files.add(await http.MultipartFile.fromPath("file", filePath, filename: fileName));
        final mstream = await mreq.send();
        final mres = await http.Response.fromStream(mstream);
        if (mres.statusCode == 201) {
          await _loadMessages();
        } else {
          debugPrint("msg post fail ${mres.statusCode} ${mres.body}");
        }
      } else {
        debugPrint("upload fail ${res.statusCode} ${res.body}");
      }
    } catch (e) {
      debugPrint("file send error $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _editMessage(int id, String oldText) async {
    final controller = TextEditingController(text: oldText);
    final newText = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Редактировать сообщение"),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text("Отмена")),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text("Сохранить")),
        ],
      ),
    );
    if (newText == null || newText.isEmpty) return;
    final res = await http.put(Uri.parse("$serverBaseUrl/messages/$id"),
        headers: {"Content-Type": "application/json", "Authorization": "Bearer ${widget.token}"},
        body: json.encode({"text": newText}));
    if (res.statusCode == 200) {
      await _loadMessages();
    } else {
      debugPrint("edit failed ${res.statusCode} ${res.body}");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Не удалось изменить (только свои сообщения)")));
    }
  }

  Future<void> _deleteMessage(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Удалить сообщение?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Нет")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Да")),
        ],
      ),
    );
    if (ok != true) return;
    final res = await http.delete(Uri.parse("$serverBaseUrl/messages/$id"),
        headers: {"Authorization": "Bearer ${widget.token}"});
    if (res.statusCode == 200) {
      await _loadMessages();
    } else {
      debugPrint("delete failed ${res.statusCode} ${res.body}");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Не удалось удалить (только свои сообщения)")));
    }
  }

  void _showMessageOptions(Map msg) {
    final isMine = msg['user'] == widget.username;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text("Копировать"),
            onTap: () {
              Clipboard.setData(ClipboardData(text: msg['text'] ?? ""));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Скопировано")));
            },
          ),
          if (isMine)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text("Изменить"),
              onTap: () {
                Navigator.pop(context);
                _editMessage(msg['id'], msg['text'] ?? "");
              },
            ),
          if (isMine)
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text("Удалить"),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(msg['id']);
              },
            ),
          if (msg['attachment'] != null)
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text("Скачать/Открыть файл"),
              onTap: () {
                Navigator.pop(context);
                final url = "$serverBaseUrl/files/${msg['attachment']}";
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
            ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text("Закрыть"),
            onTap: () => Navigator.pop(context),
          ),
        ]),
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('username');
    // optionally call server /logout
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const EntryDecider()));
  }

  Widget _buildMessageTile(Map m) {
    final bool mine = m['user'] == widget.username;
    final bool deleted = m['deleted'] == true;
    final bool edited = m['edited'] == true;
    final att = m['attachment'];
    final timeText = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(m['time']));
    return GestureDetector(
      onLongPress: () => _showMessageOptions(m),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: mine ? Colors.green[400] : Colors.grey[300],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(m['user'] ?? "Anon", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (deleted)
                const Text("[message deleted]", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.black45))
              else ...[
                Text(m['text'] ?? ""),
                if (att != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InkWell(
                      onTap: () {
                        final url = "$serverBaseUrl/files/$att";
                        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.attach_file, size: 18),
                          const SizedBox(width: 6),
                          Flexible(child: Text(att, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (edited && !deleted)
                  const Text("edited", style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
                const SizedBox(width: 8),
                Text(timeText, style: const TextStyle(fontSize: 10, color: Colors.black87)),
              ]),
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
        title: Text("Chat v2.0 — ${widget.username}"),
        actions: [
          IconButton(icon: const Icon(Icons.attach_file), onPressed: _pickAndSendFile),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMessages,
              child: ListView.builder(
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (context, idx) {
                  final m = messages.length > 0 ? messages[messages.length - 1 - idx] : null;
                  if (m == null) return const SizedBox.shrink();
                  return _buildMessageTile(Map<String, dynamic>.from(m));
                },
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  decoration: const InputDecoration(hintText: "Введите сообщение..."),
                  minLines: 1,
                  maxLines: 4,
                ),
              ),
              IconButton(icon: const Icon(Icons.send), color: Colors.teal, onPressed: _sendText)
            ]),
          ),
        ],
      ),
    );
  }
}
