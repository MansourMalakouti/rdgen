// ArinaDesk -> Zammad REST client (HTTP Basic auth). Pure Dart, no Flutter.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ArinaSupportException implements Exception {
  final String message;
  const ArinaSupportException(this.message);

  @override
  String toString() => message;
}

class ArinaTicket {
  final int id;
  final String number;
  const ArinaTicket(this.id, this.number);
}

/// "help.example.com/" -> "https://help.example.com"
String arinaNormalizeUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  if (!s.startsWith('http://') && !s.startsWith('https://')) {
    s = 'https://$s';
  }
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

String arinaTicketUrl(String baseUrl, int id) =>
    '${arinaNormalizeUrl(baseUrl)}/#ticket/zoom/$id';

String _serverDetail(String text) {
  try {
    final j = jsonDecode(text);
    if (j is Map) {
      final human = j['error_human'];
      final err = j['error'];
      if (human is String && human.isNotEmpty) return human;
      if (err is String && err.isNotEmpty) return err;
    }
  } catch (_) {}
  return '';
}

Future<dynamic> _request(
  String method,
  String baseUrl,
  String path,
  String user,
  String password, {
  Map<String, dynamic>? body,
}) async {
  final base = arinaNormalizeUrl(baseUrl);
  if (base.isEmpty) {
    throw const ArinaSupportException('آدرس سامانه‌ی پشتیبانی تنظیم نشده است.');
  }
  final Uri uri;
  try {
    uri = Uri.parse('$base$path');
  } catch (_) {
    throw const ArinaSupportException('آدرس سامانه‌ی پشتیبانی معتبر نیست.');
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req =
        await client.openUrl(method, uri).timeout(const Duration(seconds: 15));
    final cred = base64Encode(utf8.encode('$user:$password'));
    req.headers.set(HttpHeaders.authorizationHeader, 'Basic $cred');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      req.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      req.add(utf8.encode(jsonEncode(body)));
    }
    final resp = await req.close().timeout(const Duration(seconds: 20));
    final text = await resp
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 20));
    final code = resp.statusCode;
    if (code >= 200 && code < 300) {
      try {
        return jsonDecode(text);
      } catch (_) {
        throw const ArinaSupportException(
            'پاسخ نامعتبر از سامانه‌ی پشتیبانی دریافت شد.');
      }
    }
    final detail = _serverDetail(text);
    final suffix = detail.isEmpty ? '' : '\n($detail)';
    if (code == 401) {
      throw const ArinaSupportException(
          'نام کاربری یا رمز عبور اشتباه است.');
    }
    if (code == 403) {
      throw ArinaSupportException(
          'این حساب اجازه‌ی انجام این کار را ندارد.$suffix');
    }
    if (code == 404 || code == 422) {
      throw ArinaSupportException('درخواست پذیرفته نشد.$suffix');
    }
    throw ArinaSupportException('خطای سامانه‌ی پشتیبانی (کد $code).$suffix');
  } on ArinaSupportException {
    rethrow;
  } on TimeoutException {
    throw const ArinaSupportException(
        'پاسخی از سامانه‌ی پشتیبانی دریافت نشد (timeout).');
  } on HandshakeException {
    throw const ArinaSupportException(
        'برقراری ارتباط امن (SSL) با سامانه‌ی پشتیبانی ممکن نشد.');
  } on SocketException {
    throw const ArinaSupportException(
        'اتصال به سامانه‌ی پشتیبانی برقرار نشد. اینترنت و آدرس را بررسی کنید.');
  } on HttpException {
    throw const ArinaSupportException('خطا در ارتباط با سامانه‌ی پشتیبانی.');
  } finally {
    client.close(force: true);
  }
}

/// Checks the login. Returns the account display name.
Future<String> arinaTestConnection({
  required String url,
  required String user,
  required String password,
}) async {
  final j = await _request('GET', url, '/api/v1/users/me', user, password);
  if (j is Map) {
    final first = (j['firstname'] ?? '').toString().trim();
    final last = (j['lastname'] ?? '').toString().trim();
    final name = '$first $last'.trim();
    if (name.isNotEmpty) return name;
    final login = (j['login'] ?? j['email'] ?? '').toString();
    if (login.isNotEmpty) return login;
  }
  return user;
}

/// Creates a ticket as the logged-in (customer) account.
Future<ArinaTicket> arinaCreateTicket({
  required String url,
  required String user,
  required String password,
  required String group,
  required String title,
  required String body,
}) async {
  final j = await _request(
    'POST',
    url,
    '/api/v1/tickets',
    user,
    password,
    body: {
      'title': title,
      'group': group,
      'article': {
        'subject': title,
        'body': body,
        'type': 'web',
        'internal': false,
        'content_type': 'text/plain',
      },
    },
  );
  if (j is Map && j['id'] is int) {
    return ArinaTicket(j['id'] as int, (j['number'] ?? j['id']).toString());
  }
  throw const ArinaSupportException(
      'تیکت ثبت شد ولی شماره‌ی آن از سامانه دریافت نشد.');
}
