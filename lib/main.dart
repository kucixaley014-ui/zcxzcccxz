import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dictaphone — Voice Recorder',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const RecorderPage(),
    );
  }
}

class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  final Record _recorder = Record();
  bool _isRecording = false;
  String? _currentPath;
  List<FileSystemEntity> _recordings = [];
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<Directory> _getStorageDirectory() async {
    if (Platform.isAndroid) {
      return await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    }
    return await getApplicationDocumentsDirectory();
  }

  Future<void> _loadRecordings() async {
    final dir = await _getStorageDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}recordings');
    if (!await folder.exists()) await folder.create(recursive: true);
    final files = folder
        .listSync()
        .where((f) => f.path.endsWith('.m4a') || f.path.endsWith('.wav') || f.path.endsWith('.aac'))
        .toList();
    setState(() => _recordings = files);
  }

  Future<bool> _requestPermissions() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) return false;

    if (Platform.isAndroid) {
      final storageStatus = await Permission.storage.request();
      if (!storageStatus.isGranted) {
        // proceed: app documents dir still accessible on many devices
      }
    }

    return true;
  }

  Future<void> _startRecording() async {
    final ok = await _requestPermissions();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission is required')));
      return;
    }

    final dir = await _getStorageDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}recordings');
    if (!await folder.exists()) await folder.create(recursive: true);

    final fileName = 'rec_${DateTime.now().toIso8601String().replaceAll(':', '-')}.m4a';
    final path = '${folder.path}${Platform.pathSeparator}$fileName';

    try {
      await _recorder.start(
        path: path,
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        samplingRate: 44100,
      );

      setState(() {
        _isRecording = true;
        _currentPath = path;
        _elapsedSeconds = 0;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsedSeconds++);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка старта записи: $e')));
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _recorder.stop();
    } catch (e) {}
    _timer?.cancel();
    setState(() {
      _isRecording = false;
      _elapsedSeconds = 0;
    });
    await _loadRecordings();
  }

  Future<void> _deleteRecording(FileSystemEntity file) async {
    try {
      await File(file.path).delete();
      await _loadRecordings();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка при удалении: $e')));
    }
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dictaphone — Запись голоса'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Text(_isRecording ? 'Запись...' : 'Готов к записи', style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 8),
                    Text(_isRecording ? _formatDuration(_elapsedSeconds) : '00:00', style: const TextStyle(fontSize: 32)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                          label: Text(_isRecording ? 'Остановить' : 'Запись'),
                          onPressed: _isRecording ? _stopRecording : _startRecording,
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Обновить список'),
                          onPressed: _loadRecordings,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Text('Записи', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: _recordings.isEmpty
                  ? const Center(child: Text('Пока нет записей'))
                  : ListView.builder(
                      itemCount: _recordings.length,
                      itemBuilder: (context, index) {
                        final f = _recordings[index];
                        final name = f.path.split(Platform.pathSeparator).last;
                        return ListTile(
                          title: Text(name),
                          subtitle: Text(f.path),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                onPressed: () async {
                                  // For in-app playback add just_audio; here show path
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Файл: ${f.path}')));
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => _deleteRecording(f),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
