import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

class NoInternetOverlay extends StatelessWidget {
  const NoInternetOverlay({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Material(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                S.current.couldNotConnectToInternet,
                style: Theme.of(context).textTheme.headline6,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                S.current.pleaseCheckYorNetworkSettings,
                style: Theme.of(context).textTheme.bodyText1,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
