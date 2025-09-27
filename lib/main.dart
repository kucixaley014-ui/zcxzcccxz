// lib/main.dart
import 'dart:async';
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
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String serverBaseUrl = "https://lol154.pythonanywhere.com"; // твой сервер

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация локальных уведомлений
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher'); // используй свой icon
  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: null,
    macOS: null,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Chat 2.3",
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const EntryDecider(),
    );
  }
}

/// Решает, показывать экран логина или сразу чат, если есть token+username
class EntryDecider extends StatefulWidget {
  const EntryDecider({super.key});

  @override
  State<EntryDecider> createState() => _EntryDeciderState();
}

class _EntryDeciderState extends State<EntryDecider> {
  Future<Map<String?, String?>> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final username = prefs.getString('username');
    final notif = prefs.getBool('notify_enabled') ?? true;
    return {'token': token, 'username': username, 'notif': notif.toString()};
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String?, String?>>(
      future: _check(),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final token = snap.data!['token'];
        final username = snap.data!['username'];
        if (token != null && username != null) {
          return ChatPage(username: username, token: token);
        } else {
          return const AuthPage();
        }
      },
    );
  }
}

/// --- Auth Page (Register / Login) ---
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _isRegister = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _toggleRegister() async {
    setState(() => _isRegister = !_isRegister);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final username = _nameCtrl.text.trim();
    final password = _passCtrl.text.trim();

    try {
      final url = _isRegister ? '$serverBaseUrl/register' : '$serverBaseUrl/login';
      final res = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();

        // login endpoint returns token+username; register may not — если регистр успешна, надо логиниться автоматически
        if (_isRegister && (data['status'] == 'ok' || res.statusCode == 201)) {
          // после регистрации попытаемся залогинить автоматически
          final loginRes = await http.post(
            Uri.parse('$serverBaseUrl/login'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"username": username, "password": password}),
          );
          if (loginRes.statusCode == 200) {
            final loginData = jsonDecode(loginRes.body);
            await prefs.setString('token', loginData['token']);
            await prefs.setString('username', loginData['username']);
            await prefs.setBool('notify_enabled', true);
            if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatPage(username: loginData['username'], token: loginData['token'])));
            return;
          } else {
            // регистрация успешна, но автоматический логин упал — всё равно покажем сообщение
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Регистрация прошла, попробуйте войти.')));
          }
        }

        if (!_isRegister && data['token'] != null) {
          await prefs.setString('token', data['token']);
          await prefs.setString('username', data['username']);
          await prefs.setBool('notify_enabled', true);
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatPage(username: data['username'], token: data['token'])));
          return;
        }

        // на случай, если сервер вернул ok (при регистрации) — обработано выше.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ответ сервера: ${res.statusCode} ${res.body}')));
      } else {
        // полезно показать тело ответа для отладки — но не перегружать пользователя
        String msg;
        try {
          final j = jsonDecode(res.body);
          msg = j['error'] ?? j['message'] ?? res.body;
        } catch (e) {
          msg = res.body;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $msg')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сети: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
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
                  Text(_isRegister ? "Регистрация" : "Вход в чат", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: "Имя"),
                    validator: (v) => v!.isEmpty ? "Введите имя" : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Пароль"),
                    validator: (v) => v!.isEmpty ? "Введите пароль" : null,
                  ),
                  const SizedBox(height: 16),
                  _loading
                      ? const CircularProgressIndicator()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton(onPressed: _submit, child: Text(_isRegister ? "Зарегистрироваться" : "Войти")),
                            TextButton(onPressed: _toggleRegister, child: Text(_isRegister ? "Уже есть аккаунт?" : "Регистрация")),
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

/// --- Chat Page ---
class ChatPage extends StatefulWidget {
  final String username;
  final String token;
  const ChatPage({super.key, required this.username, required this.token});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> messages = [];
  bool _loading = false;
  bool _uploading = false;
  Timer? _pollTimer;
  bool _appInForeground = true;
  bool _notifEnabled = true;
  String? _editingId; // id редактируемого сообщения (если не null)
  double _lastScrollPos = 0.0;
  bool _userScrolledUp = false;
  final Dio _dio = Dio();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFromPrefs();
    _scrollCtrl.addListener(_onScroll);
    _startPolling();
  }

  Future<void> _initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _notifEnabled = prefs.getBool('notify_enabled') ?? true;
    // token уже передан в widget.token
    await _loadMessages();
  }

  void _onScroll() {
    final max = _scrollCtrl.position.maxScrollExtent;
    final pos = _scrollCtrl.position.pixels;
    _userScrolledUp = pos < (max - 150); // если от конца больше 150 пикс — считаем, что юзер поднялся
    _lastScrollPos = pos;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    // загружаем и сравниваем — если есть новые и приложение в фоне -> локальное уведомление
    try {
      final res = await http.get(Uri.parse("$serverBaseUrl/messages"));
      if (res.statusCode == 200) {
        final List<dynamic> remote = jsonDecode(res.body);
        final newList = remote.map((e) => Map<String, dynamic>.from(e)).toList();

        bool hasNewForMe = false;
        if (messages.isNotEmpty) {
          final lastKnownId = messages.last['id'];
          for (final m in newList) {
            if (m['id'] != null && m['id'] > lastKnownId && m['user'] != widget.username) {
              hasNewForMe = true;
              break;
            }
          }
        } else {
          // если раньше пусто и теперь не пусто — новые сообщения тоже считаем
          if (newList.isNotEmpty) hasNewForMe = true;
        }

        final wasEmpty = messages.isEmpty;
        setState(() => messages = newList);

        // уведомление если в фоне и включены уведомления и есть новые от других
        if (!_appInForeground && _notifEnabled && hasNewForMe) {
          _showLocalNotification("Новое сообщение", "${newList.last['user']}: ${_truncate(newList.last['text'] ?? '')}");
        }

        // автоскролл: только если пользователь не листал вверх (т.е. _userScrolledUp == false)
        if (!_userScrolledUp) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollCtrl.hasClients) {
              _scrollCtrl.animateTo(
                _scrollCtrl.position.maxScrollExtent,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            }
          });
        } else {
          // если пользователь был вверху — не дергаем позицию
        }
      }
    } catch (e) {
      debugPrint("Poll error: $e");
    }
  }

  Future<void> _loadMessages() async {
    try {
      final res = await http.get(Uri.parse("$serverBaseUrl/messages"));
      if (res.statusCode == 200) {
        final List<dynamic> remote = jsonDecode(res.body);
        setState(() => messages = remote.map((e) => Map<String, dynamic>.from(e)).toList());
        // прокрутим вниз при начальной загрузке
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      debugPrint("Ошибка загрузки сообщений: $e");
    }
  }

  Future<void> _showLocalNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'chat_messages', 'Chat Messages',
      channelDescription: 'Уведомления о новых сообщениях',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(0, title, body, platformChannelSpecifics);
  }

  String _truncate(String s, [int len = 40]) {
    if (s.length <= len) return s;
    return s.substring(0, len - 1) + "…";
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (_editingId != null) {
      // отправляем редактирование
      final id = int.tryParse(_editingId!) ?? -1;
      if (id > 0) {
        try {
          final res = await http.put(
            Uri.parse("$serverBaseUrl/messages/$id"),
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer ${widget.token}"
            },
            body: jsonEncode({"text": text}),
          );
          if (res.statusCode == 200) {
            _editingId = null;
            _ctrl.clear();
            await _loadMessages();
            return;
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка редактирования: ${res.statusCode}')));
          }
        } catch (e) {
          debugPrint("Edit error: $e");
        }
      }
      return;
    }

    try {
      final res = await http.post(
        Uri.parse("$serverBaseUrl/messages"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.token}"
        },
        body: jsonEncode({"text": text}),
      );
      if (res.statusCode == 201 || res.statusCode == 200) {
        _ctrl.clear();
        await _loadMessages();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients && !_userScrolledUp) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка отправки: ${res.statusCode}')));
      }
    } catch (e) {
      debugPrint("Send error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка сети при отправке')));
    }
  }

  Future<void> _pickAndSendFile() async {
    // запросим разрешение на чтение/запись (Android)
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет разрешения на доступ к памяти')));
      return;
    }

    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;
    final filePath = result.files.single.path!;
    final fileName = result.files.single.name;

    setState(() => _uploading = true);
    try {
      final formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(filePath, filename: fileName),
        "text": fileName,
        "user": widget.username,
      });

      await _dio.post(
        "$serverBaseUrl/messages",
        data: formData,
        options: Options(headers: {"Authorization": "Bearer ${widget.token}"}),
        onSendProgress: (sent, total) {
          final percent = total > 0 ? (sent / total * 100).toStringAsFixed(0) : "0";
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Загрузка $percent%')));
        },
      );

      await _loadMessages();
    } catch (e) {
      debugPrint("File upload error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка загрузки файла')));
    } finally {
      setState(() => _uploading = false);
    }
  }

  Future<void> _downloadFile(String filename) async {
    // запрос разрешения
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет разрешения на запись')));
      return;
    }

    final dir = await getExternalStorageDirectory();
    final savePath = "${dir!.path}/$filename";
    try {
      await _dio.download(
        "$serverBaseUrl/files/$filename",
        savePath,
        onReceiveProgress: (r, t) {
          if (t > 0) {
            final p = (r / t * 100).toStringAsFixed(0);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скачивание $p%')));
          }
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Сохранено: $savePath')));
    } catch (e) {
      debugPrint("Download error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка скачивания')));
    }
  }

  void _onMessageLongPress(Map msg) {
    final mine = msg['user'] == widget.username;
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text("Копировать"),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg['text'] ?? ''));
                  Navigator.pop(context);
                },
              ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text("Изменить"),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _editingId = msg['id'].toString();
                      _ctrl.text = msg['text'] ?? '';
                    });
                  },
                ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.delete),
                  title: const Text("Удалить"),
                  onTap: () async {
                    Navigator.pop(context);
                    final id = msg['id'];
                    try {
                      final res = await http.delete(
                        Uri.parse("$serverBaseUrl/messages/$id"),
                        headers: {"Authorization": "Bearer ${widget.token}"},
                      );
                      if (res.statusCode == 200) {
                        await _loadMessages();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка удаления: ${res.statusCode}')));
                      }
                    } catch (e) {
                      debugPrint("Delete error: $e");
                    }
                  },
                ),
              if ((msg['attachment'] ?? '').isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text("Скачать файл"),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadFile(msg['attachment']);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('username');
    await prefs.setBool('notify_enabled', false);
    if (mounted) {
      Navigator.pushReplacement(context, const AuthPage());
    }
  }

  Future<void> _toggleNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifEnabled = !_notifEnabled;
      prefs.setBool('notify_enabled', _notifEnabled);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_notifEnabled ? "Уведомления включены" : "Уведомления выключены")));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _scrollCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  // Lifecycle для уведомлений: помечаем foreground/background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
  }

  Widget _buildMessageTile(Map m) {
    final bool mine = m['user'] == widget.username;
    final bool deleted = m['deleted'] == true;
    final att = m['attachment'];
    final timeText = m['time'] != null ? DateFormat('HH:mm').format(DateTime.tryParse(m['time']) ?? DateTime.now()) : "";

    return GestureDetector(
      onLongPress: () => _onMessageLongPress(m),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: deleted ? Colors.grey[300] : (mine ? Colors.teal[400] : Colors.white),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(2, 3))],
          ),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(m['user'] ?? "Anon", style: TextStyle(fontWeight: FontWeight.bold, color: mine ? Colors.white : Colors.teal)),
              const SizedBox(height: 6),
              if (deleted)
                const Text("[удалено]", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.red))
              else ...[
                Text(m['text'] ?? "", style: TextStyle(color: mine ? Colors.white : Colors.black)),
                if (att != null && (att as String).isNotEmpty)
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(timeText, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                  if (m['edited'] == true) const Padding(padding: EdgeInsets.only(left: 6), child: Text('изменено', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.black45))),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  // UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Chat — ${widget.username}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_emotions_outlined),
            onPressed: _toggleNotifications,
            tooltip: _notifEnabled ? "Уведомления: ВКЛ" : "Уведомления: ВЫКЛ",
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') _logout();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'logout', child: Text('Выйти')),
            ],
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (sn) {
                // фикс: если пользователь начал прокручивать — устанавливаем флаг
                if (sn is UserScrollNotification) {
                  _userScrolledUp = _scrollCtrl.position.pixels < (_scrollCtrl.position.maxScrollExtent - 150);
                }
                return false;
              },
              child: ListView.builder(
                controller: _scrollCtrl,
                itemCount: messages.length,
                itemBuilder: (_, i) => _buildMessageTile(messages[i]),
              ),
            ),
          ),
          if (_uploading) const LinearProgressIndicator(),
          SafeArea(
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.attach_file), onPressed: _pickAndSendFile),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: InputDecoration(
                      hintText: _editingId != null ? "Редактируете сообщение..." : "Сообщение...",
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
