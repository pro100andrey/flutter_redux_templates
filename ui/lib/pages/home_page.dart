import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    required this.isWaiting,
    super.key,
  });

  final bool isWaiting;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(S.current.title),
        ),
        body: Stack(
          children: const [
            Center(
              child: Text('HomePage'),
            ),
          ],
        ),
      );
}
