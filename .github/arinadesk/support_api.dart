// ArinaDesk -> Zammad REST client (HTTP Basic auth). Pure Dart, no Flutter.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ArinaSupportException implements Exception {
  final String message;

  /// HTTP status code when the server answered with an error.
  final int? code;
  const ArinaSupportException(this.message, {this.code});

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
          'نام کاربری یا رمز عبور اشتباه است.',
          code: 401);
    }
    if (code == 403) {
      throw ArinaSupportException(
          'این حساب اجازه‌ی انجام این کار را ندارد.$suffix',
          code: 403);
    }
    if (code == 404 || code == 422) {
      throw ArinaSupportException('درخواست پذیرفته نشد.$suffix', code: code);
    }
    throw ArinaSupportException('خطای سامانه‌ی پشتیبانی (کد $code).$suffix',
        code: code);
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
  Map<String, Object> extra = const {},
}) async {
  final j = await _request(
    'POST',
    url,
    '/api/v1/tickets',
    user,
    password,
    body: {
      ...extra,
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

// ---------------------------------------------------------------------------
// Ticket status (for the "is my ticket answered?" indicator)
//
// NOTE: Zammad only fills `last_contact_agent_at` for communication-type
// replies (email/phone/web), not for notes, so the status is worked out from
// the public articles (messages) of the ticket instead.

const String kArinaStatusWaiting = 'waiting'; // no agent reply yet
const String kArinaStatusAnswered = 'answered'; // an agent replied
const String kArinaStatusClosed = 'closed';

class ArinaTicketInfo {
  final int id;
  final String number;
  final String title;
  final String state; // new / open / pending reminder / pending close / closed
  final String owner; // assigned agent ('' or '-' when nobody)
  final String group;
  final String priority;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const ArinaTicketInfo({
    required this.id,
    required this.number,
    required this.title,
    required this.state,
    this.owner = '',
    this.group = '',
    this.priority = '',
    this.createdAt,
    this.updatedAt,
  });
}

/// One message of a ticket.
class ArinaArticle {
  final int id;
  final String sender; // Agent / Customer / System
  final String type; // note / email / web / phone ...
  final bool internal; // hidden from customers
  final DateTime? createdAt;
  final String from;
  final String text; // plain text
  const ArinaArticle({
    required this.id,
    required this.sender,
    required this.type,
    required this.internal,
    required this.createdAt,
    required this.from,
    required this.text,
  });

  bool get isAgent => sender.toLowerCase() == 'agent';
  bool get isCustomer => sender.toLowerCase() == 'customer';
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

String _str(dynamic v) => (v ?? '').toString();

Future<ArinaTicketInfo> arinaGetTicket({
  required String url,
  required String user,
  required String password,
  required int id,
}) async {
  final j = await _request(
      'GET', url, '/api/v1/tickets/$id?expand=true', user, password);
  if (j is! Map) {
    throw const ArinaSupportException('پاسخ نامعتبر از سامانه‌ی پشتیبانی.');
  }
  return ArinaTicketInfo(
    id: id,
    number: (j['number'] ?? id).toString(),
    title: _str(j['title']),
    state: j['state'] is String ? j['state'] as String : '',
    owner: _str(j['owner']),
    group: _str(j['group']),
    priority: _str(j['priority']),
    createdAt: _date(j['created_at']),
    updatedAt: _date(j['updated_at']),
  );
}

/// Plain text of an HTML snippet (tags removed, entities decoded).
String arinaStripHtml(String html) {
  var s = html;
  s = s.replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>',
      caseSensitive: false, dotAll: true), '');
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'</(p|div|li|tr|h[1-6])>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAll(RegExp(r'\s*\n\s*'), '\n');
  return s.trim();
}

/// All messages of a ticket, oldest first (a customer only gets public ones).
Future<List<ArinaArticle>> arinaGetArticles({
  required String url,
  required String user,
  required String password,
  required int id,
}) async {
  final j = await _request('GET', url,
      '/api/v1/ticket_articles/by_ticket/$id?expand=true', user, password);
  final out = <ArinaArticle>[];
  if (j is! List) return out;
  for (final a in j) {
    if (a is! Map || a['id'] is! int) continue;
    var body = _str(a['body']);
    if (_str(a['content_type']).contains('html')) body = arinaStripHtml(body);
    out.add(ArinaArticle(
      id: a['id'] as int,
      sender: _str(a['sender']),
      type: _str(a['type']),
      internal: a['internal'] == true,
      createdAt: _date(a['created_at']),
      from: _str(a['from']),
      text: body.trim(),
    ));
  }
  out.sort((x, y) => x.id.compareTo(y.id));
  return out;
}

/// waiting / answered / closed. "Answered" = the newest public message between
/// the customer and the agents was written by an agent (notes included).
String arinaStatusOf(String state, List<ArinaArticle> articles) {
  final s = state.trim().toLowerCase();
  if (s == 'closed' || s == 'merged' || s == 'removed') {
    return kArinaStatusClosed;
  }
  for (final a in articles.reversed) {
    if (a.internal) continue;
    if (a.isAgent) return kArinaStatusAnswered;
    if (a.isCustomer) return kArinaStatusWaiting;
  }
  return kArinaStatusWaiting;
}

/// Id of the newest public agent message (0 if none).
int arinaLastAgentArticleId(List<ArinaArticle> articles) {
  var best = 0;
  for (final a in articles) {
    if (!a.internal && a.isAgent && a.id > best) best = a.id;
  }
  return best;
}

/// Short preview of the newest public agent message ('' if none).
String arinaAgentPreview(List<ArinaArticle> articles, {int maxChars = 280}) {
  for (final a in articles.reversed) {
    if (a.internal || !a.isAgent || a.text.isEmpty) continue;
    return a.text.length > maxChars
        ? '${a.text.substring(0, maxChars)}...'
        : a.text;
  }
  return '';
}
