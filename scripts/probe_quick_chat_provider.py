#!/usr/bin/env python3
"""Read-only Codex capability probe. Never starts a thread or submits a prompt.

Print only protocol fields/counts, never raw config, credentials, or account data.
This probe does not certify tool isolation or authorization from signed Nodebay.
"""
import json
import selectors
import subprocess
import time
import sys

EXECUTABLE = "/Applications/ChatGPT.app/Contents/Resources/codex"
DISABLED = (
    "hooks", "plugins", "remote_plugin", "apps", "computer_use", "browser_use",
    "browser_use_external", "browser_use_full_cdp_access", "in_app_browser",
    "multi_agent", "memories", "shell_snapshot", "shell_tool", "unified_exec",
    "view_image", "image_generation", "workspace_dependencies", "skill_search",
    "skill_mcp_dependency_install", "goals", "sleep_tool", "code_mode_host",
)


def summarize_status(config, account):
    """Return only allowlisted diagnostics; never treat auth presence as readiness."""
    servers = config.get("mcp_servers", {}) or {}
    features = config.get("features", {}) or {}
    return {
        "protocol_initialized": True,
        "mcp_entries_after_empty_override": len(servers),
        "enabled_mcp_entries_after_empty_override": sum(
            1 for value in servers.values() if value.get("enabled", True)
        ),
        "requested_features_disabled": all(features.get(key) is False for key in DISABLED),
        "account_present_not_freshly_validated": account.get("account") is not None,
        "thread_started": False,
        "model_request_sent": False,
        "security_compatibility": "not established",
    }


def main():
    args = [EXECUTABLE, "app-server", "--strict-config", "--stdio"]
    for feature in DISABLED:
        args += ["--disable", feature]
    for override in (
        "mcp_servers={}", "notify=[]", 'web_search="disabled"',
        "analytics.enabled=false", 'history.persistence="none"',
        "project_doc_max_bytes=0",
    ):
        args += ["-c", override]
    process = subprocess.Popen(
        args, cwd="/private/tmp", stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True,
    )
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    buffer = b""

    def request(method, request_id, params):
        nonlocal buffer
        payload = {"method": method, "params": params}
        if request_id is not None:
            payload["id"] = request_id
        process.stdin.write(json.dumps(payload).encode() + b"\n")
        process.stdin.flush()
        if request_id is None:
            return None
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                message = json.loads(line)
                if message.get("id") == request_id:
                    if "error" in message:
                        raise RuntimeError("protocol request rejected")
                    return message["result"]
            if selector.select(timeout=0.2):
                chunk = process.stdout.read1(65536)
                if not chunk:
                    raise RuntimeError("provider exited")
                buffer += chunk
                if len(buffer) > 2 * 1024 * 1024:
                    raise RuntimeError("protocol size limit")
        raise RuntimeError("protocol timeout")

    try:
        request("initialize", 1, {"clientInfo": {
            "name": "nodebay_readonly_capability_probe", "version": "1.2.0"
        }})
        request("initialized", None, {})
        result = request("config/read", 2, {"includeLayers": False})
        config = result.get("config", {})
        account = request("account/read", 3, {"refreshToken": False})
        print(json.dumps(summarize_status(config, account), indent=2))
        if "--models" in sys.argv:
            models = request("model/list", 4, {"includeHidden": False})
            print(json.dumps({"models": [{key: item.get(key) for key in
                ("id", "model", "isDefault", "defaultReasoningEffort", "supportedReasoningEfforts")}
                for item in models.get("data", [])]}, indent=2))
    except (OSError, ValueError, RuntimeError, BrokenPipeError):
        print(json.dumps({"probe": "failed", "details": "redacted", "thread_started": False}))
        return 1
    finally:
        selector.close()
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdin.close()
        process.stdout.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
