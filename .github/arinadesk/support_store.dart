// ArinaDesk support settings: stored as a small JSON file in the user's
// profile (APPDATA). NOTE: the password is stored as plain text there.
import 'dart:convert';
import 'dart:io';

class ArinaSupportSettings {
  final String url;
  final String user;
  final String password;

  /// Last requester name / phone typed in the request form (prefilled next time).
  final String requesterName;
  final String phone;
  const ArinaSupportSettings({
    this.url = '',
    this.user = '',
    this.password = '',
    this.requesterName = '',
    this.phone = '',
  });

  bool get hasCredentials =>
      url.trim().isNotEmpty && user.trim().isNotEmpty && password.isNotEmpty;
}

String _safeName(String s) {
  final r = s.replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), '').trim();
  return r.isEmpty ? 'ArinaDesk' : r;
}

File _file(String appName, String? baseDir) {
  final base = baseDir ??
      Platform.environment['APPDATA'] ??
      Platform.environment['HOME'] ??
      Directory.systemTemp.path;
  final sep = Platform.pathSeparator;
  return File('$base$sep${_safeName(appName)}${sep}arina_support.json');
}

Future<ArinaSupportSettings> loadArinaSettings({
  required String appName,
  required String defaultUrl,
  String? baseDir,
}) async {
  try {
    final f = _file(appName, baseDir);
    if (await f.exists()) {
      final j = jsonDecode(await f.readAsString());
      if (j is Map) {
        final url = (j['url'] ?? '').toString();
        return ArinaSupportSettings(
          url: url.isEmpty ? defaultUrl : url,
          user: (j['user'] ?? '').toString(),
          password: (j['password'] ?? '').toString(),
          requesterName: (j['requester_name'] ?? '').toString(),
          phone: (j['phone'] ?? '').toString(),
        );
      }
    }
  } catch (_) {}
  return ArinaSupportSettings(url: defaultUrl);
}

Future<void> saveArinaSettings(
  ArinaSupportSettings s, {
  required String appName,
  String? baseDir,
}) async {
  final f = _file(appName, baseDir);
  await f.parent.create(recursive: true);
  await f.writeAsString(
    jsonEncode({
      'url': s.url.trim(),
      'user': s.user.trim(),
      'password': s.password,
      'requester_name': s.requesterName.trim(),
      'phone': s.phone.trim(),
    }),
    flush: true,
  );
}
