// ArinaDesk quick system check - dialog (Flutter UI).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'system_check_core.dart';

const int _kRendezvousPort = 21116;

String _hostOf(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  final uri = Uri.tryParse(s.contains('://') ? s : 'x://$s');
  return uri == null ? '' : uri.host;
}

int _portOf(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return _kRendezvousPort;
  final uri = Uri.tryParse(s.contains('://') ? s : 'x://$s');
  if (uri == null || !uri.hasPort || uri.port <= 0) return _kRendezvousPort;
  return uri.port;
}

/// Finds the support server this client talks to, at run time, so no
/// company specific address has to live in the (public) source code.
Future<List<Object>> _serverTarget() async {
  try {
    final custom = bind.mainGetOptionSync(key: 'custom-rendezvous-server');
    final customHost = _hostOf(custom);
    if (customHost.isNotEmpty) {
      return [customHost, _portOf(custom)];
    }
  } catch (_) {}
  try {
    // rdgen puts the server address into the API server setting as well.
    final api = await bind.mainGetApiServer();
    final apiHost = _hostOf(api);
    if (apiHost.isNotEmpty && !apiHost.endsWith('rustdesk.com')) {
      return [apiHost, _kRendezvousPort];
    }
  } catch (_) {}
  return ['', _kRendezvousPort];
}

Future<void> showArinaSystemCheck(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const _ArinaCheckDialog(),
  );
}

class _ArinaCheckDialog extends StatefulWidget {
  const _ArinaCheckDialog({Key? key}) : super(key: key);

  @override
  State<_ArinaCheckDialog> createState() => _ArinaCheckDialogState();
}

class _ArinaCheckDialogState extends State<_ArinaCheckDialog> {
  String? _report;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    String text;
    try {
      final target = await _serverTarget();
      text = await buildArinaReport(
        serverHost: target[0] as String,
        serverPort: target[1] as int,
      );
    } catch (e) {
      text = 'System check failed: $e';
    }
    if (!mounted) return;
    setState(() {
      _report = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return AlertDialog(
      title: const Text('بررسی سریع سیستم'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 380, maxWidth: 520),
        child: report == null
            ? const Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('در حال بررسی...'),
                ],
              )
            : SingleChildScrollView(
                child: SelectableText(
                  report,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontFamilyFallback: ['Courier New'],
                    fontSize: 12,
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: report == null
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: report));
                  showToast('گزارش کپی شد. آن را در تیکت جای‌گذاری کنید.');
                },
          child: const Text('کپی گزارش'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('بستن'),
        ),
      ],
    );
  }
}
