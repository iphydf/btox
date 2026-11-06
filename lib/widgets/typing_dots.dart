import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

const _period = Duration(milliseconds: 1200);
const _dots = 3;

/// Screen readers read [label]. The dots stay still if the system
/// asks for reduced motion.
final class TypingDots extends HookWidget {
  final String label;
  final Color color;
  final double size;

  const TypingDots({
    super.key,
    required this.label,
    required this.color,
    this.size = 6,
  });

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final animation = useAnimationController(duration: _period);
    useEffect(() {
      if (still) {
        animation.stop();
      } else {
        animation.repeat();
      }
      return null;
    }, [still]);
    final t = useAnimation(animation);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: size / 2,
          children: [
            for (var i = 0; i < _dots; i++)
              Opacity(
                opacity: still ? 1 : _brightness(t, i),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Each dot peaks a third of a period after the one before.
double _brightness(double t, int dot) {
  final phase = (t - dot / _dots) % 1;
  return 0.3 + 0.7 * max(0, sin(phase * 2 * pi));
}
