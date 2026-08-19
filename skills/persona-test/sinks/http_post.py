"""Generic authenticated POST sink. Uses urllib (stdlib) only.
--dry-run prints the body and makes no network call (default test path)."""
import argparse, json, os, sys, urllib.request, urllib.error

def build_request(url, token_env, body):
    token = os.environ.get(token_env)
    if not token:
        raise RuntimeError(f"env var {token_env} is not set")
    headers = {"Authorization": f"Bearer {token}",
               "Content-Type": "application/json"}
    data = json.dumps(body).encode("utf-8")
    return url, headers, data

def post(url, token_env, body, dry_run=False):
    if dry_run:
        print(json.dumps(body, indent=2))
        return {"ok": True, "status": 0, "error": None, "dry_run": True}
    try:
        url, headers, data = build_request(url, token_env, body)
    except RuntimeError as e:
        return {"ok": False, "status": 0, "error": str(e)}
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return {"ok": 200 <= resp.status < 300, "status": resp.status, "error": None}
    except urllib.error.HTTPError as e:
        return {"ok": False, "status": e.code, "error": e.read().decode("utf-8", "replace")}
    except Exception as e:  # network unreachable, timeout, DNS
        return {"ok": False, "status": 0, "error": str(e)}

def _main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--token-env", required=True)
    ap.add_argument("--body", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    with open(a.body) as f:
        body = json.load(f)
    res = post(a.url, a.token_env, body, dry_run=a.dry_run)
    if not res["ok"] and not a.dry_run:
        print(f"POST failed: status={res['status']} {res['error']}", file=sys.stderr)
        return 2
    return 0

if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
