import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

@immutable
class HomePageVm {
  const HomePageVm({
    required this.isWaiting,
  });
  final bool isWaiting;
}

class HomePage extends StatelessWidget {
  const HomePage({
    required this.vm,
    Key? key,
  }) : super(key: key);

  final HomePageVm vm;

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
