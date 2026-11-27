// Shared helpers for the ArinaDesk dialogs: Persian font and, for
// "incoming only" clients (a narrow window), a temporary wider window.
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:window_manager/window_manager.dart';

String arinaAppName() {
  try {
    return bind.mainGetAppNameSync();
  } catch (_) {
    return 'ArinaDesk';
  }
}

/// Bundled by the patch script (flutter/assets/fonts, pubspec.yaml).
const String kArinaFont = 'Vazirmatn';

/// Applies the Persian font to everything inside [child].
Widget arinaThemed(BuildContext context, Widget child) {
  final base = Theme.of(context);
  return Theme(
    data: base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: kArinaFont),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: kArinaFont),
    ),
    child: child,
  );
}

/// Content width that fits the current window (dialogs use a 12 px outer
/// margin and 20 px side padding, see [arinaDialogInset]/[arinaContentPadding]).
double arinaDialogWidth(BuildContext context, {double max = 460}) {
  final w = MediaQuery.of(context).size.width;
  return (w - 24 - 40).clamp(180.0, max).toDouble();
}

const EdgeInsets arinaDialogInset = EdgeInsets.all(12);
const EdgeInsets arinaTitlePadding = EdgeInsets.fromLTRB(20, 16, 12, 4);
const EdgeInsets arinaContentPadding = EdgeInsets.fromLTRB(20, 8, 20, 8);

int _dialogDepth = 0;

/// Like showDialog, but applies the font and, on an incoming-only client
/// (whose window is only ~280 px wide), widens the window while the dialog is
/// open and restores the size afterwards.
Future<T?> arinaShowDialog<T>(BuildContext context, WidgetBuilder builder) async {
  var resized = false;
  if (_dialogDepth == 0) {
    try {
      if (bind.isIncomingOnly()) {
        final home = getIncomingOnlyHomeSize();
        if (home.width < 480) {
          final h = home.height < 600 ? 600.0 : home.height;
          await windowManager.setSize(Size(520, h));
          resized = true;
        }
      }
    } catch (_) {}
  }
  _dialogDepth++;
  try {
    if (!context.mounted) return null;
    return await showDialog<T>(
      context: context,
      builder: (ctx) => arinaThemed(ctx, builder(ctx)),
    );
  } finally {
    _dialogDepth--;
    if (resized) {
      try {
        await windowManager.setSize(getIncomingOnlyHomeSize());
      } catch (_) {}
    }
  }
}
