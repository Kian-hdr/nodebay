#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

python3 -m unittest tests.test_nodebay_browser_bridge
node --check BrowserBridge/extension/background.js
node --check BrowserBridge/extension/media.js
perl -c BrowserBridge/native/nodebay-browser-bridge
python3 -m json.tool BrowserBridge/extension/manifest.json >/dev/null

print "Browser bridge contract and framing tests: passed"
