#!/usr/bin/env python
"""Build a Pages-sized ANNUAL version of the dashboard data, one store per scenario.

For each scenario (S2, S3) found under SRC_ROOT/<scen>, averages the monthly
packed bins (nt=540, 1980-2024) into annual means (nt=45), re-packs to Int16,
and gzips each bin (.bin.gz) so the whole store fits well under the Pages ~1 GB
limit. Writes an annual manifest (cadence=annual, binext=.bin.gz) + annual
globalmeans.json, and copies obs/rmse json.

The dashboard computes the S3-S2 land-use difference client-side from the two
scenario stores, so only S2 and S3 need to be built here.

Output tree (Pages build root's data/):
  <OUT_ROOT>/<scen>/<var>/<model>.bin.gz , manifest.json, globalmeans.json, obs.json, rmse.json
"""
import json, os, gzip, shutil, numpy as np

SRC_ROOT  = "/home/renatob/TRENDYtoILAMB.jl/dashboard/site/data"   # has S2/ and S3/ subdirs
OUT_ROOT  = "/home/renatob/data/trendy_pages_build/data"
SCENARIOS = ["S2", "S3"]

def build(src, out):
    os.makedirs(out, exist_ok=True)
    man = json.load(open(f"{src}/manifest.json"))
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
    for v in os.listdir(src):
        d = f"{src}/{v}"
        if not os.path.isdir(d): continue
        os.makedirs(f"{out}/{v}", exist_ok=True)
        for fn in os.listdir(d):
            if not fn.endswith(".bin"): continue
            with gzip.open(f"{out}/{v}/{fn}.gz", "wb", compresslevel=6) as g:
                g.write(annual_bin(f"{d}/{fn}"))
            nbin += 1

    man_out = dict(man)
    man_out["nt"] = ny; man_out["times"] = years
    man_out["cadence"] = "annual"; man_out["binext"] = ".bin.gz"
    json.dump(man_out, open(f"{out}/manifest.json", "w"))

    gm = json.load(open(f"{src}/globalmeans.json"))
    gm_out = {}
    for var, series in gm.items():
        gm_out[var] = {}
        for model, s in series.items():
            arr = np.array([np.nan if x is None else x for x in s], dtype=float)
            if arr.size != nt:                              # already annual or odd length: keep as-is
                gm_out[var][model] = s; continue
            ya = np.nanmean(arr.reshape(ny, 12), axis=1)
            gm_out[var][model] = [None if not np.isfinite(x) else round(float(x), 4) for x in ya]
    json.dump(gm_out, open(f"{out}/globalmeans.json", "w"))

    for j in ("obs.json", "rmse.json"):
        if os.path.exists(f"{src}/{j}"): shutil.copy(f"{src}/{j}", f"{out}/{j}")
    return nbin, ny

total = 0
for scen in SCENARIOS:
    src = f"{SRC_ROOT}/{scen}"
    if not os.path.exists(f"{src}/manifest.json"):
        print(f"skip {scen}: no manifest at {src}"); continue
    if os.path.isdir(f"{OUT_ROOT}/{scen}"):
        shutil.rmtree(f"{OUT_ROOT}/{scen}")                 # clean stale build for this scenario
    nbin, ny = build(src, f"{OUT_ROOT}/{scen}")
    print(f"[{scen}] {nbin} gzipped bins, {ny} years")
    total += nbin

sz = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(OUT_ROOT) for f in fs)
print(f"annual build: {total} bins across {SCENARIOS}, total = {sz/1048576:.0f} MB -> {OUT_ROOT}")
