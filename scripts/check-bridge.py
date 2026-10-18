"""Exercise the real helper process, including recovery after invalid input."""

import json
from pathlib import Path
import subprocess


root = Path(__file__).resolve().parent.parent
assembly = root / "Bridge/BakaThreesome.ShikimoriBridge/bin/Debug/net10.0/BakaThreesome.ShikimoriBridge.dll"
requests = [
    {"version": 1, "id": "request-é-1", "method": "handshake"},
    {"version": 2, "id": "version", "method": "handshake"},
    {"version": 1, "id": "method", "method": "not-implemented"},
    "malformed",
    {"version": 1, "id": "after-error", "method": "handshake"},
]
payload = "\n".join(
    item if isinstance(item, str) else json.dumps(item, ensure_ascii=False)
    for item in requests
) + "\n"
result = subprocess.run(
    ["dotnet", str(assembly)],
    input=payload, capture_output=True, text=True, timeout=10, check=True,
)
responses = [json.loads(line) for line in result.stdout.splitlines()]
assert len(responses) == len(requests), "Expected one response per request"
assert result.stderr == "", "Unexpected helper diagnostics"
assert responses[0]["id"] == "request-é-1"
assert {"handshake", "catalog.search", "watchlist.save"} <= set(responses[0]["result"]["capabilities"])
assert responses[1]["error"]["code"] == "unsupported_version"
assert responses[2]["error"]["code"] == "unknown_method"
assert responses[3]["error"]["code"] == "invalid_json"
assert responses[4]["id"] == "after-error"
assert responses[4]["result"]["name"] == "BakaThreesome.ShikimoriBridge"
assert all(item["version"] == 1 for item in responses)
print("Bridge smoke check passed: handshake, Unicode IDs, version/method errors, recovery and EOF.")
