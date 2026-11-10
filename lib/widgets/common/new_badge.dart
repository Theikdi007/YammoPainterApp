import 'package:flutter/material.dart';

/// A small "NEW" label positioned at the top-right of a card.
/// Place it as a child of a [Stack].
class NewBadge extends StatelessWidget {
  const NewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 8,
      top: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'NEW',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
