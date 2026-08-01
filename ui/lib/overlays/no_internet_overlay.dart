import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import '../theme/spacing.dart';

class NoInternetOverlay extends StatelessWidget {
  const NoInternetOverlay({super.key});

  @override
  Widget build(BuildContext context) => Material(
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            S.current.couldNotConnectToInternet,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          Gaps.md,
          Text(
            S.current.pleaseCheckYourNetworkSettings,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
