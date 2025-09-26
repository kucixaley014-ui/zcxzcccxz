import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Flutter Chat",
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String user;
  final String text;
  final DateTime time;

  ChatMessage({required this.user, required this.text, required this.time});

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      user: json['user'] ?? 'Anon',
      text: json['text'] ?? '',
      time: DateTime.parse(json['time']),
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
  final String baseUrl = "https://lol154.pythonanywhere.com";
  List<ChatMessage> messages = [];
  String username = "Anon";

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _fetchMessages();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      username = prefs.getString("username") ?? "Anon";
    });
  }

  Future<void> _saveUsername(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("username", name);
  }

  Future<void> _fetchMessages() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/messages"));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          messages = data.map((m) => ChatMessage.fromJson(m)).toList();
        });
      }
    } catch (e) {
      debugPrint("Ошибка загрузки: $e");
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/messages"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"name": username, "text": text}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        _controller.clear();
        _fetchMessages(); // обновляем чат
      }
    } catch (e) {
      debugPrint("Ошибка отправки: $e");
    }
  }

  void _askUsername() async {
    final controller = TextEditingController(text: username);
    String? newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Введите имя"),
        content: TextField(controller: controller),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text("Отмена")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text("Сохранить")),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      await _saveUsername(newName);
      setState(() => username = newName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Чат ($username)"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: _askUsername,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchMessages,
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[messages.length - 1 - index];
                bool isMe = msg.user == username;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.green[200] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(msg.user,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
                        Text(msg.text),
                        Text(DateFormat("HH:mm").format(msg.time),
                            style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: "Введите сообщение...",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () => _sendMessage(_controller.text),
              )
            ],
          )
        ],
      ),
    );
  }
}
