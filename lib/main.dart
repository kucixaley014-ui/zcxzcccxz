import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

const String apiBase = "https://lol154.pythonanywhere.com";

void main() {
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const RootPage(),
    );
  }
}

/// Проверка: вошёл ли пользователь ранее
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  String? token;
  String? username;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString("token");
    final u = prefs.getString("username");
    if (t != null && u != null) {
      setState(() {
        token = t;
        username = u;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (token != null && username != null) {
      return ChatPage(token: token!, username: username!);
    } else {
      return const AuthPage();
    }
  }
}

/// Страница авторизации
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController userCtrl = TextEditingController();
  final TextEditingController passCtrl = TextEditingController();
  bool isLogin = true;
  String error = "";

  Future<void> _submit() async {
    setState(() => error = "");
    final username = userCtrl.text.trim();
    final password = passCtrl.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(() => error = "Введите имя и пароль");
      return;
    }

    final url = Uri.parse("$apiBase/${isLogin ? "login" : "register"}");
    final resp = await http.post(url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}));

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final data = jsonDecode(resp.body);
      if (isLogin) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("token", data["token"]);
        await prefs.setString("username", data["username"]);
        if (mounted) {
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => ChatPage(
                      token: data["token"], username: data["username"])));
        }
      } else {
        setState(() => isLogin = true);
      }
    } else {
      try {
        final data = jsonDecode(resp.body);
        setState(() => error = data["error"] ?? "Ошибка");
      } catch (_) {
        setState(() => error = "Ошибка сервера");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text(isLogin ? "Вход" : "Регистрация")),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(controller: userCtrl, decoration: const InputDecoration(labelText: "Имя")),
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: "Пароль"), obscureText: true),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _submit, child: Text(isLogin ? "Войти" : "Зарегистрироваться")),
            TextButton(
                onPressed: () => setState(() => isLogin = !isLogin),
                child: Text(isLogin ? "Регистрация" : "Уже есть аккаунт? Войти")),
            if (error.isNotEmpty)
              Text(error, style: const TextStyle(color: Colors.red)),
          ]),
        ));
  }
}

/// Сообщение
class Message {
  final int id;
  final String user;
  final String text;
  final String time;
  final bool edited;
  final bool deleted;
  final int? replyTo;

  Message(
      {required this.id,
      required this.user,
      required this.text,
      required this.time,
      required this.edited,
      required this.deleted,
      this.replyTo});

  factory Message.fromJson(Map<String, dynamic> j) {
    return Message(
        id: j["id"],
        user: j["user"],
        text: j["text"],
        time: j["time"],
        edited: j["edited"],
        deleted: j["deleted"],
        replyTo: j["reply_to"]);
  }
}

/// Чат
class ChatPage extends StatefulWidget {
  final String token;
  final String username;
  const ChatPage({super.key, required this.token, required this.username});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController msgCtrl = TextEditingController();
  final ScrollController scrollCtrl = ScrollController();
  Timer? timer;
  List<Message> messages = [];
  int? replyTo;
  bool notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final resp = await http.get(Uri.parse("$apiBase/messages"));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as List;
      final newMsgs = data.map((j) => Message.fromJson(j)).toList();
      if (messages.isNotEmpty && newMsgs.length > messages.length && !scrollCtrl.position.atEdge) {
        if (notificationsEnabled && mounted) {
          final last = newMsgs.last;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Новое сообщение от ${last.user}: ${last.text.length > 20 ? last.text.substring(0, 20) + "..." : last.text}"),
          ));
        }
      }
      setState(() => messages = newMsgs);
    }
  }

  Future<void> _sendMessage() async {
    final text = msgCtrl.text.trim();
    if (text.isEmpty) return;
    msgCtrl.clear();
    final resp = await http.post(Uri.parse("$apiBase/messages"),
        headers: {
          "Authorization": "Bearer ${widget.token}",
          "Content-Type": "application/json"
        },
        body: jsonEncode({"text": text, "reply_to": replyTo}));
    if (resp.statusCode == 201) {
      _loadMessages();
      setState(() => replyTo = null);
    }
  }

  Future<void> _logout() async {
    await http.post(Uri.parse("$apiBase/logout"),
        headers: {"Authorization": "Bearer ${widget.token}"});
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("token");
    await prefs.remove("username");
    if (mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const AuthPage()));
    }
  }

  Widget _msgTile(Message m) {
    final reply = m.replyTo != null
        ? messages.where((x) => x.id == m.replyTo).toList()
        : [];
    return ListTile(
      title: Text("${m.user}: ${m.text}"),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reply.isNotEmpty)
            Text("↪ ${reply.first.user}: ${reply.first.text}",
                style: const TextStyle(fontStyle: FontStyle.italic)),
          Text(m.time),
        ],
      ),
      onLongPress: m.deleted
          ? null
          : () => setState(() => replyTo = m.id), // Ответить
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text("Чат (${widget.username})"), actions: [
          IconButton(
              onPressed: () =>
                  setState(() => notificationsEnabled = !notificationsEnabled),
              icon: const Icon(Icons.emoji_emotions)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.exit_to_app))
        ]),
        body: Column(children: [
          if (replyTo != null)
            Container(
              color: Colors.grey[300],
              child: Row(children: [
                Expanded(
                    child: Text(
                        "Ответ на: ${messages.firstWhere((m) => m.id == replyTo).text}")),
                IconButton(
                    onPressed: () => setState(() => replyTo = null),
                    icon: const Icon(Icons.close))
              ]),
            ),
          Expanded(
              child: ListView.builder(
                  controller: scrollCtrl,
                  reverse: false,
                  itemCount: messages.length,
                  itemBuilder: (_, i) => _msgTile(messages[i]))),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: msgCtrl,
                    decoration: const InputDecoration(hintText: "Сообщение"))),
            IconButton(onPressed: _sendMessage, icon: const Icon(Icons.send))
          ])
        ]));
  }
}
