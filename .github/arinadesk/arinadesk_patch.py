#!/usr/bin/env python3
"""ArinaDesk UI patch for the RustDesk Flutter client.

Target: RustDesk 1.5.3 (flutter/lib/desktop/pages/desktop_home_page.dart).

Adds an "ArinaDesk tools" button area to the left pane of the home page.
Buttons:
  1. "request support": creates a Zammad ticket (HTTP Basic auth, credentials
     are saved once in the app's support settings).
  2. "track tickets": opens the helpdesk site in the browser.
  3. "quick system check": disk, RAM, uptime, adapters, DNS and connectivity
     checks done natively (dart:ffi / dart:io), no PowerShell or cmd involved.
  4. "copy ticket info": ID, computer name and OS go to the clipboard.

It also bundles the Vazirmatn font (downloaded at build time, checksum
verified, SIL OFL licence) and registers it in flutter/pubspec.yaml.

The script FAILS (non-zero exit) if an anchor line is not found exactly once,
so a RustDesk upgrade that changes the UI breaks the build loudly instead of
silently producing a client without the buttons.

No company-specific values live here: this repository is public.
"""
import argparse
import hashlib
import pathlib
import sys
import time
import urllib.request

HOME_PAGE = "flutter/lib/desktop/pages/desktop_home_page.dart"

MARKER = "buildArinaTools"

# extra Dart files shipped next to this script, copied into the RustDesk tree
EXTRA_DIR = "flutter/lib/arinadesk"
EXTRA_FILES = (
    "arina_config.dart",
    "arina_ui_common.dart",
    "support_api.dart",
    "support_store.dart",
    "support_ui.dart",
    "system_check_core.dart",
    "system_check_ui.dart",
)

# Vazirmatn (SIL OFL 1.1), pinned release + SHA-256 so a changed file is rejected
PUBSPEC = "flutter/pubspec.yaml"
FONT_DIR = "flutter/assets/fonts"
FONT_URL = "https://raw.githubusercontent.com/rastikerdar/vazirmatn/v33.003/fonts/ttf/%s"
FONT_FILES = (
    ("Vazirmatn-Regular.ttf",
     "b69fd4c680b8f3f225feabcc655a2c585d97627b8f5f5c0f9985e894069f3a56"),
    ("Vazirmatn-Bold.ttf",
     "f635fdbea28f265de395ba83b4b1570dcf2f58d13c65469e61903b1c2d2ae723"),
)
FONT_YAML = (
    "    - family: Vazirmatn\n"
    "      fonts:\n"
    "        - asset: assets/fonts/Vazirmatn-Regular.ttf\n"
    "        - asset: assets/fonts/Vazirmatn-Bold.ttf\n"
    "          weight: 700\n"
)

# import line added to the home page (anchor must exist exactly once)
IMPORT_ANCHOR = "import 'package:flutter_hbb/consts.dart';"
IMPORT_INSERT_LINES = (
    "import 'package:flutter_hbb/arinadesk/support_ui.dart';",
    "import 'package:flutter_hbb/arinadesk/system_check_ui.dart';",
)

# 1) the children list of buildLeftPane(): add our widget after the password board
LIST_ANCHOR = "if (!isOutgoingOnly) buildPasswordBoard(context),"
LIST_INSERT = "if (!isOutgoingOnly) buildArinaTools(context),"

# 2) the class body: add our methods right before buildRightPane()
METHOD_ANCHOR = "buildRightPane(BuildContext context) {"

# First line has no indent: the two spaces before METHOD_ANCHOR in the file are reused.
METHODS = r"""Widget buildArinaTools(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 16, top: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _arinaToolButton(
              Icons.support_agent,
              'درخواست پشتیبانی',
              () => showArinaSupportRequest(
                  context, gFFI.serverModel.serverId.text.trim())),
          const SizedBox(height: 6),
          _arinaToolButton(Icons.open_in_new, 'پیگیری تیکت‌ها',
              () => openArinaSupportPortal(context)),
          const SizedBox(height: 6),
          _arinaToolButton(
              Icons.speed, 'بررسی سریع سیستم', () => showArinaSystemCheck(context)),
          const SizedBox(height: 6),
          _arinaToolButton(
              Icons.content_copy, 'کپی اطلاعات برای تیکت', _arinaCopyTicketInfo),
        ],
      ),
    );
  }

  Widget _arinaToolButton(IconData icon, String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: AutoSizeText(
              label,
              style: const TextStyle(fontFamily: 'Vazirmatn'),
              maxLines: 1,
              minFontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _arinaCopyTicketInfo() async {
    final appName = bind.mainGetAppNameSync();
    final id = gFFI.serverModel.serverId.text.trim();
    var host = '';
    var os = '';
    try {
      host = Platform.localHostname;
      os = Platform.operatingSystemVersion;
    } catch (_) {}
    final lines = <String>[
      '$appName ID: $id',
      if (host.isNotEmpty) 'Computer: $host',
      if (os.isNotEmpty) 'OS: $os',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    showToast('اطلاعات کپی شد. آن را در تیکت جای‌گذاری کنید.');
  }"""


def fail(msg):
    print("ARINADESK PATCH ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


def download_font(name, sha256, dest_dir):
    dest = dest_dir / name
    if dest.is_file() and hashlib.sha256(dest.read_bytes()).hexdigest() == sha256:
        return
    last = None
    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(FONT_URL % name, timeout=60) as r:
                data = r.read()
            got = hashlib.sha256(data).hexdigest()
            if got != sha256:
                fail("font checksum mismatch for %s (got %s)" % (name, got))
            dest.write_bytes(data)
            print("font ready: %s" % dest)
            return
        except SystemExit:
            raise
        except Exception as e:  # network hiccup: retry
            last = e
            time.sleep(3 * attempt)
    fail("could not download font %s: %s" % (name, last))


def install_fonts(root):
    dest_dir = root / FONT_DIR
    dest_dir.mkdir(parents=True, exist_ok=True)
    for name, sha in FONT_FILES:
        download_font(name, sha, dest_dir)

    pub = root / PUBSPEC
    if not pub.is_file():
        fail("file not found: %s" % pub)
    with open(pub, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    if "family: Vazirmatn" in text:
        print("pubspec already lists Vazirmatn")
        return
    nl = "\r\n" if "\r\n" in text else "\n"
    anchor = nl + "  fonts:" + nl
    if text.count(anchor) != 1:
        fail("pubspec 'fonts:' anchor found %d times (expected 1)" % text.count(anchor))
    block = FONT_YAML.replace("\n", nl)
    text = text.replace(anchor, anchor + block, 1)
    with open(pub, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print("pubspec updated with Vazirmatn")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rustdesk-root", default=".")
    args = ap.parse_args()

    root = pathlib.Path(args.rustdesk_root)
    path = root / HOME_PAGE
    if not path.is_file():
        fail("file not found: %s" % path)

    install_fonts(root)

    # copy the extra Dart files (always, they are ours and safe to overwrite)
    here = pathlib.Path(__file__).resolve().parent
    dest = pathlib.Path(args.rustdesk_root) / EXTRA_DIR
    dest.mkdir(parents=True, exist_ok=True)
    for name in EXTRA_FILES:
        srcfile = here / name
        if not srcfile.is_file():
            fail("missing file next to the script: %s" % srcfile)
        (dest / name).write_bytes(srcfile.read_bytes())
        print("copied %s -> %s" % (name, dest))

    # newline="" keeps the original line endings (LF or CRLF) untouched
    with open(path, "r", encoding="utf-8", newline="") as f:
        src = f.read()

    if MARKER in src:
        print("ArinaDesk patch already applied, nothing to do.")
        return

    nl = "\r\n" if "\r\n" in src else "\n"

    for name, anchor in (("import anchor", IMPORT_ANCHOR),
                         ("list anchor", LIST_ANCHOR),
                         ("method anchor", METHOD_ANCHOR)):
        n = src.count(anchor)
        if n != 1:
            fail("%s found %d times (expected exactly 1): %s" % (name, n, anchor))

    src = src.replace(IMPORT_ANCHOR, IMPORT_ANCHOR + nl + nl.join(IMPORT_INSERT_LINES), 1)
    src = src.replace(LIST_ANCHOR, LIST_ANCHOR + nl + "      " + LIST_INSERT, 1)

    methods = METHODS.replace("\r\n", "\n").replace("\n", nl)
    src = src.replace(METHOD_ANCHOR, methods + nl + nl + "  " + METHOD_ANCHOR, 1)

    # sanity checks
    if src.count(MARKER) != 2:
        fail("unexpected marker count after patching: %d" % src.count(MARKER))
    if src.count("{") != src.count("}"):
        fail("brace count mismatch after patching")

    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(src)

    print("ArinaDesk patch applied to %s" % HOME_PAGE)


if __name__ == "__main__":
    main()
