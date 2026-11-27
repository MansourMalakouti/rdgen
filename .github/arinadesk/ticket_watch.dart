// Checks the tickets created from this computer against Zammad and reports
// what changed (new agent reply, ticket closed). Pure Dart, no Flutter.
import 'support_api.dart';
import 'support_store.dart';
import 'ticket_store.dart';

const String kArinaEventAnswered = 'answered';
const String kArinaEventClosed = 'closed';

class ArinaTicketEvent {
  final ArinaTrackedTicket ticket;
  final String kind; // kArinaEvent*
  final String preview; // short text of the newest agent reply, may be ''
  const ArinaTicketEvent(this.ticket, this.kind, this.preview);
}

/// One polling round. Network or login problems never throw: the stored state
/// is simply kept and the next round tries again.
Future<List<ArinaTicketEvent>> arinaPollTickets({
  required ArinaSupportSettings settings,
  required String appName,
  String? baseDir,
}) async {
  final list = await loadArinaTickets(appName: appName, baseDir: baseDir);
  final events = <ArinaTicketEvent>[];
  final out = <ArinaTrackedTicket>[];
  var changed = false;

  for (final t in list) {
    if (t.status == kArinaStatusClosed) {
      out.add(t);
      continue;
    }
    final ArinaTicketInfo info;
    try {
      info = await arinaGetTicket(
        url: settings.url,
        user: settings.user,
        password: settings.password,
        id: t.id,
      );
    } on ArinaSupportException catch (e) {
      if (e.code == 404) {
        changed = true; // ticket is gone: stop tracking it
      } else {
        out.add(t);
      }
      continue;
    } catch (_) {
      out.add(t);
      continue;
    }

    final status = arinaStatusOf(info);
    final agentAt = info.lastAgentAt?.toUtc().toIso8601String() ?? '';
    final closedNow = status == kArinaStatusClosed && t.status != kArinaStatusClosed;
    final newReply = agentAt.isNotEmpty &&
        agentAt != t.lastAgentAt &&
        status != kArinaStatusClosed;
    final kind = closedNow
        ? kArinaEventClosed
        : (newReply ? kArinaEventAnswered : '');

    final updated = t.copyWith(
      title: info.title.isEmpty ? t.title : info.title,
      status: status,
      lastAgentAt: agentAt,
      unseen: t.unseen || kind.isNotEmpty,
    );
    if (updated.status != t.status ||
        updated.lastAgentAt != t.lastAgentAt ||
        updated.title != t.title ||
        updated.unseen != t.unseen) {
      changed = true;
    }
    out.add(updated);

    if (kind.isNotEmpty) {
      var preview = '';
      try {
        preview = await arinaLastAgentReply(
          url: settings.url,
          user: settings.user,
          password: settings.password,
          id: t.id,
        );
      } catch (_) {}
      events.add(ArinaTicketEvent(updated, kind, preview));
    }
  }

  if (changed) {
    await saveArinaTickets(out, appName: appName, baseDir: baseDir);
  }
  return events;
}
