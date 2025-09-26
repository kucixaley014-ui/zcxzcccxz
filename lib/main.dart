import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

const String baseUrl = "https://lol154.pythonanywhere.com";

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Chat',
      theme: ThemeData(
        primarySwatch: Colors.teal,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final String user;
  final DateTime time;

  ChatMessage({required this.text, required this.user, required this.time});

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text'] ?? "",
      user: json['user'] ?? json['name'] ?? "Anon",
      time: DateTime.tryParse(json['time'] ?? "") ?? DateTime.now(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<ChatMessage> messages = [];
  final TextEditingController _controller = TextEditingController();
  String username = "Anon";

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _fetchMessages();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedName = prefs.getString("username");

    if (savedName == null) {
      savedName = "User${DateTime.now().millisecondsSinceEpoch % 1000}";
      await prefs.setString("username", savedName);
    }

    setState(() {
      username = savedName!;
    });
  }

  Future<void> _fetchMessages() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/messages"));
      debugPrint("GET статус: ${response.statusCode}, тело: ${response.body}");
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          messages = data.map((m) => ChatMessage.fromJson(m)).toList();
        });
      } else {
        debugPrint("Ошибка GET: ${response.body}");
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
        body: json.encode({"name": username, "text": text}), // ✅ сервер ждёт name
      );
      debugPrint("POST статус: ${response.statusCode}, тело: ${response.body}");
      if (response.statusCode == 200 || response.statusCode == 201) {
        _controller.clear();
        _fetchMessages();
      } else {
        debugPrint("Ошибка POST: ${response.body}");
      }
    } catch (e) {
      debugPrint("Ошибка отправки: $e");
    }
  }

  Widget _buildMessage(ChatMessage msg) {
    bool isMine = msg.user == username;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMine ? Colors.green[300] : Colors.grey[300],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg.user,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            Text(msg.text),
            Text(
              DateFormat("HH:mm").format(msg.time),
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Flutter Chat"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return _buildMessage(messages[messages.length - 1 - index]);
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: "Введите сообщение...",
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.teal),
                  onPressed: () => _sendMessage(_controller.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
