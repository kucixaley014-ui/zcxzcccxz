import 'package:flutter/material.dart';
import 'dart:math';

void main() {
  runApp(const TicTacToeApp());
}

class TicTacToeApp extends StatelessWidget {
  const TicTacToeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Крестики-нолики',
      debugShowCheckedModeBanner: false,
      home: TicTacToeGame(),
    );
  }
}

class TicTacToeGame extends StatefulWidget {
  @override
  _TicTacToeGameState createState() => _TicTacToeGameState();
}

class _TicTacToeGameState extends State<TicTacToeGame> {
  List<String> board = List.filled(9, '');
  bool gameOver = false;
  String message = '';

  final Random _random = Random();

  void resetGame() {
    setState(() {
      board = List.filled(9, '');
      gameOver = false;
      message = '';
    });
  }

  void playerMove(int index) {
    if (board[index] == '' && !gameOver) {
      setState(() {
        board[index] = 'X';
      });
      checkWinner();
      if (!gameOver) {
        botMove();
      }
    }
  }

  void botMove() {
    List<int> emptyCells = [];
    for (int i = 0; i < 9; i++) {
      if (board[i] == '') emptyCells.add(i);
    }
    if (emptyCells.isNotEmpty) {
      int move = emptyCells[_random.nextInt(emptyCells.length)];
      setState(() {
        board[move] = 'O';
      });
      checkWinner();
    }
  }

  void checkWinner() {
    List<List<int>> winPatterns = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];

    for (var pattern in winPatterns) {
      String a = board[pattern[0]];
      String b = board[pattern[1]];
      String c = board[pattern[2]];
      if (a != '' && a == b && b == c) {
        setState(() {
          gameOver = true;
          message = (a == 'X') ? 'Ты выиграл! 🎉' : 'Ты проиграл! 😔';
        });
        return;
      }
    }

    if (!board.contains('')) {
      setState(() {
        gameOver = true;
        message = 'Ничья 🤝';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Крестики-нолики')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GridView.builder(
            shrinkWrap: true,
            itemCount: 9,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
            ),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => playerMove(index),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black),
                    color: Colors.grey[200],
                  ),
                  child: Center(
                    child: Text(
                      board[index],
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          if (gameOver)
            Column(
              children: [
                Text(
                  message,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: resetGame,
                  child: const Text("Играть снова"),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
