import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ConnectionStatusDot extends StatelessWidget {
  final bool connected;
  const ConnectionStatusDot({super.key, required this.connected});

  @override
  Widget build(BuildContext context) {
    return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: connected ? Colors.greenAccent : Colors.redAccent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (connected ? Colors.greenAccent : Colors.redAccent)
                    .withOpacity(0.5),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
        )
        .animate(
          onPlay: (c) {
            if (connected) {
              c.repeat(reverse: true);
            } else {
              c.reset();
              c.stop();
            }
          },
        )
        .scale(
          begin: const Offset(1.0, 1.0),
          end: const Offset(1.2, 1.2),
          duration: 600.ms,
        );
  }
}
