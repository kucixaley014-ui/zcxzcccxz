import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

const String serverBaseUrl = "https://lol154.pythonanywhere.com"; // локально для эмулятора

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
  Timer? _timer;
  final _recorder = Record();
  final _player = AudioPlayer();
  bool _recording = false;
  String? _recordPath;
  bool _previewMode = false;

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
    _recorder.dispose();
    _player.dispose();
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
        if (mounted) {
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

  Future<void> _sendVoice(String path) async {
    try {
      final req = http.MultipartRequest(
        "POST",
        Uri.parse("$serverBaseUrl/messages"),
      );
      if (_token != null) {
        req.headers["Authorization"] = "Bearer $_token";
      }
      req.files.add(await http.MultipartFile.fromPath("file", path));
      final res = await req.send();
      if (res.statusCode == 201) {
        _loadMessages();
      }
    } catch (e) {
      debugPrint("Ошибка отправки голосового: $e");
    }
  }

  Future<void> _startRecording() async {
    var status = await Permission.microphone.request();
    if (!status.isGranted) return;

    final dir = await getTemporaryDirectory();
    final path = "${dir.path}/${DateTime.now().millisecondsSinceEpoch}.m4a";
    await _recorder.start(path: path);
    setState(() {
      _recording = true;
      _recordPath = path;
      _previewMode = false;
    });
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    if (path != null) {
      setState(() {
        _recording = false;
        _previewMode = true; // после записи → режим предпрослушки
      });
    }
  }

  Widget _buildDateSeparator(DateTime date) {
    final text = DateFormat("yyyy-MM-dd").format(date);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.black)),
      ),
    );
  }

  Widget _buildMessageTile(Map m) {
    final bool mine = m['user'] == widget.username;
    final bool deleted = m['deleted'] == true;
    final msgType = m['type'] ?? "text";
    final time = DateTime.tryParse(m['time'] ?? "");
    final timeText =
        time != null ? DateFormat('HH:mm').format(time.add(const Duration(hours: 3))) : "";

    if (msgType == "voice" && m['attachment'] != null) {
      final url = "$serverBaseUrl/files/${m['attachment']}";
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: ListTile(
            leading: const Icon(Icons.mic, color: Colors.teal),
            title: Text(m['user'] ?? "Anon"),
            subtitle: Text("Голосовое сообщение"),
            trailing: IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () => _player.play(UrlSource(url)),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Card(
        color: mine ? Colors.teal[400] : Colors.white,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(m['user'] ?? "Anon",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: mine ? Colors.white : Colors.teal)),
              const SizedBox(height: 6),
              if (deleted)
                const Text("[удалено]",
                    style: TextStyle(
                        fontStyle: FontStyle.italic, color: Colors.redAccent))
              else
                Text(m['text'] ?? "",
                    style: TextStyle(
                        color: mine ? Colors.white : Colors.black,
                        fontSize: 16)),
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
    List<Widget> msgWidgets = [];
    DateTime? lastDate;
    for (var m in messages) {
      final msgTime = DateTime.tryParse(m['time'] ?? "");
      if (msgTime != null) {
        final localDate = DateTime(msgTime.year, msgTime.month, msgTime.day);
        if (lastDate == null || localDate != lastDate) {
          msgWidgets.add(_buildDateSeparator(localDate));
          lastDate = localDate;
        }
      }
      msgWidgets.add(_buildMessageTile(m));
    }

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
            child: ListView(
              controller: _scrollCtrl,
              children: msgWidgets,
            ),
          ),
          if (_previewMode && _recordPath != null)
            Container(
              color: Colors.grey[200],
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => _player.play(DeviceFileSource(_recordPath!))),
                  IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _previewMode = false;
                          _recordPath = null;
                        });
                      }),
                  IconButton(
                      icon: const Icon(Icons.send, color: Colors.teal),
                      onPressed: () {
                        if (_recordPath != null) {
                          _sendVoice(_recordPath!);
                          setState(() {
                            _previewMode = false;
                            _recordPath = null;
                          });
                        }
                      }),
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
                if (_ctrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.teal),
                    onPressed: () => _sendMessage(_ctrl.text),
                  )
                else
                  GestureDetector(
                    onLongPressStart: (_) => _startRecording(),
                    onLongPressEnd: (_) => _stopRecording(),
                    child: Icon(
                      _recording ? Icons.mic : Icons.mic_none,
                      color: Colors.red,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
