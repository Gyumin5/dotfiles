#!/usr/bin/env python3
"""Analyze lean-ctx A/B results — paired, pre-registered decision rule.

Reads results.jsonl. Per task, takes the median over reps for each arm, pairs
native vs lean-ctx, and computes:
  - token & cost savings (paired delta, % ), median + bootstrap 95% CI
  - Wilcoxon signed-rank p-value (pure python, no scipy)
  - correctness per arm (lean-ctx must not be meaningfully worse)
  - per-domain breakdown
  - verdict against the pre-registered rule

Pre-registered decision rule (set BEFORE seeing results):
  KEEP (opt-in justified): median net token savings >= 25% AND
        correctness drop <= 2 percentage points AND zero unexpected egress
  DROP: median savings <= 10% OR correctness meaningfully worse
  GRAY (10-25%): keep only if C++/large-file domain benefits AND correctness equal
"""
import json, sys, math, statistics as st
from collections import defaultdict

RESULTS = sys.argv[1] if len(sys.argv) > 1 else "/tmp/bench/results.jsonl"

def total_tokens(r):   # all billed input + output
    return (r.get("input_tokens",0) + r.get("cache_creation",0)
            + r.get("cache_read",0) + r.get("output_tokens",0))

def work_tokens(r):    # excludes cheap cache_read (marginal new work)
    return r.get("input_tokens",0) + r.get("cache_creation",0) + r.get("output_tokens",0)

def median(xs):
    return st.median(xs) if xs else float("nan")

def bootstrap_ci(deltas, iters=5000, alpha=0.05):
    # deterministic bootstrap (LCG) so result is reproducible without scipy/np
    if not deltas:
        return (float("nan"), float("nan"))
    n = len(deltas); seed = 12345; meds = []
    for _ in range(iters):
        samp = []
        for _ in range(n):
            seed = (1103515245*seed + 12345) & 0x7fffffff
            samp.append(deltas[seed % n])
        meds.append(median(samp))
    meds.sort()
    lo = meds[int((alpha/2)*iters)]
    hi = meds[int((1-alpha/2)*iters)-1]
    return (lo, hi)

def wilcoxon_p(deltas):
    # signed-rank, normal approximation with continuity correction; ignores zeros
    d = [x for x in deltas if x != 0]
    n = len(d)
    if n < 6:
        return float("nan")
    order = sorted(range(n), key=lambda i: abs(d[i]))
    ranks = [0.0]*n; i = 0
    while i < n:
        j = i
        while j+1 < n and abs(d[order[j+1]]) == abs(d[order[i]]):
            j += 1
        avg = (i+1 + j+1)/2.0
        for k in range(i, j+1):
            ranks[order[k]] = avg
        i = j+1
    Wp = sum(ranks[i] for i in range(n) if d[i] > 0)
    Wm = sum(ranks[i] for i in range(n) if d[i] < 0)
    W = min(Wp, Wm)
    mu = n*(n+1)/4.0
    sigma = math.sqrt(n*(n+1)*(2*n+1)/24.0)
    if sigma == 0:
        return float("nan")
    z = (W - mu + 0.5)/sigma
    return 2*(0.5*math.erfc(abs(z)/math.sqrt(2)))

def main():
    rows = []
    with open(RESULTS) as f:
        for line in f:
            line=line.strip()
            if line:
                rows.append(json.loads(line))

    # per (id, arm): median over reps; correctness = mean correct over reps
    by = defaultdict(list)
    for r in rows:
        if r.get("ok"):
            by[(r["id"], r["arm"])].append(r)

    ids = sorted({r["id"] for r in rows})
    domain = {r["id"]: r["domain"] for r in rows}

    per_task = {}
    for tid in ids:
        nat = by.get((tid,"native"), []); lean = by.get((tid,"leanctx"), [])
        if not nat or not lean:
            continue
        def agg(g):
            return {
                "cost":   median([x["cost_usd"] for x in g if x.get("cost_usd") is not None]),
                "ttok":   median([total_tokens(x) for x in g]),
                "wtok":   median([work_tokens(x) for x in g]),
                "correct":st.mean([1.0 if x.get("correct") else 0.0 for x in g]),
                "turns":  median([x.get("num_turns") or 0 for x in g]),
                "dur":    median([x.get("dur") or 0 for x in g]),
                "n": len(g),
            }
        per_task[tid] = {"native": agg(nat), "leanctx": agg(lean), "domain": domain[tid]}

    if not per_task:
        print("No paired tasks yet."); return

    def savings_pct(tid, key):
        nv = per_task[tid]["native"][key]; lv = per_task[tid]["leanctx"][key]
        if nv in (0, None) or nv != nv:
            return None
        return 100.0*(nv - lv)/nv   # positive = lean-ctx cheaper

    print(f"=== lean-ctx A/B  ({len(per_task)} paired tasks) ===\n")
    hdr = f"{'task':28} {'dom':11} {'nat$':>8} {'lean$':>8} {'save%':>7} {'natTok':>8} {'leanTok':>8} {'nC':>4} {'lC':>4}"
    print(hdr); print("-"*len(hdr))
    for tid in sorted(per_task):
        p = per_task[tid]
        sp = savings_pct(tid,"ttok")
        print(f"{tid:28.28} {p['domain']:11.11} {p['native']['cost']:8.4f} {p['leanctx']['cost']:8.4f} "
              f"{(sp if sp is not None else float('nan')):7.1f} {p['native']['ttok']:8.0f} {p['leanctx']['ttok']:8.0f} "
              f"{p['native']['correct']:4.2f} {p['leanctx']['correct']:4.2f}")

    tok_deltas  = [savings_pct(t,"ttok") for t in per_task if savings_pct(t,"ttok") is not None]
    cost_deltas = [savings_pct(t,"cost") for t in per_task if savings_pct(t,"cost") is not None]
    work_deltas = [savings_pct(t,"wtok") for t in per_task if savings_pct(t,"wtok") is not None]

    nat_corr  = st.mean([per_task[t]["native"]["correct"]  for t in per_task])
    lean_corr = st.mean([per_task[t]["leanctx"]["correct"] for t in per_task])

    med_tok = median(tok_deltas); ci = bootstrap_ci(tok_deltas); p_w = wilcoxon_p(tok_deltas)

    print("\n=== summary (positive % = lean-ctx cheaper) ===")
    print(f"total-token savings : median {med_tok:.1f}%  95%CI [{ci[0]:.1f}, {ci[1]:.1f}]  Wilcoxon p={p_w:.4f}")
    print(f"cost($) savings     : median {median(cost_deltas):.1f}%")
    print(f"work-token savings  : median {median(work_deltas):.1f}%  (excludes cheap cache_read)")
    print(f"correctness         : native {nat_corr*100:.1f}%   lean-ctx {lean_corr*100:.1f}%   "
          f"(delta {(lean_corr-nat_corr)*100:+.1f} pp)")

    print("\n=== per-domain median total-token savings ===")
    dom_map = defaultdict(list)
    for t in per_task:
        sp = savings_pct(t,"ttok")
        if sp is not None:
            dom_map[per_task[t]["domain"]].append(sp)
    for d in sorted(dom_map):
        print(f"  {d:12} {median(dom_map[d]):6.1f}%   (n={len(dom_map[d])})")

    print("\n=== verdict (pre-registered) ===")
    corr_drop_pp = (nat_corr - lean_corr)*100
    if corr_drop_pp > 2:
        print(f"DROP — lean-ctx correctness worse by {corr_drop_pp:.1f}pp (rule: <=2pp).")
    elif med_tok >= 25:
        print(f"KEEP (opt-in) — median token savings {med_tok:.1f}% >= 25%, correctness ok. "
              f"(network audit must also be clean.)")
    elif med_tok <= 10:
        print(f"DROP — median token savings {med_tok:.1f}% <= 10%; not worth the trust surface.")
    else:
        cpp = median(dom_map.get("large_file", []))
        print(f"GRAY ({med_tok:.1f}%) — keep only if large_file domain benefits & correctness equal. "
              f"large_file median savings = {cpp:.1f}%, correctness delta {(lean_corr-nat_corr)*100:+.1f}pp.")
    print("\n(Token/cost = Anthropic usage block. Correctness = vs mechanically-computed oracle.)")

if __name__ == "__main__":
    main()
