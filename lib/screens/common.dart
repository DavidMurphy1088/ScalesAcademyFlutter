import 'package:flutter/material.dart';

import '../log/test_log.dart';

/// Title bar with the app icon at the top left and the test log buttons at the right (Log to console, Copy log,
/// Clear: see TestLog). The icon (and the bar) grow on wider screens:
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
    actions: const [_TestLogButtons(), SizedBox(width: 8)],
  );
}

/// The test log buttons in every screen's title bar
class _TestLogButtons extends StatelessWidget {
  const _TestLogButtons();

  void _tell(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final log = TestLog.instance;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.terminal),
            label: Text('Log to console (${log.length})'),
            onPressed: () {
              log.printToConsole();
              _tell(context, 'Test log written to the console (${log.length} lines)');
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy log'),
            onPressed: () async {
              await log.copyToClipboard();
              if (context.mounted) _tell(context, 'Test log copied (${log.length} lines) - paste it into an email');
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Clear'),
            onPressed: () {
              log.clear();
              _tell(context, 'Test log cleared');
            },
          ),
        ],
      ),
    );
  }
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
