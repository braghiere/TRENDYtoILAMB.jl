#!/usr/bin/env python
"""Derive ecosystem respiration reco = ra + rh for the dashboard, from the packed
ra/rh bins produced by preprocess.jl. Writes data/reco/<model>.bin (+ ENSEMBLE
mean/std), inserts a `reco` entry into manifest.json (after rh), and adds reco
global totals (Pg C yr-1) to globalmeans.json.

Run AFTER preprocess.jl + globalstats.jl:  python dashboard/derive_reco.py
"""
import json, os, numpy as np
BASE = "/home/renatob/TRENDYtoILAMB.jl/dashboard/site/data"
R = 6.371e6

man = json.load(open(f"{BASE}/manifest.json"))
nt, nlat, nlon, fill = man["nt"], man["nlat"], man["nlon"], man["fill"]
vmeta = {v["name"]: v for v in man["variables"]}
sc_ra, sc_rh = vmeta["ra"]["scale"], vmeta["rh"]["scale"]
SC_RECO = 0.001                                    # same precision as ra/rh
lat = np.array(man["lat"])
dlat = abs(lat[1] - lat[0]); dlon = 2*np.pi/nlon
A = R*R*dlon*(np.sin(np.deg2rad(lat+dlat/2)) - np.sin(np.deg2rad(lat-dlat/2)))  # m2 per cell

os.makedirs(f"{BASE}/reco", exist_ok=True)

def load(var, m, scale):
    p = f"{BASE}/{var}/{m}.bin"
    if not os.path.exists(p): return None
    a = np.fromfile(p, dtype="<i2").reshape(nt, nlat, nlon)
    return np.where(a == fill, np.nan, a.astype(np.float32) * scale)   # g C m-2 day-1

def packwrite(m, field):
    q = np.where(np.isnan(field), fill,
                 np.clip(np.round(field/SC_RECO), -32000, 32000)).astype("<i2")
    q.tofile(f"{BASE}/reco/{m}.bin")

def flux_total(field):    # g C m-2 day-1 -> Pg C yr-1 per timestep
    out = np.full(nt, np.nan)
    for t in range(nt):
        f = field[t]; msk = np.isfinite(f)
        if msk.any(): out[t] = (f[msk] * np.broadcast_to(A[:,None], f.shape)[msk]).sum()*365*1e-15
    return out

models = [m for m in man["models"] if not m.startswith("ENSEMBLE")]
gm = json.load(open(f"{BASE}/globalmeans.json"))
gm["reco"] = {}
esum = np.zeros((nt,nlat,nlon)); esq = np.zeros((nt,nlat,nlon)); ecnt = np.zeros((nt,nlat,nlon),np.int32)
built = 0
for m in models:
    ra = load("ra", m, sc_ra); rh = load("rh", m, sc_rh)
    if ra is None or rh is None:            # missing a component -> all-fill layer (no 404)
        packwrite(m, np.full((nt,nlat,nlon), np.nan))
        gm["reco"][m] = [None]*nt
        continue
    reco = ra + rh                          # NaN where either is NaN
    packwrite(m, reco)
    gm["reco"][m] = [None if not np.isfinite(x) else round(float(x),4) for x in flux_total(reco)]
    val = np.isfinite(reco); esum[val]+=reco[val]; esq[val]+=reco[val]**2; ecnt[val]+=1
    built += 1

mean = np.where(ecnt>=2, esum/np.maximum(ecnt,1), np.nan)
std  = np.where(ecnt>=2, np.sqrt(np.maximum(0, esq/np.maximum(ecnt,1) - (esum/np.maximum(ecnt,1))**2)), np.nan)
packwrite("ENSEMBLE-mean", mean); packwrite("ENSEMBLE-std", std)
gm["reco"]["ENSEMBLE-mean"] = [None if not np.isfinite(x) else round(float(x),4) for x in flux_total(mean)]
gm["reco"]["ENSEMBLE-std"]  = [None if not np.isfinite(x) else round(float(x),4) for x in flux_total(std)]

# insert reco into manifest.variables right after rh
recometa = {"name":"reco","units":"g C m-2 day-1","scale":SC_RECO,"vmin":0.0,"vmax":12.0,"diverging":False}
names = [v["name"] for v in man["variables"]]
if "reco" not in names:
    i = names.index("rh")+1 if "rh" in names else len(man["variables"])
    man["variables"].insert(i, recometa)
json.dump(man, open(f"{BASE}/manifest.json","w"))
json.dump(gm, open(f"{BASE}/globalmeans.json","w"))
em = np.nanmean(gm["reco"]["ENSEMBLE-mean"])
print(f"reco built for {built} models; ensemble mean total = {em:.1f} Pg C yr-1")
