import 'package:flutter/material.dart';

class AuthPageBackdrop extends StatelessWidget {
  final Widget child;

  const AuthPageBackdrop({super.key, required this.child});

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
                  Color(0xF20B111D),
                  Color(0xC6111827),
                  Color(0x66111827),
                ],
                stops: [0, 0.48, 1],
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.30, 0.08),
                radius: 1.18,
                colors: [
                  Color(0x00111827),
                  Color(0x55111827),
                  Color(0xD90B111D),
                ],
                stops: [0, 0.60, 1],
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class AuthBrandMark extends StatelessWidget {
  final bool light;

  const AuthBrandMark({super.key, this.light = true});

  @override
  Widget build(BuildContext context) {
    final foreground = light ? Colors.white : const Color(0xFF0F172A);
    final background =
        light ? const Color(0x24FFFFFF) : const Color(0xFFEFF6FF);
    final border = light ? const Color(0x38FFFFFF) : const Color(0xFFBFDBFE);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF22D3EE), Color(0xFF8B5CF6)],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Photo Compare',
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
