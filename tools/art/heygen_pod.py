#!/usr/bin/env python3
"""Casino Brawyal — HeyGen talking-face generation, run inside a cloud pod.

The office network blocks api.heygen.com, so this runs in the AKS cluster
(kubectl cp'd into a python:3.12-slim pod along with the portrait images).
Stdlib only — no pip installs needed.

Expects: HYGEN_API_KEY env var; /work/ace_portrait.png, /work/moneyman_portrait.png.
Produces: /work/ace_intro.mp4, /work/moneyman_boss_intro.mp4 (kubectl cp'd back out).
"""

import json
import os
import sys
import time
import urllib.request

API = "https://api.heygen.com"
UPLOAD = "https://upload.heygen.com/v1/talking_photo"
KEY = os.environ["HYGEN_API_KEY"]

CLIPS = [
    {
        "id": "ace_intro",
        "image": "/work/ace_portrait.png",
        "voice_hint": ["confident", "young", "male"],
        "text": (
            "They say the house always wins. Well... the house never played against me. "
            "Mister Moneyman took everything I had. Tonight, I'm taking it back — "
            "one spin at a time."
        ),
    },
    {
        "id": "moneyman_boss_intro",
        "image": "/work/moneyman_portrait.png",
        "voice_hint": ["deep", "mature", "male"],
        "text": (
            "Well, well. The little card trick made it all the way to my office. "
            "You should have taken your losses and crawled home, boy. "
            "Now... the house collects everything."
        ),
    },
]


def call(url: str, data: bytes | None = None, content_type: str = "application/json") -> dict:
    request = urllib.request.Request(url, data=data, method="POST" if data else "GET")
    request.add_header("X-Api-Key", KEY)
    if data:
        request.add_header("Content-Type", content_type)
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read())


def pick_voice(voices: list, hints: list) -> str:
    def score(voice: dict) -> int:
        blob = json.dumps(voice).lower()
        return sum(1 for hint in hints if hint in blob)
    english = [v for v in voices if "en" in str(v.get("language", "")).lower()]
    pool = english or voices
    return max(pool, key=score)["voice_id"]


def main() -> None:
    voices = call(f"{API}/v2/voices")["data"]["voices"]
    print(f"{len(voices)} voices available", flush=True)

    pending = []
    for clip in CLIPS:
        with open(clip["image"], "rb") as f:
            photo = call(UPLOAD, f.read(), "image/png")
        talking_photo_id = photo["data"]["talking_photo_id"]
        print(f"{clip['id']}: talking photo {talking_photo_id}", flush=True)

        body = json.dumps({
            "video_inputs": [{
                "character": {"type": "talking_photo", "talking_photo_id": talking_photo_id},
                "voice": {
                    "type": "text",
                    "input_text": clip["text"],
                    "voice_id": pick_voice(voices, clip["voice_hint"]),
                },
            }],
            "dimension": {"width": 1280, "height": 720},
        }).encode()
        video = call(f"{API}/v2/video/generate", body)
        video_id = video["data"]["video_id"]
        print(f"{clip['id']}: rendering {video_id}", flush=True)
        pending.append((clip["id"], video_id))

    for clip_id, video_id in pending:
        for attempt in range(60):
            status = call(f"{API}/v1/video_status.get?video_id={video_id}")["data"]
            state = status["status"]
            if state == "completed":
                out = f"/work/{clip_id}.mp4"
                urllib.request.urlretrieve(status["video_url"], out)
                print(f"{clip_id}: saved {out} ({os.path.getsize(out)} bytes)", flush=True)
                break
            if state == "failed":
                print(f"{clip_id}: FAILED {status.get('error')}", flush=True)
                sys.exit(1)
            print(f"{clip_id}: {state} ({attempt})", flush=True)
            time.sleep(15)
        else:
            print(f"{clip_id}: timed out", flush=True)
            sys.exit(1)
    print("ALL DONE", flush=True)


if __name__ == "__main__":
    main()
