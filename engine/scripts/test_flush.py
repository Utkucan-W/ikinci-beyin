#!/usr/bin/env python3
"""flush.py regresyon testleri: süreklilik, yinelenme penceresi ve kuyruk.

Çalıştırma: python3 engine/scripts/test_flush.py
"""

from __future__ import annotations

import contextlib
import datetime as dt
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT_DIR = Path(__file__).resolve().parent


def load_flush_module():
    spec = importlib.util.spec_from_file_location("flush_precompact_test", SCRIPT_DIR / "flush.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FLUSH = load_flush_module()

SUMMARY = """## Bağlam
Kısa bağlam.
## Önemli Konuşmalar
Önemli konuşma.
## Alınan Kararlar
Karar.
## Öğrenilenler
Öğrenme.
## Yapılacaklar
Sonraki adım.
"""


class PrecompactContinuityTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.original_vault = FLUSH.VAULT_ROOT
        self.original_state = FLUSH.STATE_DIR
        FLUSH.VAULT_ROOT = self.root / "vault"
        FLUSH.STATE_DIR = FLUSH.VAULT_ROOT / ".beyin" / "engine" / "scripts" / ".state"
        FLUSH.STATE_DIR.mkdir(parents=True)
        self.addCleanup(self.restore_globals)

    def tearDown(self):
        self.tempdir.cleanup()

    def restore_globals(self):
        FLUSH.VAULT_ROOT = self.original_vault
        FLUSH.STATE_DIR = self.original_state

    def transcript_and_args(self):
        transcript = self.root / "session.jsonl"
        with transcript.open("w", encoding="utf-8") as stream:
            for number in range(5):
                stream.write(json.dumps({"role": "user", "content": f"Tur {number}"}) + "\n")
        hook_input = self.root / "hook.json"
        hook_input.write_text(
            json.dumps({"session_id": "precompact-test", "transcript_path": str(transcript)}),
            encoding="utf-8",
        )
        return transcript, type("Args", (), {
            "hook_input": hook_input,
            "reason": "precompact",
            "max_summary_chars": 1200,
            "summary_timeout_seconds": 35,
            "emit_result": True,
        })()

    def args_for(self, reason, session_id="precompact-test"):
        """Aynı oturum için farklı olay türünde ikinci bir çağrı kur."""
        transcript = self.root / f"session-{session_id}.jsonl"
        with transcript.open("w", encoding="utf-8") as stream:
            for number in range(5):
                stream.write(json.dumps({"role": "user", "content": f"Tur {number}"}) + "\n")
        hook_input = self.root / f"hook-{session_id}-{reason}.json"
        hook_input.write_text(
            json.dumps({"session_id": session_id, "transcript_path": str(transcript)}),
            encoding="utf-8",
        )
        return type("Args", (), {
            "hook_input": hook_input,
            "reason": reason,
            "max_summary_chars": 1200,
            "summary_timeout_seconds": 35,
            "emit_result": True,
        })()

    def test_sessionend_after_precompact_is_not_swallowed_as_duplicate(self):
        """Compaction'dan hemen sonra kapanan oturumun son bölümü kaybolmamalı.

        Yinelenme penceresi yalnız oturuma bakarsa, PreCompact'ten 60 saniye
        içinde gelen SessionEnd atılır ve compaction sonrası konuşulan her şey
        rapora hiç geçmez.
        """
        base = dt.datetime(2026, 9, 3, 12, tzinfo=dt.timezone.utc)
        with mock.patch.object(FLUSH, "_run_summary", return_value=(SUMMARY, None, "codex")):
            first, _ = FLUSH._flush_once(self.args_for("precompact"), base)
            second, _ = FLUSH._flush_once(
                self.args_for("sessionend"), base + dt.timedelta(seconds=5)
            )
            third, _ = FLUSH._flush_once(
                self.args_for("sessionend"), base + dt.timedelta(seconds=10)
            )

        self.assertEqual(first, "appended")
        self.assertEqual(second, "appended", "farklı olay yinelenme sayılmamalı")
        self.assertEqual(third, "duplicate", "aynı olayın tekrarı hâlâ engellenmeli")
        daily = FLUSH.VAULT_ROOT / FLUSH.DAILY_REPORTS_RELATIVE / "2026-09-03.md"
        self.assertEqual(daily.read_text(encoding="utf-8").count("### Oturum"), 2)

    def test_successful_flush_clears_the_deferred_record(self):
        """Başarılı yazımdan sonra kuyrukta kayıt kalmamalı.

        Kalırsa retry_deferred_flush.py aynı oturumu ikinci kez rapora ekler.
        """
        args = self.args_for("sessionend", session_id="kuyruk-test")
        transcript = Path(json.loads(args.hook_input.read_text(encoding="utf-8"))["transcript_path"])
        event_time = dt.datetime(2026, 9, 3, 12, tzinfo=dt.timezone.utc)
        self.assertTrue(
            FLUSH._defer_flush(
                FLUSH.STATE_DIR, "kuyruk-test", transcript,
                "sessionend", "provider-down", event_time,
            )
        )
        queue = FLUSH.STATE_DIR / FLUSH.DEFERRED_DIR_NAME
        self.assertEqual(len(list(queue.glob("*.json"))), 1)

        with mock.patch.object(FLUSH, "_run_summary", return_value=(SUMMARY, None, "codex")):
            status, _ = FLUSH._flush_once(args, event_time)

        self.assertEqual(status, "appended")
        self.assertEqual(list(queue.glob("*.json")), [])

    def short_args_for(self, reason, session_id):
        """Minimum tur eşiğinin altında kalan tek turluk bir oturum kur."""
        transcript = self.root / f"short-{session_id}.jsonl"
        transcript.write_text(
            json.dumps({"role": "user", "content": "Tek tur"}) + "\n",
            encoding="utf-8",
        )
        hook_input = self.root / f"short-{session_id}-{reason}.json"
        hook_input.write_text(
            json.dumps({"session_id": session_id, "transcript_path": str(transcript)}),
            encoding="utf-8",
        )
        return type("Args", (), {
            "hook_input": hook_input,
            "reason": reason,
            "max_summary_chars": 1200,
            "summary_timeout_seconds": 35,
            "emit_result": True,
        })()

    def test_short_precompact_does_not_swallow_the_following_sessionend(self):
        """5 turun altındaki PreCompact da sonraki SessionEnd'i yutmamalı.

        Bu yol `status: ok` yazar ama özet üretmez. Durum kaydına reason
        yazılmazsa yinelenme kontrolü eski davranışa düşer ve oturumun tamamı
        rapora hiç girmez.
        """
        base = dt.datetime(2026, 9, 3, 12, tzinfo=dt.timezone.utc)
        with mock.patch.object(FLUSH, "_run_summary", return_value=(SUMMARY, None, "codex")):
            first, _ = FLUSH._flush_once(self.short_args_for("precompact", "kisa-oturum"), base)
            second, _ = FLUSH._flush_once(
                self.short_args_for("sessionend", "kisa-oturum"),
                base + dt.timedelta(seconds=5),
            )

        self.assertEqual(first, "below-minimum-turns")
        self.assertEqual(second, "appended", "kısa precompact sonrası oturum kaybolmamalı")

    def load_retry_module(self):
        """retry_deferred_flush'ı testin yamalı flush örneğiyle yükle.

        Kendi `import flush` satırı gerçek vault'a bakan ikinci bir modül
        örneği yaratırdı; sys.modules'a testin örneğini koyarak engelliyoruz.
        """
        previous = sys.modules.get("flush")
        sys.modules["flush"] = FLUSH
        try:
            spec = importlib.util.spec_from_file_location(
                "retry_deferred_test", SCRIPT_DIR / "retry_deferred_flush.py"
            )
            assert spec is not None and spec.loader is not None
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        finally:
            if previous is None:
                sys.modules.pop("flush", None)
            else:
                sys.modules["flush"] = previous
        return module

    def test_retry_skips_a_record_cleared_while_it_was_summarising(self):
        """Özet üretilirken normal flush kaydı sildiyse retry ikinci kez yazmamalı.

        Özetleme dakikalar sürebilir; kayıt okunduktan sonra silinmesi gerçek
        bir yarış durumudur ve korunmazsa aynı oturum rapora iki kez girer.
        """
        retry = self.load_retry_module()
        transcript = self.root / "yaris.jsonl"
        transcript.write_text(
            json.dumps({"role": "user", "content": "Tek tur"}) + "\n",
            encoding="utf-8",
        )
        event_time = dt.datetime(2026, 9, 3, 12, tzinfo=dt.timezone.utc)
        self.assertTrue(
            FLUSH._defer_flush(
                FLUSH.STATE_DIR, "yaris-oturum", transcript,
                "sessionend", "provider-down", event_time,
            )
        )
        record = next((FLUSH.STATE_DIR / FLUSH.DEFERRED_DIR_NAME).glob("*.json"))

        def summarise_then_race(*_args, **_kwargs):
            # Normal flush özetleme sırasında oturumu yazıp kaydı sildi.
            record.unlink()
            return SUMMARY, None, "codex"

        with mock.patch.object(FLUSH, "_run_summary", side_effect=summarise_then_race), \
                mock.patch.object(FLUSH, "_append_daily") as append:
            result = retry._retry_one(record, dry_run=False)

        self.assertEqual(result, "zaten-islendi")
        append.assert_not_called()

    def test_precompact_prompt_requests_a_bounded_summary(self):
        prompt = FLUSH.build_flush_prompt("kayıt", 1200)

        self.assertIn("1200 karakteri aşmasın", prompt)

    def test_precompact_flush_appends_and_returns_summary(self):
        _, args = self.transcript_and_args()
        with mock.patch.object(FLUSH, "_run_summary", return_value=(SUMMARY, None, "codex")) as run_codex:
            status, summary = FLUSH._flush_once(args, dt.datetime(2026, 9, 3, 12, tzinfo=dt.timezone.utc))

        self.assertEqual(status, "appended")
        self.assertEqual(summary, SUMMARY)
        self.assertEqual(run_codex.call_args.args[2], 35)
        daily = FLUSH.VAULT_ROOT / FLUSH.DAILY_REPORTS_RELATIVE / "2026-09-03.md"
        self.assertIn(SUMMARY, daily.read_text(encoding="utf-8"))

    def test_emit_result_is_machine_readable(self):
        _, args = self.transcript_and_args()
        stdout = io.StringIO()
        previous = os.environ.pop("BEYIN_INVOKED_BY", None)
        try:
            with mock.patch.object(FLUSH, "_flush_once", return_value=("appended", SUMMARY)), \
                    contextlib.redirect_stdout(stdout):
                self.assertEqual(FLUSH.main([
                    "--hook-input", str(args.hook_input), "--reason", "precompact", "--emit-result",
                ]), 0)
        finally:
            if previous is not None:
                os.environ["BEYIN_INVOKED_BY"] = previous

        self.assertEqual(json.loads(stdout.getvalue()), {"status": "appended", "summary": SUMMARY})

    def test_hook_injects_successful_summary_as_precompact_context(self):
        vault = self.root / "hook-vault"
        shutil.copytree(SCRIPT_DIR.parent, vault / ".beyin" / "engine", ignore=shutil.ignore_patterns(".state"))
        shim_dir = self.root / "bin"
        shim_dir.mkdir()
        shim = shim_dir / "python3"
        result = json.dumps({"status": "appended", "summary": SUMMARY}, ensure_ascii=False)
        shim.write_text(
            "#!/bin/sh\n"
            "case \"$1\" in\n"
            "  */flush.py) printf '%s\\n' '" + result.replace("'", "'\\\"'\\\"'") + "'; exit 0 ;;\n"
            "esac\n"
            "exec \"$REAL_PYTHON\" \"$@\"\n",
            encoding="utf-8",
        )
        shim.chmod(0o755)
        environment = dict(os.environ)
        environment.pop("BEYIN_INVOKED_BY", None)
        environment["PATH"] = f"{shim_dir}:{environment['PATH']}"
        environment["REAL_PYTHON"] = sys.executable

        completed = subprocess.run(
            ["bash", str(vault / ".beyin" / "engine" / "hooks" / "pre-compact.sh")],
            input=json.dumps({"session_id": "hook-test"}),
            text=True,
            capture_output=True,
            check=True,
            env=environment,
        )

        payload = json.loads(completed.stdout)
        context = payload["hookSpecificOutput"]["additionalContext"]
        self.assertEqual(payload["hookSpecificOutput"]["hookEventName"], "PreCompact")
        self.assertIn("Compaction Öncesi Devam Özeti", context)
        self.assertIn("Yapılacaklar", context)


if __name__ == "__main__":
    unittest.main()
