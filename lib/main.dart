import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

const SERVER = "https://your-server.example.com"; // <-- Поменяй на URL сервера (PythonAnywhere)

void main() {
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(home: SplashScreen());
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> {
  String? token, username;
  @override
  void initState() {
    super.initState();
    _restore();
  }
  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    token = sp.getString('token');
    username = sp.getString('username');
    if (token != null && username != null) {
      // verify token quickly
      final r = await http.get(Uri.parse('$SERVER/whoami'), headers: {"Authorization": token!});
      if (r.statusCode == 200) {
        final j = json.decode(r.body);
        if (j['user'] == username) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(token: token!, username: username!)));
          return;
        }
      }
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AuthScreen()));
  }
  @override Widget build(BuildContext c) => Scaffold(body: Center(child: CircularProgressIndicator()));
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override State<AuthScreen> createState() => _AuthScreenState();
}
class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  TextEditingController uC = TextEditingController();
  TextEditingController pC = TextEditingController();
  String err = '';

  Future<void> submit() async {
    final u = uC.text.trim();
    final p = pC.text;
    if (u.isEmpty || p.isEmpty) { setState(()=>err="Fill"); return; }
    final url = Uri.parse('$SERVER/${isLogin? "login":"register"}');
    final r = await http.post(url, headers: {"Content-Type":"application/json"}, body: json.encode({"username":u,"password":p}));
    final j = json.decode(r.body);
    if (r.statusCode==200 && j['ok']==true) {
      final token = j['token'];
      final sp = await SharedPreferences.getInstance();
      await sp.setString('token', token);
      await sp.setString('username', u);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(token: token, username: u)));
    } else {
      setState(()=>err = j['error'] ?? 'Error');
    }
  }

  @override Widget build(BuildContext c) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin? "Login":"Register")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          TextField(controller: uC, decoration: InputDecoration(labelText: "Username")),
          TextField(controller: pC, obscureText: true, decoration: InputDecoration(labelText: "Password")),
          const SizedBox(height:12),
          ElevatedButton(onPressed: submit, child: Text(isLogin? "Login":"Register")),
          TextButton(onPressed: ()=>setState(()=>isLogin=!isLogin), child: Text(isLogin? "Create account":"Have account? Login")),
          if (err.isNotEmpty) Text(err, style: TextStyle(color: Colors.red)),
        ]),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String token;
  final String username;
  const ChatScreen({required this.token, required this.username, super.key});
  @override State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  List messages = [];
  TextEditingController msgC = TextEditingController();
  bool typing = false;
  DateFormat df = DateFormat('HH:mm');
  @override void initState() { super.initState(); _loadMessages(); _startPoll(); }

  void _startPoll() {
    Future.doWhile(() async {
      await Future.delayed(Duration(seconds: 2));
      await _loadMessages();
      return true;
    });
  }

  Future<void> _loadMessages() async {
    final r = await http.get(Uri.parse('$SERVER/messages'));
    if (r.statusCode == 200) {
      final j = json.decode(r.body);
      setState(()=>messages = j['messages'] ?? []);
    }
  }

  Future<void> _sendMessage({String? fileUrl}) async {
    final text = msgC.text.trim();
    if (text.isEmpty && fileUrl == null) return;
    final r = await http.post(Uri.parse('$SERVER/messages'),
      headers: {"Content-Type":"application/json", "Authorization": widget.token},
      body: json.encode({"text": text, "file_url": fileUrl}));
    if (r.statusCode==200) {
      msgC.clear();
      await _loadMessages();
    }
  }

  Future<void> _uploadFileAndSend() async {
    final res = await FilePicker.platform.pickFiles();
    if (res == null) return;
    final path = res.files.single.path!;
    final fileName = res.files.single.name;
    var req = http.MultipartRequest('POST', Uri.parse('$SERVER/upload'));
    req.headers['Authorization'] = widget.token;
    req.files.add(await http.MultipartFile.fromPath('file', path, filename: fileName));
    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    final j = json.decode(body);
    if (j['ok']==true) {
      final fileUrl = j['file_url'];
      await _sendMessage(fileUrl: fileUrl);
    }
  }

  Future<void> _editMessage(String id) async {
    final txt = await showDialog<String>(context: context, builder: (c) {
      final t = TextEditingController();
      return AlertDialog(
        title: Text('Edit'),
        content: TextField(controller: t),
        actions: [TextButton(onPressed: ()=>Navigator.pop(c,null), child: Text('Cancel')), TextButton(onPressed: ()=>Navigator.pop(c,t.text), child: Text('Save'))],
      );
    });
    if (txt!=null) {
      await http.put(Uri.parse('$SERVER/messages/$id'),
        headers: {"Content-Type":"application/json", "Authorization": widget.token},
        body: json.encode({"text":txt}));
      await _loadMessages();
    }
  }

  Future<void> _deleteMessage(String id) async {
    await http.delete(Uri.parse('$SERVER/messages/$id'), headers: {"Authorization": widget.token});
    await _loadMessages();
  }

  Widget _buildMessage(m) {
    final me = m['user'] == widget.username;
    final text = m['deleted'] ? "[deleted]" : (m['text'] ?? '');
    final fileUrl = m['file_url'];
    final ts = DateTime.fromMillisecondsSinceEpoch((m['ts']??0)*1000);
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Card(
        color: me ? Colors.green[300] : Colors.grey[300],
        child: Container(
          padding: EdgeInsets.all(8),
          constraints: BoxConstraints(maxWidth: 300),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(m['user'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              SizedBox(width:8),
              Text(df.format(ts), style: TextStyle(fontSize: 10)),
            ]),
            SizedBox(height:6),
            if (fileUrl != null) GestureDetector(
              onTap: () async {
                final url = SERVER + fileUrl;
                // open via browser to download (simple)
                // In production use downloads plugin
              },
              child: Text("File: ${fileUrl.split('/').last}", style: TextStyle(decoration: TextDecoration.underline)),
            ),
            Text(text),
            if (me) Row(children: [
              TextButton(onPressed: ()=>_editMessage(m['id']), child: Text('Edit')),
              TextButton(onPressed: ()=>_deleteMessage(m['id']), child: Text('Delete')),
            ])
          ]),
        ),
      ),
    );
  }

  @override Widget build(BuildContext c) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat as ${widget.username}')),
      body: Column(children: [
        Expanded(child: ListView.builder(
          itemCount: messages.length,
          itemBuilder: (_,i) => _buildMessage(messages[i]),
        )),
        Row(children: [
          IconButton(icon: Icon(Icons.attach_file), onPressed: _uploadFileAndSend),
          Expanded(child: TextField(controller: msgC, decoration: InputDecoration(hintText: 'Message'))),
          IconButton(icon: Icon(Icons.send), onPressed: ()=>_sendMessage()),
        ])
      ]),
    );
  }
}
