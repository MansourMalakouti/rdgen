// ArinaDesk quick system check - core logic.
//
// Pure Dart: no PowerShell, no cmd, no child processes. Windows facts come
// straight from kernel32 through dart:ffi, network checks use dart:io sockets.
// Nothing here is company specific (the support server host is passed in).
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

typedef _GlobalMemoryStatusExC = Int32 Function(Pointer<_MemoryStatusEx>);
typedef _GlobalMemoryStatusExD = int Function(Pointer<_MemoryStatusEx>);
typedef _GetDiskFreeSpaceExC = Int32 Function(
    Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetDiskFreeSpaceExD = int Function(
    Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetTickCount64C = Uint64 Function();
typedef _GetTickCount64D = int Function();

const int _gib = 1024 * 1024 * 1024;

String _gb(int bytes) => (bytes / _gib).toStringAsFixed(1);

String _two(int n) => n.toString().padLeft(2, '0');

String _short(Object e) {
  var s = e.toString().replaceAll('\n', ' ').replaceAll('\r', ' ');
  if (s.length > 70) s = '${s.substring(0, 70)}...';
  return s;
}

String _safe(String Function() f) {
  try {
    return f();
  } catch (_) {
    return 'unavailable';
  }
}

String _uptimeLine() {
  try {
    final lib = DynamicLibrary.open('kernel32.dll');
    final getTick =
        lib.lookupFunction<_GetTickCount64C, _GetTickCount64D>('GetTickCount64');
    final d = Duration(milliseconds: getTick());
    final text = '${d.inDays}d ${d.inHours % 24}h ${d.inMinutes % 60}m';
    final warn = d.inDays >= 14 ? '  [!] long uptime, a restart may help' : '';
    return 'Uptime: $text$warn';
  } catch (_) {
    return 'Uptime: unavailable';
  }
}

String _ramLine() {
  Pointer<_MemoryStatusEx>? p;
  try {
    final lib = DynamicLibrary.open('kernel32.dll');
    final fn = lib.lookupFunction<_GlobalMemoryStatusExC, _GlobalMemoryStatusExD>(
        'GlobalMemoryStatusEx');
    p = calloc<_MemoryStatusEx>();
    p.ref.dwLength = sizeOf<_MemoryStatusEx>();
    if (fn(p) == 0) return 'RAM: unavailable';
    final total = p.ref.ullTotalPhys;
    final avail = p.ref.ullAvailPhys;
    if (total <= 0) return 'RAM: unavailable';
    final used = total - avail;
    final pct = (used * 100 / total).round();
    final warn = pct >= 90 ? '  [!] HIGH' : '';
    return 'RAM: ${_gb(used)} / ${_gb(total)} GB used ($pct%)$warn';
  } catch (_) {
    return 'RAM: unavailable';
  } finally {
    if (p != null) calloc.free(p);
  }
}

String _diskLine() {
  Pointer<Utf16>? path;
  Pointer<Uint64>? avail;
  Pointer<Uint64>? total;
  Pointer<Uint64>? free;
  try {
    var drive = Platform.environment['SystemDrive'] ?? 'C:';
    if (drive.isEmpty) drive = 'C:';
    final root = '$drive\\';
    final lib = DynamicLibrary.open('kernel32.dll');
    final fn = lib.lookupFunction<_GetDiskFreeSpaceExC, _GetDiskFreeSpaceExD>(
        'GetDiskFreeSpaceExW');
    path = root.toNativeUtf16(allocator: calloc);
    avail = calloc<Uint64>();
    total = calloc<Uint64>();
    free = calloc<Uint64>();
    if (fn(path, avail, total, free) == 0) return 'Disk $drive: unavailable';
    final t = total.value;
    final a = avail.value;
    if (t <= 0) return 'Disk $drive: unavailable';
    final pct = (a * 100 / t).round();
    final warn = pct < 10 ? '  [!] LOW' : '';
    return 'Disk $drive: ${_gb(a)} GB free of ${_gb(t)} GB ($pct% free)$warn';
  } catch (_) {
    return 'Disk: unavailable';
  } finally {
    if (path != null) calloc.free(path);
    if (avail != null) calloc.free(avail);
    if (total != null) calloc.free(total);
    if (free != null) calloc.free(free);
  }
}

Future<String> _adaptersBlock() async {
  final b = StringBuffer('Network adapters (IPv4):');
  try {
    final list = await NetworkInterface.list(
        includeLoopback: false, type: InternetAddressType.IPv4);
    if (list.isEmpty) {
      b.write('\n  none found  [!]');
    }
    for (final i in list) {
      final addrs = i.addresses.map((a) {
        final ip = a.address;
        return ip.startsWith('169.254.') ? '$ip (link-local, no DHCP?)' : ip;
      }).join(', ');
      b.write('\n  ${i.name}: $addrs');
    }
  } catch (e) {
    b.write('\n  unavailable (${_short(e)})');
  }
  return b.toString();
}

Future<String> _dnsCheck(String host) async {
  final sw = Stopwatch()..start();
  try {
    final r =
        await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
    if (r.isEmpty) return 'DNS $host: FAIL (no answer)  [!]';
    return 'DNS $host: OK -> ${r.first.address} (${sw.elapsedMilliseconds} ms)';
  } on TimeoutException {
    return 'DNS $host: FAIL (timeout)  [!]';
  } catch (e) {
    return 'DNS $host: FAIL (${_short(e)})  [!]';
  }
}

Future<String> _tcpCheck(String label, String host, int port) async {
  final sw = Stopwatch()..start();
  try {
    final s = await Socket.connect(host, port,
        timeout: const Duration(seconds: 5));
    s.destroy();
    return '$label ($host:$port): OK (${sw.elapsedMilliseconds} ms)';
  } on TimeoutException {
    return '$label ($host:$port): FAIL (timeout)  [!]';
  } catch (e) {
    return '$label ($host:$port): FAIL (${_short(e)})  [!]';
  }
}

/// Builds the plain-text report. [serverHost] / [serverPort] is the remote
/// support server the client talks to; leave [serverHost] empty to skip it.
Future<String> buildArinaReport(
    {String serverHost = '', int serverPort = 21116}) async {
  final b = StringBuffer();
  final now = DateTime.now();
  b.writeln('=== System check ===');
  b.writeln('Time: ${now.year}-${_two(now.month)}-${_two(now.day)} '
      '${_two(now.hour)}:${_two(now.minute)}');
  b.writeln('Computer: ${_safe(() => Platform.localHostname)}');
  b.writeln('OS: ${_safe(() => Platform.operatingSystemVersion)}');

  if (Platform.isWindows) {
    b.writeln(_uptimeLine());
    b.writeln(_ramLine());
    b.writeln(_diskLine());
  }

  b.writeln(await _adaptersBlock());

  final checks = <Future<String>>[
    _dnsCheck('www.microsoft.com'),
    _tcpCheck('Internet', '1.1.1.1', 443),
  ];
  if (serverHost.isNotEmpty) {
    checks.add(_tcpCheck('Support server', serverHost, serverPort));
  }
  final results = await Future.wait(checks);
  for (final r in results) {
    b.writeln(r);
  }
  return b.toString().trimRight();
}
