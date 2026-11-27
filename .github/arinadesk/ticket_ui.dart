// ArinaDesk ticket watcher UI: status indicator on the home page, and the
// "new reply" notification (sound + window to front + dialog).
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:url_launcher/url_launcher.dart';

import 'arina_config.dart';
import 'arina_ui_common.dart';
import 'support_api.dart';
import 'support_store.dart';
import 'ticket_store.dart';
import 'ticket_watch.dart';

void _arinaBeep() {
  if (!Platform.isWindows) return;
  try {
    final lib = ffi.DynamicLibrary.open('user32.dll');
    final beep = lib.lookupFunction<ffi.Int32 Function(ffi.Uint32),
        int Function(int)>('MessageBeep');
    beep(0x40); // MB_ICONASTERISK: the user's "notification" sound
  } catch (_) {}
}

/// Sound + bring the main window to the front.
Future<void> arinaAlertUser() async {
  _arinaBeep();
  try {
    await windowOnTop(null);
  } catch (_) {}
}

Future<void> _open(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Remembers the tickets created from this computer and checks them every
/// few minutes. One instance for the whole app.
class ArinaTicketWatcher {
  ArinaTicketWatcher._();
  static final ArinaTicketWatcher instance = ArinaTicketWatcher._();

  /// Newest ticket created from this computer (null if none).
  final ValueNotifier<ArinaTrackedTicket?> latest = ValueNotifier(null);

  Timer? _timer;
  bool _busy = false;
  bool _draining = false;
  final List<(ArinaTicketEvent, String)> _queue = [];

  void start() {
    if (_timer != null) return;
    _reload();
    Future.delayed(const Duration(seconds: 15), _tick);
    _timer = Timer.periodic(
        const Duration(minutes: kArinaPollMinutes), (_) => _tick());
  }

  Future<void> _reload() async {
    final list = await loadArinaTickets(appName: arinaAppName());
    latest.value = list.isEmpty ? null : list.first;
  }

  /// Call right after a ticket was created from the request dialog.
  Future<void> onTicketCreated(ArinaTrackedTicket t) async {
    await addArinaTicket(t, appName: arinaAppName());
    await _reload();
  }

  Future<void> markSeen(int id) async {
    await markArinaTicketSeen(id, appName: arinaAppName());
    await _reload();
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    var events = <ArinaTicketEvent>[];
    var url = '';
    try {
      final settings = await loadArinaSettings(
          appName: arinaAppName(), defaultUrl: kArinaZammadUrl);
      if (settings.hasCredentials) {
        events = await arinaPollTickets(
            settings: settings, appName: arinaAppName());
        url = settings.url;
        await _reload();
      }
    } catch (_) {
      // never disturb the user because of a failed check
    } finally {
      _busy = false;
    }
    for (final e in events) {
      _queue.add((e, url));
    }
    unawaited(_drain());
  }

  /// Shows the notifications one after another (never stacked).
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final item = _queue.removeAt(0);
        await _notify(item.$1, item.$2);
      }
    } catch (_) {
    } finally {
      _draining = false;
    }
  }

  Future<void> _notify(ArinaTicketEvent e, String baseUrl) async {
    final ctx = globalKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await arinaAlertUser();
    if (!ctx.mounted) return;
    await arinaShowDialog<void>(
      ctx,
      (c) => _NoticeDialog(event: e, baseUrl: baseUrl),
    );
    await markSeen(e.ticket.id);
  }
}

class _NoticeDialog extends StatelessWidget {
  final ArinaTicketEvent event;
  final String baseUrl;
  const _NoticeDialog({Key? key, required this.event, required this.baseUrl})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final closed = event.kind == kArinaEventClosed;
    final t = event.ticket;
    return AlertDialog(
      insetPadding: arinaDialogInset,
      titlePadding: arinaTitlePadding,
      contentPadding: arinaContentPadding,
      title: Text(
        closed ? 'تیکت #${t.number} بسته شد' : 'پاسخ جدید برای تیکت #${t.number}',
        textDirection: TextDirection.rtl,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: arinaDialogWidth(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (t.title.isNotEmpty)
                Text(
                  t.title,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (closed) ...[
                const SizedBox(height: 8),
                const Text(
                  'این تیکت توسط کارشناس بسته شد.',
                  textDirection: TextDirection.rtl,
                ),
              ],
              if (event.preview.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'آخرین پاسخ کارشناس:',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  event.preview,
                  textDirection: TextDirection.rtl,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('بستن'),
        ),
        ElevatedButton(
          onPressed: () {
            _open(arinaTicketUrl(baseUrl, t.id));
            Navigator.of(context).pop();
          },
          child: const Text('مشاهده تیکت'),
        ),
      ],
    );
  }
}

/// Small status line on the home page for the newest ticket created from this
/// computer: waiting for an answer / answered by an agent / closed.
class ArinaTicketStatus extends StatefulWidget {
  const ArinaTicketStatus({Key? key}) : super(key: key);

  @override
  State<ArinaTicketStatus> createState() => _ArinaTicketStatusState();
}

class _ArinaTicketStatusState extends State<ArinaTicketStatus> {
  @override
  void initState() {
    super.initState();
    ArinaTicketWatcher.instance.start();
  }

  Future<void> _openTicket(ArinaTrackedTicket t) async {
    final s = await loadArinaSettings(
        appName: arinaAppName(), defaultUrl: kArinaZammadUrl);
    await _open(arinaTicketUrl(s.url, t.id));
    await ArinaTicketWatcher.instance.markSeen(t.id);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ArinaTrackedTicket?>(
      valueListenable: ArinaTicketWatcher.instance.latest,
      builder: (context, t, _) {
        if (t == null) return const SizedBox.shrink();
        final Color color;
        final String text;
        switch (t.status) {
          case kArinaStatusAnswered:
            color = Colors.green;
            text = 'پاسخ داده شد';
            break;
          case kArinaStatusClosed:
            color = Colors.grey;
            text = 'بسته شد';
            break;
          default:
            color = Colors.orange;
            text = 'در انتظار پاسخ کارشناس';
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => _openTicket(t),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: color.withOpacity(0.7)),
                borderRadius: BorderRadius.circular(6),
                color: color.withOpacity(t.unseen ? 0.18 : 0.07),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تیکت #${t.number}',
                          style: const TextStyle(
                              fontFamily: kArinaFont,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          text,
                          style: const TextStyle(
                              fontFamily: kArinaFont, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (t.unseen)
                    Text(
                      'جدید',
                      style: TextStyle(
                        fontFamily: kArinaFont,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
