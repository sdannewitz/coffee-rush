"""Render a trace's calls to coffee-bar as an ASCII waterfall.
Reads `gcx traces get <id> -o json` on stdin."""
import json
import sys

raw = sys.stdin.read()
if "{" not in raw:
    sys.exit("no trace JSON on stdin (is the trace ID right, and is gcx logged in?)")
trace = json.loads(raw[raw.index("{"):])


def walk(o):
    if isinstance(o, dict):
        for s in o.get("spans", []) if isinstance(o.get("spans"), list) else []:
            yield s
        for v in o.values():
            yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)


def url(span):
    for a in span.get("attributes", []):
        if a.get("key") in ("url.full", "http.url", "url.path", "http.target"):
            return (a.get("value") or {}).get("stringValue", "")
    return ""


def calls(spans, kind):
    return [s for s in spans if s.get("kind") == kind
            and (s.get("name", "").endswith(" /pull") or url(s).endswith("/pull"))]


spans = list(walk(trace))
pulls = calls(spans, "SPAN_KIND_CLIENT") or calls(spans, "SPAN_KIND_SERVER")
batch = [s for s in spans if "/pull/batch" in s.get("name", "") + url(s)]
if not pulls:
    note = " (it calls /pull/batch instead)" if batch else ""
    sys.exit(f"no calls to coffee-bar's /pull in this trace{note}")

pulls.sort(key=lambda s: int(s["startTimeUnixNano"]))
t0 = min(int(s["startTimeUnixNano"]) for s in pulls)
tn = max(int(s["endTimeUnixNano"]) for s in pulls)
total = max(tn - t0, 1)
W = 56
C, R = "\033[38;5;179m", "\033[0m"

print()
print("  calls to coffee-bar: %s%d%s     wall clock: %s%.0f ms%s" % (C, len(pulls), R, C, total / 1e6, R))
print("  " + "-" * (W + 14))
for i, s in enumerate(pulls, 1):
    st, en = int(s["startTimeUnixNano"]), int(s["endTimeUnixNano"])
    off = int((st - t0) / total * W)
    ln = max(1, int((en - st) / total * W))
    print("  %3d |%s%s%s%s%s| %5.0f ms" % (i, " " * off, C, "█" * ln, R, " " * max(0, W - off - ln), (en - st) / 1e6))
print("  " + "-" * (W + 14))
print()
