import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: IpChecker(),
    );
  }
}

class IpChecker extends StatefulWidget {
  const IpChecker({super.key});

  @override
  State<IpChecker> createState() => _IpCheckerState();
}

class _IpCheckerState extends State<IpChecker> {
  String? _ip;
  String? _error;

  Future<void> _fetchIp() async {
    try {
      final response = await http.get(Uri.parse("https://api.ipify.org?format=json"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _ip = data["ip"];
          _error = null;
        });
      } else {
        setState(() {
          _error = "Ошибка: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        _error = "Ошибка сети: $e";
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchIp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("IP Checker")),
      body: Center(
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.red))
            : _ip != null
                ? Text("Твой IP: $_ip", style: const TextStyle(fontSize: 22))
                : const CircularProgressIndicator(),
      ),
    );
  }
}
