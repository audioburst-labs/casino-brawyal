class_name TelemetryBatch
extends RefCounted
## The POST envelope, and the retry policy behind it.
##
## Transport is deliberately at-least-once: a 2xx can be lost on the wire after
## the server has committed, and this client will resend rather than guess. The
## server dedups on `batch` and on `(run_id, seq)`, so a resend writes nothing.
## Do not "fix" that into exactly-once here — the uniqueness constraints are
## load-bearing and cheaper than a handshake.

const MAX_EVENTS := 500
const MAX_BYTES := 256 * 1024

## Backoff: full jitter, 30 s doubling to a half-hour ceiling. An offline
## laptop makes ~4 DNS lookups an hour, which is nothing, and the spool is
## exactly what it is for — so there is no "give up forever" rule.
const BASE_DELAY := 30.0
const MAX_DELAY := 1800.0

enum Verdict { OK, RETRY, DROP, STOP }


## Builds the body from spooled lines. Returns `{}` when there is nothing to
## send, otherwise `{"batch": …, "events": […], "count": n}` — `count` is how
## many spool lines to drop once the server has taken them.
static func build(lines: Array[Dictionary], meta: Dictionary) -> Dictionary:
	if lines.is_empty():
		return {}
	var events: Array = []
	var bytes := 0
	for line in lines:
		if events.size() >= MAX_EVENTS:
			break
		var size := JSON.stringify(line).length()
		if bytes + size > MAX_BYTES and not events.is_empty():
			break
		events.append(line)
		bytes += size
	var body := {
		"v": 1,
		"batch": TelemetryIds.uuid4(),
		"inst": str(meta.get("install_id", "")),
		"app": str(meta.get("app_version", "")),
		"os_name": str(meta.get("os_name", "")),
		"os_version": str(meta.get("os_version", "")),
		"cpu_name": str(meta.get("cpu_name", "")),
		"cpu_count": int(meta.get("cpu_count", 0)),
		"gpu_name": str(meta.get("gpu_name", "")),
		"screen": str(meta.get("screen", "")),
		"locale": str(meta.get("locale", "")),
		"malformed": int(meta.get("malformed", 0)),
		"events": events,
	}
	return {"batch": body, "count": events.size()}


## What to do about a finished HTTPRequest.
## `result` is HTTPRequest.Result; `code` the HTTP status (0 when there is none).
static func classify(result: int, code: int) -> Verdict:
	if result != HTTPRequest.RESULT_SUCCESS:
		return Verdict.RETRY               # no route, no DNS, timeout: offline
	if code >= 200 and code < 300:
		return Verdict.OK
	if code == 401 or code == 403:
		return Verdict.STOP                # a bad key will not fix itself
	if code == 400 or code == 413:
		return Verdict.DROP                # these exact bytes will never pass
	return Verdict.RETRY                   # 429, 5xx, anything else


static func next_delay(failures: int, rng: RandomNumberGenerator = null) -> float:
	var steps := clampi(failures, 0, 30)     # pow() has no business overflowing
	var ceiling: float = minf(BASE_DELAY * pow(2.0, float(steps)), MAX_DELAY)
	var jitter := rng.randf_range(0.5, 1.0) if rng != null else randf_range(0.5, 1.0)
	return ceiling * jitter
