"""Build the static Godot web site; the API origin is public configuration.

Usage: python3 tools/build_web.py [--api-url https://example.workers.dev]
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "tools/export_templates/web_nothreads_release.zip"
OUTPUT = ROOT / "dist/web"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-url", default=os.getenv("EVW_WEB_API_URL", ""),
                        help="Public HTTPS URL of the score Worker; empty for offline testing")
    parser.add_argument("--godot", default=os.getenv("GODOT_BIN", "godot"))
    args = parser.parse_args()
    api_url = args.api_url.strip().rstrip("/")
    if api_url:
        parsed = urlparse(api_url)
        if parsed.scheme != "https" or not parsed.netloc or parsed.path or parsed.query or parsed.fragment:
            parser.error("--api-url must be an HTTPS origin without a path")
    if not TEMPLATE.is_file():
        subprocess.run([sys.executable, str(ROOT / "tools/fetch_web_template.py"),
                        str(TEMPLATE)], check=True)
    # Old exports inside res:// would otherwise be picked up by Godot's scan.
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    export = subprocess.run([args.godot, "--headless", "--path", str(ROOT),
                             "--export-release", "Web", str(OUTPUT / "index.html")],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if export.returncode:
        print(export.stdout[-8000:], file=sys.stderr)
        raise RuntimeError(f"Godot web export failed (exit {export.returncode})")
    errors = [line for line in export.stdout.splitlines() if "ERROR:" in line
              and "editor_settings" not in line and "editor settings" not in line]
    if errors:
        print("Godot meldde fouten tijdens de export:\n" + "\n".join(errors[-15:]),
              file=sys.stderr)
    html = (OUTPUT / "index.html").read_text()
    marker = '<script src="index.js"></script>'
    if html.count(marker) != 1:
        raise RuntimeError("Godot HTML shell changed; could not insert API config")
    html = html.replace(marker, '<script src="api-config.js"></script>\n\t\t' + marker)
    html = html.replace(marker, '<script src="mobile-sensors.js"></script>\n\t\t' + marker)
    html = html.replace(marker, '<script src="mobile-browser.js"></script>\n\t\t' + marker)
    mobile_style = """<style>
html, body, #canvas, button {
    -webkit-user-select: none;
    user-select: none;
    -webkit-touch-callout: none;
    overscroll-behavior: none;
}
body > input, body > textarea { font-size: 20px; }
body > .evw-keyboard-field {
    position: fixed !important;
    z-index: 31 !important;
    left: 24px !important;
    top: 52px !important;
    width: calc(100vw - 48px) !important;
    max-width: none !important;
    height: 42px !important;
    box-sizing: border-box !important;
    padding: 5px 10px !important;
    border: 2px solid #f7c843 !important;
    border-radius: 6px !important;
    background: #101c2a !important;
    color: #eff8ff !important;
    -webkit-user-select: text !important;
    user-select: text !important;
}
#evw-keyboard-panel {
    position: fixed;
    z-index: 30;
    left: 8px;
    right: 8px;
    top: 8px;
    height: 96px;
    box-sizing: border-box;
    padding: 10px 16px;
    background: #1b2b3b;
    border: 2px solid #f7c843;
    border-radius: 8px;
    color: #eff8ff;
    font: 18px sans-serif;
    display: none;
}
#evw-keyboard-panel button {
    float: right;
    border: 0;
    border-radius: 4px;
    background: #f7c843;
    color: #101c2a;
    font: 16px sans-serif;
    padding: 4px 12px;
    touch-action: manipulation;
}
</style>"""
    html = html.replace('</head>', mobile_style + '\n\t</head>')
    (OUTPUT / "index.html").write_text(html)
    shutil.copyfile(ROOT / "tools/mobile-sensors.js", OUTPUT / "mobile-sensors.js")
    shutil.copyfile(ROOT / "tools/mobile-browser.js", OUTPUT / "mobile-browser.js")
    (OUTPUT / "api-config.js").write_text(
        "window.EVW_API_BASE_URL = " + json.dumps(api_url) + ";\n")
    (OUTPUT / ".nojekyll").touch()
    print(f"Web build: {OUTPUT} (score API: {api_url or 'niet ingesteld'})")


if __name__ == "__main__":
    main()
