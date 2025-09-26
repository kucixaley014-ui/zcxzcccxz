import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const IpCheckerApp());
}

class IpCheckerApp extends StatelessWidget {
  const IpCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IP Checker',
      theme: ThemeData(
        primarySwatch: Colors.teal,
      ),
      home: const IpCheckerScreen(),
    );
  }
}

class IpCheckerScreen extends StatefulWidget {
  const IpCheckerScreen({super.key});

  @override
  State<IpCheckerScreen> createState() => _IpCheckerScreenState();
}

class _IpCheckerScreenState extends State<IpCheckerScreen> {
  String? publicIp;
  List<String> localIps = [];
  String status = 'Готово';
  bool loading = false;
  String? lastError;

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    setState(() {
      loading = true;
      status = 'Проверка...';
      lastError = null;
    });

    try {
      await Future.wait([_fetchPublicIp(), _fetchLocalIps()]);
      setState(() {
        status = 'Готово';
      });
    } catch (e) {
      setState(() {
        lastError = e.toString();
        status = 'Ошибка';
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _fetchPublicIp() async {
    // сервис ipify возвращает JSON: {"ip":"1.2.3.4"}
    final uri = Uri.parse('https://api.ipify.org?format=json');
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        setState(() {
          publicIp = data['ip']?.toString();
        });
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } on TimeoutException catch (_) {
      throw Exception('Таймаут при получении публичного IP');
    } on SocketException catch (_) {
      throw Exception('Нет сетевого соединения (SocketException)');
    } catch (e) {
      throw Exception('Ошибка получения публичного IP: $e');
    }
  }

  Future<void> _fetchLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: true,
      );
      final ips = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          // IPv4/IPv6
          ips.add('${iface.name}: ${addr.address}');
        }
      }
      if (ips.isEmpty) ips.add('Не удалось определить локальные адреса');
      setState(() => localIps = ips);
    } catch (e) {
      setState(() => localIps = ['Ошибка при получении локальных IP: $e']);
    }
  }

  Widget _buildCard(IconData icon, String title, Widget child) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: Colors.teal),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  child,
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final publicWidget = publicIp != null
        ? SelectableText(publicIp!, style: const TextStyle(fontSize: 18))
        : const Text('—');

    final localWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: localIps.map((s) => Text(s)).toList(),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('IP Checker — Проверка интернета')),
      body: RefreshIndicator(
        onRefresh: _checkAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Статус: $status',
                          style: const TextStyle(fontSize: 16)),
                    ),
                    if (loading) const SizedBox(width: 8),
                    if (loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _checkAll,
                    ),
                  ],
                ),
              ),
              _buildCard(Icons.public, 'Публичный IP (через api.ipify.org)', publicWidget),
              _buildCard(Icons.laptop_mac, 'Локальные IP интерфейсов', localWidget),
              _buildCard(Icons.info, 'Дополнительно', Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Последняя ошибка: ${lastError ?? "нет"}'),
                  const SizedBox(height: 6),
                  const Text('Потяните вниз для обновления или нажмите кнопку обновить.'),
                ],
              )),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _checkAll,
        icon: const Icon(Icons.network_check),
        label: const Text('Проверить'),
      ),
    );
  }
}
