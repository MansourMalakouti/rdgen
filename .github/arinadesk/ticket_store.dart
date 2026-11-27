// Tickets created from this computer (so only they are watched / notified).
// Stored next to the support settings, newest first.
import 'dart:convert';
import 'dart:io';

import 'support_api.dart';
import 'support_store.dart';

const int _kMaxTracked = 15;

class ArinaTrackedTicket {
  final int id;
  final String number;
  final String title;
  final String status; // kArinaStatus*
  final String lastAgentAt; // ISO UTC of the last agent reply we know, or ''
  final bool unseen; // a reply / closing the user has not looked at yet
  final String createdAt;

  const ArinaTrackedTicket({
    required this.id,
    required this.number,
    required this.title,
    this.status = kArinaStatusWaiting,
    this.lastAgentAt = '',
    this.unseen = false,
    this.createdAt = '',
  });

  ArinaTrackedTicket copyWith({
    String? title,
    String? status,
    String? lastAgentAt,
    bool? unseen,
  }) =>
      ArinaTrackedTicket(
        id: id,
        number: number,
        title: title ?? this.title,
        status: status ?? this.status,
        lastAgentAt: lastAgentAt ?? this.lastAgentAt,
        unseen: unseen ?? this.unseen,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'title': title,
        'status': status,
        'last_agent_at': lastAgentAt,
        'unseen': unseen,
        'created_at': createdAt,
      };

  static ArinaTrackedTicket? fromJson(dynamic j) {
    if (j is! Map || j['id'] is! int) return null;
    return ArinaTrackedTicket(
      id: j['id'] as int,
      number: (j['number'] ?? j['id']).toString(),
      title: (j['title'] ?? '').toString(),
      status: (j['status'] ?? kArinaStatusWaiting).toString(),
      lastAgentAt: (j['last_agent_at'] ?? '').toString(),
      unseen: j['unseen'] == true,
      createdAt: (j['created_at'] ?? '').toString(),
    );
  }
}

File _ticketsFile(String appName, String? baseDir) =>
    arinaDataFile(appName, 'arina_tickets.json', baseDir: baseDir);

Future<List<ArinaTrackedTicket>> loadArinaTickets(
    {required String appName, String? baseDir}) async {
  try {
    final f = _ticketsFile(appName, baseDir);
    if (!await f.exists()) return [];
    final j = jsonDecode(await f.readAsString());
    if (j is! List) return [];
    return [
      for (final x in j)
        if (ArinaTrackedTicket.fromJson(x) != null) ArinaTrackedTicket.fromJson(x)!
    ];
  } catch (_) {
    return [];
  }
}

Future<void> saveArinaTickets(List<ArinaTrackedTicket> list,
    {required String appName, String? baseDir}) async {
  final f = _ticketsFile(appName, baseDir);
  await f.parent.create(recursive: true);
  await f.writeAsString(jsonEncode([for (final t in list) t.toJson()]),
      flush: true);
}

/// Adds (or replaces) a ticket, newest first, keeping the last few only.
Future<void> addArinaTicket(ArinaTrackedTicket t,
    {required String appName, String? baseDir}) async {
  final list = await loadArinaTickets(appName: appName, baseDir: baseDir);
  list.removeWhere((x) => x.id == t.id);
  list.insert(0, t);
  if (list.length > _kMaxTracked) list.removeRange(_kMaxTracked, list.length);
  await saveArinaTickets(list, appName: appName, baseDir: baseDir);
}

/// Clears the "unseen" flag of one ticket.
Future<void> markArinaTicketSeen(int id,
    {required String appName, String? baseDir}) async {
  final list = await loadArinaTickets(appName: appName, baseDir: baseDir);
  var changed = false;
  for (var i = 0; i < list.length; i++) {
    if (list[i].id == id && list[i].unseen) {
      list[i] = list[i].copyWith(unseen: false);
      changed = true;
    }
  }
  if (changed) await saveArinaTickets(list, appName: appName, baseDir: baseDir);
}
