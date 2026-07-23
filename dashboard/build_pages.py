#!/usr/bin/env python
"""Build a GitHub-Pages-sized ANNUAL version of the dashboard data.

Averages the monthly packed bins (nt=540, 1980-2024) into annual means
(nt=45), re-packs to Int16, and gzips each bin (.bin.gz) so the whole store
fits well under the GitHub Pages ~1 GB limit. Also writes an annual manifest
(cadence=annual) and an annual globalmeans.json; copies obs/rmse json.

Output tree (ready to be the Pages repo root's data/):
  <OUT>/data/<var>/<model>.bin.gz , manifest.json, globalmeans.json, obs.json, rmse.json
"""
import json, os, gzip, shutil, numpy as np

SRC = "/home/renatob/TRENDYtoILAMB.jl/dashboard/site/data"
OUT = "/home/renatob/data/trendy_pages_build/data"
os.makedirs(OUT, exist_ok=True)

man = json.load(open(f"{SRC}/manifest.json"))
nt, nlat, nlon, fill = man["nt"], man["nlat"], man["nlon"], man["fill"]
years = sorted({t[:4] for t in man["times"]})
ny = len(years)
assert nt == ny * 12, f"expected whole years, got nt={nt}, ny={ny}"

def annual_bin(path):
    a = np.fromfile(path, dtype="<i2").astype(np.float32).reshape(ny, 12, nlat, nlon)
    a = np.where(a == fill, np.nan, a)
    m = np.nanmean(a, axis=1)                          # (ny, nlat, nlon), NaN if whole year missing
    q = np.where(np.isnan(m), fill, np.clip(np.round(m), -32000, 32000)).astype("<i2")
    return q.tobytes()

nbin = 0
for v in os.listdir(SRC):
    d = f"{SRC}/{v}"
    if not os.path.isdir(d): continue
    os.makedirs(f"{OUT}/{v}", exist_ok=True)
    for fn in os.listdir(d):
        if not fn.endswith(".bin"): continue
        with gzip.open(f"{OUT}/{v}/{fn}.gz", "wb", compresslevel=6) as g:
            g.write(annual_bin(f"{d}/{fn}"))
        nbin += 1

# annual manifest
man_out = dict(man)
man_out["nt"] = ny
man_out["times"] = years
man_out["cadence"] = "annual"
man_out["binext"] = ".bin.gz"
json.dump(man_out, open(f"{OUT}/manifest.json", "w"))

# annual globalmeans (mean of the 12 months in each year; null-safe)
gm = json.load(open(f"{SRC}/globalmeans.json"))
gm_out = {}
for var, series in gm.items():
    gm_out[var] = {}
    for model, s in series.items():
        arr = np.array([np.nan if x is None else x for x in s], dtype=float)
        if arr.size != nt:                              # already annual or odd length: keep as-is
            gm_out[var][model] = s; continue
        ya = np.nanmean(arr.reshape(ny, 12), axis=1)
        gm_out[var][model] = [None if not np.isfinite(x) else round(float(x), 4) for x in ya]
json.dump(gm_out, open(f"{OUT}/globalmeans.json", "w"))

for j in ("obs.json", "rmse.json"):
    if os.path.exists(f"{SRC}/{j}"): shutil.copy(f"{SRC}/{j}", f"{OUT}/{j}")

sz = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(OUT) for f in fs)
print(f"annual build: {nbin} gzipped bins, {ny} years, total data = {sz/1048576:.0f} MB -> {OUT}")
