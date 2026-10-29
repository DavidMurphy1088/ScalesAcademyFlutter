import 'package:flutter/material.dart';

/// Title bar with the app icon at the top left. The icon (and the bar) grow on wider screens:
/// phones ~40, small tablets / narrow windows ~56, iPads and wide windows ~72, very wide ~88.
PreferredSizeWidget saAppBar(BuildContext context, String title) {
  final width = MediaQuery.sizeOf(context).width;
  final double iconSize;
  if (width < 600) {
    iconSize = 40;
  } else if (width < 900) {
    iconSize = 56;
  } else if (width < 1300) {
    iconSize = 72;
  } else {
    iconSize = 88;
  }
  const padding = 8.0;
  return AppBar(
    toolbarHeight: iconSize + padding * 2,
    leadingWidth: iconSize + padding * 2,
    leading: _AppIcon(size: iconSize, padding: padding),
    title: Text(title),
  );
}

/// The app icon at the top left of the screen
class _AppIcon extends StatelessWidget {
  final double size;
  final double padding;

  const _AppIcon({required this.size, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        child: Image.asset('assets/images/app_icon.png', width: size, height: size, fit: BoxFit.contain),
      ),
    );
  }
}
