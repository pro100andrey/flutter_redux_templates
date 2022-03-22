import 'package:flutter/material.dart';

SnackBar styledSnackbar({
  required BuildContext context,
  required String? title,
  required String message,
  required double maxWidth,
}) {
  final additional = MediaQuery.of(context).size.width - maxWidth;
  final inset = (additional > 0 ? additional / 2 : 32).toDouble();

  return SnackBar(
    elevation: 6,
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.fromLTRB(inset, 0, inset, 32),
    backgroundColor: Colors.blue[900],
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title,
            style: Theme.of(context).textTheme.headline6,
          ),
          const SizedBox(height: 22),
        ],
        Text(
          message,
          style: Theme.of(context).textTheme.bodyText1,
        ),
      ],
    ),
  );
}

void showStyledSnackbar({
  required BuildContext context,
  required String message,
  String? title,
  double maxWidth = 600,
}) =>
    ScaffoldMessenger.of(context).showSnackBar(
      styledSnackbar(
        context: context,
        title: title,
        message: message,
        maxWidth: maxWidth,
      ),
    );
