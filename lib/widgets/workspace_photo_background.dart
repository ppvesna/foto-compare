import 'package:flutter/material.dart';

class WorkspacePhotoBackground extends StatelessWidget {
  const WorkspacePhotoBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/start-hero-prism-lab.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xD90B111D),
                  Color(0x8A111827),
                  Color(0x52111827),
                ],
                stops: [0.0, 0.52, 1.0],
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.30, 0.06),
                radius: 1.18,
                colors: [
                  Color(0x00111827),
                  Color(0x55111827),
                  Color(0xB80B111D),
                ],
                stops: [0.0, 0.60, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
