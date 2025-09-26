import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chat',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ChatPage(),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _msgController = TextEditingController();
  List<dynamic> messages = [];

  final String baseUrl = "https://lol154.pythonanywhere.com/messages";

  @override
  void initState() {
    super.initState();
    _loadMessages();
    Timer.periodic(const Duration(seconds: 5), (_) {
      _loadMessages();
    });
  }

  Future<void> _loadMessages() async {
    try {
      final response = await http.get(Uri.parse(baseUrl));
      debugPrint("GET ${response.statusCode} ${response.body}");
      if (response.statusCode == 200) {
        setState(() {
          messages = json.decode(response.body);
        });
      }
    } catch (e) {
      debugPrint("Ошибка загрузки: $e");
    }
  }

  Future<void> _sendMessage() async {
    if (_msgController.text.trim().isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "user": _userController.text.trim().isEmpty ? "Anon" : _userController.text.trim(),
          "text": _msgController.text.trim(),
        }),
      );
      debugPrint("POST ${response.statusCode} ${response.body}");
      if (response.statusCode == 201 || response.statusCode == 200) {
        _msgController.clear();
        _loadMessages();
      }
    } catch (e) {
      debugPrint("Ошибка отправки: $e");
    }
  }

  Widget _buildMessageItem(Map<String, dynamic> msg) {
    return ListTile(
      title: Text(msg["user"] ?? "Anon"),
      subtitle: Text(msg["text"] ?? ""),
      trailing: Text(msg["time"] ?? ""),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _userController,
              decoration: const InputDecoration(
                labelText: "Ваше имя",
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: messages.length,
              itemBuilder: (context, idx) {
                final msg = messages[messages.length - 1 - idx];
                return _buildMessageItem(msg);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _msgController,
                  decoration: const InputDecoration(
                    labelText: "Сообщение",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendMessage,
              )
            ]),
          ),
        ],
      ),
    );
  }
}
