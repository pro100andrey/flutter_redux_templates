import 'package:flutter/material.dart';
import 'package:localization/export.dart';

@immutable
class ___PageName___PageVm {
  const ___PageName___PageVm({
    required this.isWaiting,
  });
  final bool isWaiting;
}

class ___PageName___Page extends StatelessWidget {
  const ___PageName___Page({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final ___PageName___PageVm vm;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(S.current.title),
        ),
        body: Stack(
          children: const [
            Center(
              child: Text('___PageName___Page'),
            ),
          ],
        ),
      );
}
