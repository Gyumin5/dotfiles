#!/usr/bin/env python3
"""lean-ctx A/B benchmark runner (runs ON raion).

For each task x arm x rep:
  - compute ground-truth answer mechanically (oracle_cmd)
  - run headless claude with isolated HOME (native vs lean-ctx regime)
  - parse the JSON output (usage = real billed tokens, cost, turns)
  - grade the agent's "ANSWER:" line against the oracle
  - append one row to results.jsonl (resumable: skips already-done rows)

Objectivity:
  - token/cost metrics come from Anthropic's usage block, never lean-ctx self-report
  - ground truth computed by deterministic shell, not by me
  - both arms get the identical prompt; only the tool regime differs
"""
import json, os, re, subprocess, sys, time

BENCH      = "/tmp/bench"
TASKS      = os.environ.get("TASKS", os.path.join(os.path.dirname(os.path.abspath(__file__)), "tasks.jsonl"))
RESULTS    = os.environ.get("RESULTS", os.path.join(BENCH, "results.jsonl"))
CLAUDE     = os.environ.get("CLAUDE_BIN", "/home/gmoh/.local/bin/claude")
REPS       = int(os.environ.get("REPS", "3"))
RUN_TIMEOUT= int(os.environ.get("RUN_TIMEOUT", "180"))
MAX_BUDGET = os.environ.get("MAX_BUDGET_USD", "0.80")   # runaway backstop per run
WORKDIR    = os.path.join(BENCH, "work")          # neutral cwd (no project CLAUDE.md)

ARMS = {
    "native":  {"home": os.path.join(BENCH, "home-native"),  "mcp": os.path.join(BENCH, "empty-mcp.json")},
    "leanctx": {"home": os.path.join(BENCH, "home-leanctx"), "mcp": os.path.join(BENCH, "leanctx-mcp.json")},
}

PROMPT_SUFFIX = ("\n\nUse your available tools to inspect the actual files before answering. "
                 "Do not guess. End your reply with exactly one final line of the form:\n"
                 "ANSWER: <value>\n"
                 "Put nothing after that line.")

def sh(cmd, timeout=60):
    try:
        p = subprocess.run(["bash", "-lc", cmd], capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"

def load_done(path):
    done = set()
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                try:
                    r = json.loads(line)
                    done.add((r["id"], r["arm"], r["rep"]))
                except Exception:
                    pass
    return done

def extract_answer(text):
    if not text:
        return ""
    matches = re.findall(r"(?im)^\s*ANSWER:\s*(.+?)\s*$", text)
    if matches:
        return matches[-1].strip()
    # fallback: last non-empty line
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    return lines[-1] if lines else ""

def norm(s):
    return re.sub(r"\s+", " ", str(s).strip()).strip().strip("'\"`")

def grade(match, expected, got):
    e, g = norm(expected), norm(got)
    if not e:
        return None  # invalid oracle
    if match == "numeric":
        ge = re.search(r"-?\d+", e); gg = re.search(r"-?\d+", g)
        return bool(ge and gg and int(ge.group()) == int(gg.group()))
    if match == "path":
        return os.path.basename(e) == os.path.basename(g) or e == g or e in g
    # contains
    return e.lower() in g.lower()

def run_one(task, arm, rep):
    a = ARMS[arm]
    env = dict(os.environ)
    env["HOME"] = a["home"]
    prompt = task["prompt"] + PROMPT_SUFFIX
    cmd = [CLAUDE, "-p", prompt, "--output-format", "json",
           "--max-budget-usd", MAX_BUDGET,
           "--strict-mcp-config", "--mcp-config", a["mcp"]]
    t0 = time.time()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=RUN_TIMEOUT,
                           cwd=WORKDIR, env=env, stdin=subprocess.DEVNULL)
        dur = time.time() - t0
        out = p.stdout
        try:
            j = json.loads(out)
        except Exception:
            return {"ok": False, "err": "json_parse", "raw": out[:500], "stderr": p.stderr[:500], "dur": dur}
        u = j.get("usage", {}) or {}
        result_text = j.get("result", "") or ""
        return {
            "ok": True,
            "result": result_text,
            "answer": extract_answer(result_text),
            "is_error": j.get("is_error", False),
            "num_turns": j.get("num_turns"),
            "cost_usd": j.get("total_cost_usd"),
            "input_tokens": u.get("input_tokens", 0),
            "cache_creation": u.get("cache_creation_input_tokens", 0),
            "cache_read": u.get("cache_read_input_tokens", 0),
            "output_tokens": u.get("output_tokens", 0),
            "dur": dur,
        }
    except subprocess.TimeoutExpired:
        return {"ok": False, "err": "run_timeout", "dur": time.time() - t0}

def main():
    os.makedirs(WORKDIR, exist_ok=True)
    tasks = []
    with open(TASKS) as f:
        for line in f:
            line = line.strip()
            if line:
                tasks.append(json.loads(line))

    # 1) compute + cache ground truth, drop invalid tasks
    valid = []
    for t in tasks:
        rc, out, err = sh(t["oracle_cmd"])
        if rc == 0 and out.strip():
            t["_expected"] = out.strip().splitlines()[0] if t["match"] != "contains" else out.strip()
            valid.append(t)
            print(f"[oracle] {t['id']}: expected={t['_expected'][:60]!r}", flush=True)
        else:
            print(f"[oracle] SKIP {t['id']} (empty/err rc={rc} err={err[:60]})", flush=True)

    done = load_done(RESULTS)
    total = len(valid) * len(ARMS) * REPS
    n = 0
    with open(RESULTS, "a") as rf:
        for t in valid:
            for arm in ARMS:
                for rep in range(1, REPS + 1):
                    n += 1
                    key = (t["id"], arm, rep)
                    if key in done:
                        print(f"[{n}/{total}] skip done {key}", flush=True)
                        continue
                    r = run_one(t, arm, rep)
                    correct = None
                    if r.get("ok"):
                        correct = grade(t["match"], t["_expected"], r.get("answer", ""))
                    row = {
                        "id": t["id"], "domain": t["domain"], "repo": t["repo"],
                        "arm": arm, "rep": rep, "match": t["match"],
                        "expected": t["_expected"], "correct": correct,
                        **r,
                    }
                    rf.write(json.dumps(row, ensure_ascii=False) + "\n")
                    rf.flush()
                    print(f"[{n}/{total}] {t['id']} {arm} r{rep} "
                          f"correct={correct} cost=${r.get('cost_usd')} "
                          f"tok(in/cc/cr/out)={r.get('input_tokens')}/{r.get('cache_creation')}/"
                          f"{r.get('cache_read')}/{r.get('output_tokens')} dur={r.get('dur',0):.0f}s"
                          + ("" if r.get("ok") else f" ERR={r.get('err')}"), flush=True)
    print(f"DONE: {n} runs, results -> {RESULTS}", flush=True)

if __name__ == "__main__":
    main()
