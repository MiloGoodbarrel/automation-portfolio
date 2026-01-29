__author__ = "Luis Ramirez"

"""Service health checker with optional webhook notification."""

from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request
from datetime import datetime
from typing import List, Dict, Any


def check_url(url: str, timeout: int, retries: int, interval: float) -> Dict[str, Any]:
    last_error = None
    for attempt in range(1, retries + 1):
        start = time.time()
        try:
            req = urllib.request.Request(url, method="GET")
            with urllib.request.urlopen(req, timeout=timeout) as response:
                duration_ms = int((time.time() - start) * 1000)
                return {
                    "url": url,
                    "status": response.status,
                    "ok": 200 <= response.status < 400,
                    "duration_ms": duration_ms,
                    "attempts": attempt,
                }
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
            last_error = exc
            time.sleep(interval)

    return {
        "url": url,
        "status": None,
        "ok": False,
        "duration_ms": None,
        "attempts": retries,
        "error": str(last_error),
    }


def post_webhook(webhook_url: str, message: str) -> None:
    payload = json.dumps({"text": message}).encode("utf-8")
    req = urllib.request.Request(webhook_url, data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    urllib.request.urlopen(req, timeout=10).read()


def main() -> int:
    parser = argparse.ArgumentParser(description="Service health checker")
    parser.add_argument("--url", action="append", required=True, help="Target URL (repeatable)")
    parser.add_argument("--timeout", type=int, default=10, help="Request timeout in seconds")
    parser.add_argument("--retries", type=int, default=2, help="Retry count")
    parser.add_argument("--interval", type=float, default=1.0, help="Seconds between retries")
    parser.add_argument("--output", help="Write JSON results to file")
    parser.add_argument("--webhook-url", help="Optional webhook URL for alerts")

    args = parser.parse_args()

    results: List[Dict[str, Any]] = [
        check_url(url, args.timeout, args.retries, args.interval) for url in args.url
    ]

    timestamp = datetime.utcnow().isoformat() + "Z"
    summary = {
        "timestamp": timestamp,
        "total": len(results),
        "healthy": sum(1 for r in results if r.get("ok")),
        "unhealthy": sum(1 for r in results if not r.get("ok")),
        "results": results,
    }

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2)

    if args.webhook_url and summary["unhealthy"] > 0:
        failed = [r["url"] for r in results if not r.get("ok")]
        message = f"Health check failed for {len(failed)} service(s): {', '.join(failed)}"
        post_webhook(args.webhook_url, message)

    print(json.dumps(summary, indent=2))
    return 0 if summary["unhealthy"] == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
