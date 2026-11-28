// ArinaDesk support request UI: settings, new request, open the portal.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:url_launcher/url_launcher.dart';

import 'arina_config.dart';
import 'arina_ui_common.dart';
import 'support_api.dart';
import 'support_store.dart';
import 'ticket_store.dart';
import 'ticket_ui.dart';

export 'ticket_ui.dart' show ArinaTicketStatus;

String _appName() {
  try {
    return bind.mainGetAppNameSync();
  } catch (_) {
    return 'ArinaDesk';
  }
}

Future<ArinaSupportSettings> _load() =>
    loadArinaSettings(appName: _appName(), defaultUrl: kArinaZammadUrl);

Future<void> _openUrl(String url) async {
  try {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok) showToast('باز کردن مرورگر ممکن نشد.');
  } catch (_) {
    showToast('باز کردن مرورگر ممکن نشد.');
  }
}

/// "Support portal / track tickets" button: opens the helpdesk site.
Future<void> openArinaSupportPortal(BuildContext context) async {
  final s = await _load();
  final url = arinaNormalizeUrl(s.url);
  if (url.isEmpty) {
    showToast('آدرس سامانه‌ی پشتیبانی تنظیم نشده است.');
    return;
  }
  await _openUrl(url);
}

/// Credentials dialog. Returns true when settings were saved.
Future<bool> showArinaSupportSettings(BuildContext context) async {
  final saved = await arinaShowDialog<bool>(
    context,
    (ctx) => const _SettingsDialog(),
  );
  return saved == true;
}

/// "Request support" button: asks for credentials the first time, then shows
/// the title / description form and creates the ticket.
Future<void> showArinaSupportRequest(
    BuildContext context, String deviceId) async {
  var s = await _load();
  if (!context.mounted) return;
  if (!s.hasCredentials) {
    final saved = await showArinaSupportSettings(context);
    if (!saved) return;
    s = await _load();
    if (!s.hasCredentials) return;
  }
  if (!context.mounted) return;
  final settings = s;
  await arinaShowDialog<void>(
    context,
    (ctx) => _RequestDialog(settings: settings, deviceId: deviceId),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({Key? key}) : super(key: key);

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loaded = false;
  bool _busy = false;
  String? _message;
  bool _messageOk = false;
  ArinaSupportSettings _orig = const ArinaSupportSettings();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await _load();
    if (!mounted) return;
    setState(() {
      _orig = s;
      _url.text = s.url;
      _user.text = s.user;
      _pass.text = s.password;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  ArinaSupportSettings _current() => ArinaSupportSettings(
        url: _url.text.trim(),
        user: _user.text.trim(),
        password: _pass.text,
        requesterName: _orig.requesterName,
        phone: _orig.phone,
      );

  Future<void> _test() async {
    final s = _current();
    if (!s.hasCredentials) {
      setState(() {
        _message = 'آدرس، نام کاربری و رمز عبور را وارد کنید.';
        _messageOk = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final name = await arinaTestConnection(
          url: s.url, user: s.user, password: s.password);
      if (!mounted) return;
      setState(() {
        _message = 'اتصال موفق بود: $name';
        _messageOk = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.toString();
        _messageOk = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final s = _current();
    if (!s.hasCredentials) {
      setState(() {
        _message = 'آدرس، نام کاربری و رمز عبور را وارد کنید.';
        _messageOk = false;
      });
      return;
    }
    try {
      await saveArinaSettings(s, appName: _appName());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'ذخیره‌ی تنظیمات ممکن نشد.';
        _messageOk = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: arinaDialogInset,
      titlePadding: arinaTitlePadding,
      contentPadding: arinaContentPadding,
      title: const Text(
        'تنظیمات پشتیبانی',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: arinaDialogWidth(context),
        child: !_loaded
            ? const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'نام کاربری و رمز عبور سامانه‌ی پشتیبانی را یک بار وارد کنید.',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _url,
                      decoration:
                          const InputDecoration(labelText: 'آدرس سامانه'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _user,
                      decoration: const InputDecoration(
                          labelText: 'نام کاربری (ایمیل)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _pass,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'رمز عبور'),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _message!,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 13,
                          color: _messageOk ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _test,
          child: const Text('تست اتصال'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('انصراف'),
        ),
        ElevatedButton(
          onPressed: (_busy || !_loaded) ? null : _save,
          child: const Text('ذخیره'),
        ),
      ],
    );
  }
}

class _RequestDialog extends StatefulWidget {
  final ArinaSupportSettings settings;
  final String deviceId;
  const _RequestDialog(
      {Key? key, required this.settings, required this.deviceId})
      : super(key: key);

  @override
  State<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<_RequestDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  late ArinaSupportSettings _settings;
  bool _sending = false;
  String? _error;
  ArinaTicket? _ticket;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _name.text = _settings.requesterName;
    _phone.text = _settings.phone;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _deviceFooter() {
    var host = '';
    try {
      host = Platform.localHostname;
    } catch (_) {}
    return host.isEmpty ? '' : '--\nComputer: $host';
  }

  Future<void> _openSettings() async {
    final saved = await showArinaSupportSettings(context);
    if (!saved) return;
    final s = await _load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final text = _body.text.trim();
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    String? problem;
    if (kArinaFieldName.isNotEmpty && name.isEmpty) {
      problem = 'نام درخواست‌دهنده را بنویسید.';
    } else if (kArinaFieldPhone.isNotEmpty && phone.isEmpty) {
      problem = 'شماره‌ی تماس را بنویسید.';
    } else if (title.isEmpty) {
      problem = 'عنوان مشکل را بنویسید.';
    }
    if (problem != null) {
      setState(() {
        _error = problem;
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final footer = _deviceFooter();
      final body = footer.isEmpty
          ? (text.isEmpty ? title : text)
          : '${text.isEmpty ? title : text}\n\n$footer';
      final extra = <String, Object>{...kArinaZammadExtraFields};
      if (kArinaFieldName.isNotEmpty) extra[kArinaFieldName] = name;
      if (kArinaFieldPhone.isNotEmpty) extra[kArinaFieldPhone] = phone;
      final plainId = widget.deviceId.replaceAll(RegExp(r'\s+'), '');
      if (kArinaFieldDeviceId.isNotEmpty && plainId.isNotEmpty) {
        extra[kArinaFieldDeviceId] = plainId;
      }
      final t = await arinaCreateTicket(
        url: _settings.url,
        user: _settings.user,
        password: _settings.password,
        group: kArinaZammadGroup,
        title: title,
        body: body,
        extra: extra,
      );
      // watch this ticket (status indicator + reply notification)
      try {
        await ArinaTicketWatcher.instance.onTicketCreated(ArinaTrackedTicket(
          id: t.id,
          number: t.number,
          title: title,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ));
      } catch (_) {}
      // remember name / phone for the next request on this computer
      try {
        final updated = ArinaSupportSettings(
          url: _settings.url,
          user: _settings.user,
          password: _settings.password,
          requesterName: name,
          phone: phone,
        );
        await saveArinaSettings(updated, appName: _appName());
        _settings = updated;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _ticket = t;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Widget _form() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kArinaFieldName.isNotEmpty) ...[
            TextField(
              controller: _name,
              enabled: !_sending,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(labelText: 'نام درخواست‌دهنده'),
            ),
            const SizedBox(height: 8),
          ],
          if (kArinaFieldPhone.isNotEmpty) ...[
            TextField(
              controller: _phone,
              enabled: !_sending,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'شماره‌ی تماس'),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _title,
            enabled: !_sending,
            maxLength: 120,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              labelText: 'عنوان مشکل',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            enabled: !_sending,
            minLines: 5,
            maxLines: 10,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              labelText: 'شرح مشکل',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'شناسه و نام این کامپیوتر خودکار همراه درخواست ارسال می‌شود.',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 11),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textDirection: TextDirection.rtl,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _success(ArinaTicket t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 44),
        const SizedBox(height: 12),
        const Text(
          'درخواست شما ثبت شد.',
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 6),
        Text(
          'شماره‌ی تیکت: #${t.number}',
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    return AlertDialog(
      insetPadding: arinaDialogInset,
      titlePadding: arinaTitlePadding,
      contentPadding: arinaContentPadding,
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'درخواست پشتیبانی',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          if (t == null)
            IconButton(
              tooltip: 'تنظیمات حساب',
              icon: const Icon(Icons.settings, size: 20),
              onPressed: _sending ? null : _openSettings,
            ),
        ],
      ),
      content: SizedBox(
        width: arinaDialogWidth(context),
        child: t == null ? _form() : _success(t),
      ),
      actions: t == null
          ? [
              TextButton(
                onPressed: _sending ? null : () => Navigator.of(context).pop(),
                child: const Text('انصراف'),
              ),
              ElevatedButton(
                onPressed: _sending ? null : _submit,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('ثبت درخواست'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('بستن'),
              ),
              ElevatedButton(
                onPressed: () => _openUrl(arinaTicketUrl(_settings.url, t.id)),
                child: const Text('مشاهده و پیگیری تیکت'),
              ),
            ],
    );
  }
}
