"""Compare the OPNsense interface configuration with interfaces-expected.json.

Interface assignments and addresses have no write API in OPNsense, so they
cannot be managed by OpenTofu; this check makes any change to them visible.
Exit 0 = in sync, 1 = drift (the alert OPNsenseInterfaceDrift fires),
2 = could not check.

Env: OPNSENSE_URI, OPNSENSE_API_KEY, OPNSENSE_API_SECRET,
OPNSENSE_ALLOW_INSECURE ("true" for the self-signed GUI cert),
EXPECTED (path to the JSON, default ./interfaces-expected.json).
API privileges: "Status: Interfaces", "Interfaces: Bridge".
"""

import base64
import json
import os
import ssl
import sys
import urllib.request

FIELDS_FROM_CONFIG = ("ipaddr", "subnet", "ipaddrv6", "blockpriv", "blockbogons")
IGNORED = {"lo0", ""}


def api(path):
    uri = os.environ["OPNSENSE_URI"].rstrip("/") + "/api/" + path
    token = base64.b64encode(
        f"{os.environ['OPNSENSE_API_KEY']}:{os.environ['OPNSENSE_API_SECRET']}".encode()
    ).decode()
    req = urllib.request.Request(uri, headers={"Authorization": "Basic " + token})
    ctx = ssl.create_default_context()
    if os.environ.get("OPNSENSE_ALLOW_INSECURE") == "true":
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
        return json.load(resp)


def live_state():
    interfaces = {}
    for row in api("interfaces/overview/interfaces_info")["rows"]:
        ident = row.get("identifier") or ""
        if ident in IGNORED:
            continue
        cfg = row.get("config") or {}
        entry = {
            "description": row.get("description"),
            "device": row.get("device"),
            "enabled": bool(row.get("enabled")),
        }
        entry.update({k: cfg.get(k) for k in FIELDS_FROM_CONFIG})
        interfaces[ident] = entry
    bridges = {
        row["bridgeif"]: {k: row.get(k) for k in ("members", "proto", "descr")}
        for row in api("interfaces/bridge_settings/search_item")["rows"]
    }
    return {"interfaces": interfaces, "bridges": bridges}


def diff(expected, live):
    problems = []
    for section in ("interfaces", "bridges"):
        exp, cur = expected.get(section, {}), live.get(section, {})
        for name in sorted(set(exp) | set(cur)):
            if name not in cur:
                problems.append(f"{section}/{name}: missing on the firewall")
            elif name not in exp:
                problems.append(f"{section}/{name}: new on the firewall: {json.dumps(cur[name])}")
            else:
                for key in sorted(set(exp[name]) | set(cur[name])):
                    if exp[name].get(key) != cur[name].get(key):
                        problems.append(
                            f"{section}/{name}.{key}: expected {exp[name].get(key)!r}, "
                            f"firewall has {cur[name].get(key)!r}"
                        )
    return problems


def main():
    path = os.environ.get("EXPECTED", "interfaces-expected.json")
    with open(path, encoding="utf-8") as f:
        expected = json.load(f)
    try:
        live = live_state()
    except Exception as e:  # noqa: BLE001 - any failure means "could not check"
        print(f"ERROR could not read the firewall: {e}", file=sys.stderr)
        return 2
    problems = diff(expected, live)
    if not problems:
        print("interfaces in sync")
        return 0
    print(f"DRIFT {len(problems)} difference(s) from infra/opnsense-ops/interfaces-expected.json:")
    for p in problems:
        print("  " + p)
    return 1


if __name__ == "__main__":
    sys.exit(main())
