import 'dart:ui';

import 'package:flutter/material.dart';

class BarrierOverlay extends StatelessWidget {
  const BarrierOverlay({
    super.key,
  });

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const ModalBarrier(dismissible: false),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          )
        ],
      );
}
