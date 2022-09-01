import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

class ___PageName___Page extends StatelessWidget {
  const ___PageName___Page({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(S.current.title),
        ),
        body: Stack(
          children: const [
            Center(
              child: Text('___PageName___Page Coming soon...'),
            ),
          ],
        ),
      );
}
