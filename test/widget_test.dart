import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_voice_recorder/main.dart'; // правильное имя пакета

void main() {
  testWidgets('App loads and displays title', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Dictaphone — Voice Recorder'), findsOneWidget);
  });
}
