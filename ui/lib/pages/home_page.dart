import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:localization/localization.dart';

class HomePage extends StatelessWidget {
  const HomePage({required this.onPressedLogOut, super.key});

  /// Clears the session. Nothing is told to navigate: the auth guard re-runs on
  /// the token and brings the user back to the login screen itself.
  ///
  /// It replaces an `isWaiting` this page declared, never read, and was handed
  /// a literal `false` by a connector that subscribed to the whole store to
  /// compute it.
  final VoidCallback onPressedLogOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(S.current.appTitle),
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.log_out),
          tooltip: S.current.logOut,
          onPressed: onPressedLogOut,
        ),
      ],
    ),
    body: const Stack(children: [Center(child: Text('HomePage'))]),
  );
}
