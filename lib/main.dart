import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';

void main() => runApp(const FlappyApp());

class FlappyApp extends StatelessWidget {
  const FlappyApp({super.key});

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
  double birdY = 0;
  double velocity = 0;
  double gravity = -4.9;
  double jumpForce = 2.5;
  Timer? gameLoop;
  List<double> barrierX = [1, 2.5];
  List<double> barrierGap = [0.3, 0.4];
  Random rand = Random();
  int score = 0;
  bool isPlaying = false;

  void startGame() {
    isPlaying = true;
    birdY = 0;
    velocity = 0;
    barrierX = [1, 2.5];
    score = 0;

    gameLoop = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      setState(() {
        velocity += gravity * 0.03;
        birdY -= velocity * 0.03;

        for (int i = 0; i < barrierX.length; i++) {
          barrierX[i] -= 0.02;
          if (barrierX[i] < -1.2) {
            barrierX[i] += 3;
            barrierGap[i] = 0.2 + rand.nextDouble() * 0.5;
            score++;
          }
        }

        if (birdY < -1 || birdY > 1) {
          endGame();
        }

        for (int i = 0; i < barrierX.length; i++) {
          if (barrierX[i] < 0.1 && barrierX[i] > -0.1) {
            if (birdY > barrierGap[i] || birdY < barrierGap[i] - 0.4) {
              endGame();
            }
          }
        }
      });
    });
  }

  void jump() {
    if (!isPlaying) {
      startGame();
    }
    setState(() {
      velocity = jumpForce;
    });
  }

  void endGame() {
    gameLoop?.cancel();
    isPlaying = false;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Game Over"),
        content: Text("Your score: $score"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              startGame();
            },
            child: const Text("Restart"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: jump,
      child: Scaffold(
        backgroundColor: Colors.lightBlue,
        body: Stack(
          children: [
            AnimatedContainer(
              alignment: Alignment(0, birdY),
              duration: const Duration(milliseconds: 0),
              child: Container(width: 40, height: 40, color: Colors.yellow),
            ),
            for (int i = 0; i < barrierX.length; i++) ...[
              AnimatedContainer(
                alignment: Alignment(barrierX[i], barrierGap[i] + 1.2),
                duration: const Duration(milliseconds: 0),
                child: Container(width: 60, height: 400, color: Colors.green),
              ),
              AnimatedContainer(
                alignment: Alignment(barrierX[i], barrierGap[i] - 1.2),
                duration: const Duration(milliseconds: 0),
                child: Container(width: 60, height: 400, color: Colors.green),
              ),
            ],
            Positioned(
              top: 50,
              left: 20,
              child: Text(
                "Score: $score",
                style: const TextStyle(fontSize: 24, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
