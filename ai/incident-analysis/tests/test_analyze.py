import json, os, subprocess, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import analyze

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class AnalyzeTests(unittest.TestCase):
    def test_healthy_logs_report_no_incident(self):
        ev = [analyze.parse_line(json.dumps({"level": "info", "message": "request"}))]
        self.assertEqual(analyze.rules_engine(ev)["status"], "healthy")

    def test_db_timeout_classified_and_escalated(self):
        ev = [analyze.parse_line(json.dumps({"level": "error", "message": f"db timeout ETIMEDOUT {i}"})) for i in range(12)]
        rep = analyze.rules_engine(ev)
        inc = rep["incidents"][0]
        self.assertEqual(inc["category"], "Database / network connectivity")
        self.assertEqual(inc["count"], 12)            # numbers stripped -> grouped as one problem
        self.assertEqual(inc["severity"], "CRITICAL")  # HIGH raised by repetition
        self.assertTrue(inc["remediation"])

    def test_oom_is_critical(self):
        ev = [analyze.parse_line('{"level":"error","message":"JavaScript heap out of memory"}')]
        self.assertEqual(analyze.rules_engine(ev)["incidents"][0]["severity"], "CRITICAL")

    def test_plain_text_lines_detected(self):
        self.assertEqual(analyze.parse_line("2026 FATAL something failed")["level"], "error")

    def test_unknown_error_falls_back_to_default(self):
        ev = [analyze.parse_line('{"level":"error","message":"weird thing"}')]
        self.assertEqual(analyze.rules_engine(ev)["incidents"][0]["category"], "Unclassified application error")

    def test_llm_failure_falls_back_to_rules(self):
        os.environ["OLLAMA_HOST"] = "http://127.0.0.1:9"   # nothing listens here
        ev = [analyze.parse_line('{"level":"error","message":"ETIMEDOUT"}')]
        rep = analyze.analyse(ev, "ollama")
        self.assertIn("fallback", rep["engine"])
        self.assertEqual(rep["status"], "incident")

    def test_cli_on_sample_file_exits_1_and_prints_report(self):
        sample = os.path.join(HERE, "sample_logs", "db_timeout.log")
        script = os.path.join(HERE, "analyze.py")

        p = subprocess.run(
            [sys.executable, script, "--file", sample],
            capture_output=True,
            text=True,
            cwd=HERE,
        )

        self.assertEqual(
            p.returncode, 1,
            f"Expected exit code 1 for an incident.\n"
            f"STDOUT:\n{p.stdout}\nSTDERR:\n{p.stderr}"
        )
        self.assertIn(
            "Database / network connectivity",
            p.stdout,
            f"Expected database incident in report.\nSTDERR:\n{p.stderr}"
        )
        self.assertIn("Resource exhaustion (memory)", p.stdout)


if __name__ == "__main__":
    unittest.main()
