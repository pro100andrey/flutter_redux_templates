import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({
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
              child: Text('ProfilePage'),
            ),
          ],
        ),
      );
}
