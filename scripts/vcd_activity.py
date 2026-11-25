#!/usr/bin/env python3
"""VCD switching-activity summary. Usage: vcd_activity.py file.vcd [--top 25]"""
import argparse, collections, re

UNIT = {"s": 1e9, "ms": 1e6, "us": 1e3, "ns": 1.0, "ps": 1e-3, "fs": 1e-6}

def norm(v, w):
    v = v.lower().replace("x", "0").replace("z", "0")
    return v.rjust(w, "0")[-w:]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vcd")
    ap.add_argument("--top", type=int, default=25)
    a = ap.parse_args()

    head, _, body = open(a.vcd).read().partition("$enddefinitions")
    ht = head.split()
    scope, entries, ns_per_unit = [], [], 1.0
    i = 0
    while i < len(ht):
        t = ht[i]
        if t == "$timescale":
            j = i + 1; parts = []
            while ht[j] != "$end": parts.append(ht[j]); j += 1
            m = re.match(r"(\d+)([a-z]+)", "".join(parts))
            ns_per_unit = int(m.group(1)) * UNIT[m.group(2)]
            i = j
        elif t == "$scope":
            scope.append(ht[i + 2]); i += 2
        elif t == "$upscope":
            if scope: scope.pop()
        elif t == "$var":
            entries.append((".".join(scope), ht[i + 4], int(ht[i + 2]), ht[i + 3]))
        i += 1

    width = {}
    for sc, n, w, v in entries: width[v] = max(width.get(v, 0), w)
    last, tc, tmax = {}, collections.Counter(), 0
    bt = body.split(); k = 0
    while k < len(bt):
        t = bt[k]; c = t[0]
        if c == "#":   tmax = int(t[1:]); k += 1; continue
        if c in "bB":  val, vid = t[1:], bt[k + 1]; k += 2
        elif c in "rR": k += 2; continue
        elif c == "$": k += 1; continue
        else:          val, vid = c, t[1:]; k += 1
        w = width.get(vid)
        if w is None: continue
        val = norm(val, w)
        prev = last.get(vid)
        if prev is not None and prev != val:
            tc[vid] += sum(1 for x, y in zip(prev, val) if x != y)
        last[vid] = val

    clk = next((v for sc, n, w, v in entries if n == "clk"), None)
    cycles = max(1, tc[clk] // 2) if clk else max(1, round(tmax * ns_per_unit / 10.0))

    print(f"vcd_end_time_ns,{tmax * ns_per_unit:.1f}")
    print(f"clock_cycles,{cycles}")
    print(f"unique_signals,{len(width)}")
    print(f"unique_bits,{sum(width.values())}")
    print(f"unique_bit_toggles,{sum(tc.values())}")
    print(f"unique_bit_toggles_per_cycle,{sum(tc.values()) / cycles:.3f}")
    print("# NOTE: iverilog does not dump memory arrays (buf_mem/kernel_mem/outq_mem);")
    print("# port aliases share toggles across parent/child scopes, so scope rows do not sum to the total.")
    print()
    print("scope,signals,bits,bit_toggles,toggles_per_cycle,toggles_per_bit_per_cycle")
    sc_acc = collections.defaultdict(lambda: [0, 0, 0])
    for sc, n, w, v in entries:
        s = sc_acc[sc]; s[0] += 1; s[1] += w; s[2] += tc[v]
    for sc in sorted(sc_acc):
        s, b, t = sc_acc[sc]
        print(f"{sc},{s},{b},{t},{t / cycles:.3f},{t / cycles / max(b, 1):.4f}")
    print()
    print(f"# top {a.top} most active signals")
    print("signal,width,bit_toggles,toggles_per_cycle")
    for sc, n, w, v in sorted(entries, key=lambda e: -tc[e[3]])[:a.top]:
        print(f"{sc}.{n},{w},{tc[v]},{tc[v] / cycles:.3f}")

if __name__ == "__main__":
    main()