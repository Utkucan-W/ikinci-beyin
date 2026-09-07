#!/usr/bin/env python3
"""Sağlayıcılar düştüğü için ertelenmiş oturum özetlerini yeniden dene.

flush.py tüm özet sağlayıcıları başarısız olduğunda oturumu kaybetmez;
`.state/deferred-flush/<key>.json` altına transkript yolunu ve tarihi yazar.
Bu betik o kayıtları sırayla yeniden işler ve başarılı olanı doğru günün
günlük raporuna ekler.

Kullanım:
    python3 retry_deferred_flush.py [--limit N] [--dry-run]
"""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import sys
from typing import Any, Sequence

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import flush as FLUSH  # noqa: E402

DEFERRED_DIR = FLUSH.STATE_DIR / FLUSH.DEFERRED_DIR_NAME


def _load(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def _same_record(before: dict[str, Any], after: dict[str, Any]) -> bool:
    """İki okuma arasında kayıt aynı mı kaldı?

    `uid` yeni kayıtlarda vardır; eski kayıtlarda yoksa zaman damgası ve
    transkript yoluna düşülür.
    """
    before_uid, after_uid = before.get("uid"), after.get("uid")
    if before_uid or after_uid:
        return before_uid == after_uid
    return (
        before.get("ts") == after.get("ts")
        and before.get("transcript_path") == after.get("transcript_path")
    )


def _event_time(record: dict[str, Any]) -> dt.datetime:
    stamp = record.get("ts")
    if isinstance(stamp, (int, float)) and stamp > 0:
        return dt.datetime.fromtimestamp(float(stamp)).astimezone()
    date_text = str(record.get("date", ""))
    try:
        naive = dt.datetime.strptime(date_text, "%Y-%m-%d")
    except ValueError:
        return dt.datetime.now().astimezone()
    return naive.replace(hour=12).astimezone()


def _retry_one(path: Path, dry_run: bool) -> str:
    record = _load(path)
    if record is None:
        return "bozuk-kayit"

    transcript_path = Path(str(record.get("transcript_path", "")))
    if not transcript_path.is_file():
        return "transkript-yok"

    turns = FLUSH.read_transcript(transcript_path)
    transcript, turn_count = FLUSH.format_turns(turns)
    if turn_count < 1:
        return "tur-yok"

    prompt = FLUSH.build_flush_prompt(transcript, 0)
    if dry_run:
        return "kuru-calisma"

    summary, error, provider = FLUSH._run_summary(prompt, FLUSH.VAULT_ROOT)
    if error is not None or not summary:
        return f"hala-basarisiz:{error or 'bos'}"
    if summary == "FLUSH_BOS":
        path.unlink(missing_ok=True)
        return "flush-bos"
    if not FLUSH.validate_summary(summary):
        return "sema-gecersiz"

    # Özet üretimi dakikalar sürebilir; bu sürede normal bir flush aynı oturumu
    # yazıp kuyruk kaydını silmiş olabilir. Rapora eklemeyi oturum kilidi
    # altında yap ve kaydın hâlâ durduğunu son anda bir kez daha doğrula;
    # aksi hâlde aynı oturum rapora iki kez girer.
    session_id = str(record.get("session_id", ""))
    lock_path = FLUSH._session_lock_path(FLUSH.STATE_DIR, session_id)
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        current = _load(path)
        if current is None:
            return "zaten-islendi"
        if not _same_record(record, current):
            # Aynı ada yeni bir kayıt yazılmış: bu özet artık o kaydı
            # temsil etmiyor. Dokunma, bir sonraki tur onu kendi özetiyle
            # işlesin.
            return "kayit-yenilendi"
        FLUSH._append_daily(
            FLUSH.VAULT_ROOT,
            summary,
            str(record.get("reason", "deferred")),
            _event_time(record),
        )
        path.unlink(missing_ok=True)
    return f"eklendi:{provider}"


def main(argv: Sequence[str] | None = None) -> int:
    if os.environ.get("BEYIN_INVOKED_BY"):
        return 0

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=5)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    if not DEFERRED_DIR.is_dir():
        print("ertelenmiş kayıt yok")
        return 0

    records = sorted(DEFERRED_DIR.glob("*.json"))
    if not records:
        print("ertelenmiş kayıt yok")
        return 0

    processed = 0
    for path in records:
        if processed >= max(args.limit, 0):
            break
        result = _retry_one(path, args.dry_run)
        print(f"{path.name}: {result}")
        processed += 1
    print(f"işlenen {processed} / bekleyen {len(records)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
