import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FlappyGame(),
    );
  }
}

class FlappyGame extends StatefulWidget {
  const FlappyGame({super.key});
  @override
  State<FlappyGame> createState() => _FlappyGameState();
}

class _FlappyGameState extends State<FlappyGame> {
  double birdY = 0; // Позиция птички по Y (-1 до 1)
  double velocity = 0; // скорость
  double gravity = -4.5; // сила падения
  double boost = 8; // сила прыжка (будет накапливаться)
  double currentBoost = 0;

  bool holding = false;
  Timer? gameTimer;
  Timer? boostTimer;

  // трубы
  List<double> pipesX = [2, 4];
  double gapSize = 0.4; // размер дырки между трубами
  Random rng = Random();
  List<double> pipeHeights = [0.6, 0.5];

  bool gameOver = false;

  void startGame() {
    gameOver = false;
    birdY = 0;
    velocity = 0;
    pipesX = [2, 4];
    pipeHeights = [0.6, 0.5];

    gameTimer?.cancel();
    gameTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      setState(() {
        // физика птички
        birdY -= velocity * 0.02;
        velocity += gravity * 0.02;

        // движение труб
        for (int i = 0; i < pipesX.length; i++) {
          pipesX[i] -= 0.02;
          if (pipesX[i] < -1.5) {
            pipesX[i] += 3;
            pipeHeights[i] = 0.3 + rng.nextDouble() * 0.4;
          }
        }

        // проверка на столкновение
        for (int i = 0; i < pipesX.length; i++) {
          if (pipesX[i] < 0.2 && pipesX[i] > -0.2) {
            if (birdY > pipeHeights[i] || birdY < pipeHeights[i] - gapSize) {
              endGame();
            }
          }
        }

        // если упал или улетел
        if (birdY < -1 || birdY > 1) {
          endGame();
        }
      });
    });
  }

  void endGame() {
    gameTimer?.cancel();
    boostTimer?.cancel();
    gameOver = true;
    setState(() {});
  }

  void onTapDown() {
    holding = true;
    currentBoost = 0;
    boostTimer?.cancel();
    boostTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (holding) {
        setState(() {
          currentBoost = (currentBoost + 0.5).clamp(0, boost);
        });
      }
    });
  }

  void onTapUp() {
    holding = false;
    velocity = currentBoost;
    currentBoost = 0;
    boostTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (gameOver) {
          startGame();
        } else {
          onTapDown();
        }
      },
      onTapUp: (_) {
        if (!gameOver) onTapUp();
      },
      child: Scaffold(
        backgroundColor: Colors.lightBlue,
        body: Stack(
          children: [
            // птичка
            Align(
              alignment: Alignment(0, birdY),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.yellow,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // трубы
            for (int i = 0; i < pipesX.length; i++) ...[
              Align(
                alignment: Alignment(pipesX[i], pipeHeights[i] + gapSize),
                child: Container(
                  width: 60,
                  height: 1,
                  color: Colors.green,
                ),
              ),
              Align(
                alignment: Alignment(pipesX[i], pipeHeights[i] - 1 - gapSize),
                child: Container(
                  width: 60,
                  height: 1,
                  color: Colors.green,
                ),
              ),
            ],
            // сообщение
            if (gameOver)
              const Center(
                child: Text(
                  "Tap to Restart",
                  style: TextStyle(fontSize: 32, color: Colors.white),
                ),
              )
          ],
        ),
      ),
    );
  }
}
