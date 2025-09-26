import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const ChatApp());
}

const String serverBaseUrl = "https://lol154.pythonanywhere.com";

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Чат',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      debugShowCheckedModeBanner: false,
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final int? id;
  final String name;
  final String text;
  final DateTime ts;

  ChatMessage({this.id, required this.name, required this.text, required this.ts});

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    return ChatMessage(
      id: j['id'],
      name: j['name'],
      text: j['text'],
      ts: DateTime.parse(j['ts']),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<ChatMessage> _messages = [];
  String _username = "";
  Timer? _pollTimer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadUsername().then((_) {
      _loadMessages();
      _startPolling();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    String? name = prefs.getString('chat_username');
    if (name == null || name.trim().isEmpty) {
      await Future.delayed(Duration.zero);
      await _askForName();
    } else {
      setState(() => _username = name);
    }
  }

  Future<void> _askForName() async {
    String tmp = "";
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Введите ваше имя"),
        content: TextField(
          autofocus: true,
          onChanged: (v) => tmp = v,
          decoration: const InputDecoration(hintText: "Имя..."),
        ),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text("OK"),
          )
        ],
      ),
    );
    if (tmp.trim().isEmpty) {
      tmp = "User${DateTime.now().millisecondsSinceEpoch % 1000}";
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_username', tmp);
    setState(() => _username = tmp);
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse("$serverBaseUrl/messages"));
      if (res.statusCode == 200) {
        final List j = json.decode(res.body);
        final msgs = j.map((e) => ChatMessage.fromJson(e)).toList().cast<ChatMessage>();
        setState(() {
          _messages = msgs;
        });
      } else {
        // ошибка получения
        // print("Error fetching messages: ${res.statusCode}");
      }
    } catch (e) {
      // ошибка сети
      // print("Network error: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages());
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final payload = {"name": _username, "text": text};
    _controller.clear();
    try {
      final res = await http.post(
        Uri.parse("$serverBaseUrl/messages"),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );
      if (res.statusCode == 201 || res.statusCode == 200) {
        await _loadMessages();
        if (_scroll.hasClients) {
          _scroll.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      } else {
        // ошибка отправки
        // print("Error sending message: ${res.statusCode}");
      }
    } catch (e) {
      // ошибка сети
      // print("Send error: $e");
    }
  }

  Widget _buildDateSeparator(String date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        const Expanded(child: Divider()),
        const SizedBox(width: 8),
        Text(date, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(width: 8),
        const Expanded(child: Divider()),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msgs = List<ChatMessage>.from(_messages.reversed);

    String? lastDate;
    return Scaffold(
      appBar: AppBar(
        title: Text("Чат — $_username"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              String? newName = await showDialog<String?>(
                context: context,
                builder: (_) {
                  String tmp = "";
                  return AlertDialog(
                    title: const Text("Изменить имя"),
                    content: TextField(onChanged: (v) => tmp = v, decoration: const InputDecoration(hintText: "Новое имя")),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, null), child: const Text("Отмена")),
                      TextButton(onPressed: () => Navigator.pop(context, tmp), child: const Text("Сохранить")),
                    ],
                  );
                },
              );
              if (newName != null && newName.trim().isNotEmpty) {
                await SharedPreferences.getInstance().then((prefs) => prefs.setString('chat_username', newName.trim()));
                setState(() => _username = newName.trim());
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    itemCount: msgs.length,
                    itemBuilder: (context, idx) {
                      final m = msgs[idx];
                      final date = DateFormat('yyyy-MM-dd').format(m.ts);
                      Widget dateWidget = const SizedBox.shrink();
                      if (lastDate != date) {
                        lastDate = date;
                        dateWidget = _buildDateSeparator(date);
                      }

                      final isMe = m.name == _username;
                      final time = DateFormat.Hm().format(m.ts);

                      final bubble = Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.green[400] : Colors.grey[300],
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(isMe ? 12 : 0),
                              bottomRight: Radius.circular(isMe ? 0 : 12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                              Text(m.text, style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Text(time, style: TextStyle(fontSize: 11, color: isMe ? Colors.white70 : Colors.black54)),
                              ),
                            ],
                          ),
                        ),
                      );

                      return Column(
                        children: [
                          dateWidget,
                          bubble,
                        ],
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration.collapsed(hintText: "Введите сообщение..."),
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.deepPurple),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
