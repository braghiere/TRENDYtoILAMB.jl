#!/usr/bin/env python
"""Compute observational reference global aggregates for the dashboard's model
intercomparison panel, from the ILAMB-Data benchmark files.
  - gpp (FLUXCOM, WECANN): global total Pg C yr-1
  - et  (GLEAMv3.3a)     : area-weighted mean mm day-1
  - lai (AVHRR)          : area-weighted mean m2 m-2
Plus literature references for nbp (GCB residual sink) and cVeg (biomass obs).
Writes dashboard/site/data/obs.json : {var:[{name,value,std}, ...]}
"""
import json, os, numpy as np
from netCDF4 import Dataset
DATA = "/home/renatob/data/ILAMB-Data/DATA"
OUT  = "/home/renatob/data/trendy_dashboard_data/obs.json"
R = 6.371e6

def cellarea(lat, nlon):
    dlat = abs(lat[1]-lat[0]); dlon = 2*np.pi/nlon
    return R*R*dlon*(np.sin(np.deg2rad(lat+dlat/2))-np.sin(np.deg2rad(lat-dlat/2)))

def load(path, var):
    ds = Dataset(path)
    v = ds.variables[var]; a = np.ma.masked_invalid(v[:]).astype(float)
    fv = getattr(v, "_FillValue", None); mv = getattr(v, "missing_value", None)
    for x in (fv, mv):
        if x is not None: a = np.ma.masked_equal(a, float(x))
    latn = "lat" if "lat" in ds.variables else "latitude"
    lat = np.array(ds.variables[latn][:]); units = getattr(v, "units", "")
    ds.close(); return a, lat, units

def annual_series(monthly):
    n = (len(monthly)//12)*12
    return monthly[:n].reshape(-1,12).mean(axis=1)

def flux_total(path, var):                       # -> Pg C yr-1, interannual mean/std
    a, lat, units = load(path, var); nlon = a.shape[2]; A = cellarea(lat, nlon)
    conv = 1.0
    if "s" in units and "day" not in units: conv = 86400.0   # per-s -> per-day
    tot = (a*conv*A[None,:,None]).sum(axis=(1,2))*365*1e-15
    ann = annual_series(np.ma.filled(tot, np.nan)); ann = ann[np.isfinite(ann)]
    return float(ann.mean()), float(ann.std())

def area_mean(path, var, conv=1.0):              # -> native mean, interannual mean/std
    a, lat, _ = load(path, var); nlon = a.shape[2]; A = cellarea(lat, nlon)
    num = (a*conv*A[None,:,None]).sum(axis=(1,2)); den = (np.ones_like(a)*A[None,:,None]*~a.mask).sum(axis=(1,2))
    m = np.ma.filled(num/den, np.nan); ann = annual_series(m); ann = ann[np.isfinite(ann)]
    return float(ann.mean()), float(ann.std())

def pool_total(path, var, tokgC):                # -> Pg C, mean/std over available maps
    a, lat, _ = load(path, var); nlon = a.shape[2]; A = cellarea(lat, nlon)
    tot = (a*tokgC*A[None,:,None]).sum(axis=(1,2))*1e-12
    t = np.ma.filled(tot, np.nan); t = t[np.isfinite(t)]
    return float(t.mean()), float(t.std() if len(t) > 1 else 0.0)

obs = {v:[] for v in ("gpp","reco","et","lai","nbp","cVeg","cSoil","mrro","tas","pr","rsds")}

def add(var, name, fn):
    try:
        m,s = fn(); obs[var].append({"name":name,"value":m,"std":s})
    except Exception as e:
        print(f"  skip {var}/{name}: {e}")

# --- carbon fluxes (Pg C yr-1) ------------------------------------------------
add("gpp","FLUXCOM", lambda: flux_total(f"{DATA}/gpp/FLUXCOM/gpp.nc","gpp"))
# reco (ecosystem respiration = ra+rh) vs FLUXCOM, g m-2 day-1 -> Pg C yr-1
add("reco","FLUXCOM", lambda: flux_total(f"{DATA}/reco/FLUXCOM/reco.nc","reco"))

# --- carbon pools (Pg C) ------------------------------------------------------
# cVeg: XuSaatchi'21 live-woody CARBON density (already carbon, per long_name).
# Like ILAMB (cf-units): Mg C/ha -> kg C/m2 = *0.1 (no C fraction).
add("cVeg","XuSaatchi'21", lambda: pool_total(f"{DATA}/biomass/XuSaatchi2021/XuSaatchi.nc","biomass",0.1))
# cSoil: SoilGrids2 and HWSD2, both kg C m-2 already -> Pg C (tokgC=1)
add("cSoil","SoilGrids2", lambda: pool_total(f"{DATA}/cSoil/SoilGrids2/soilgrids2_cSoil.nc","cSoil",1.0))
add("cSoil","HWSD2",      lambda: pool_total(f"{DATA}/cSoil/HWSD2/cSoilAbove1m_fx_HWSD2_19600101-20220101.nc","cSoilAbove1m",1.0))

# --- hydrology / meteorology (native area-weighted means) ---------------------
add("et","GLEAM",   lambda: area_mean(f"{DATA}/evspsbl/GLEAMv3.3a/et.nc","et",86400.0))       # kg m-2 s-1 -> mm/day
add("lai","MODIS",  lambda: area_mean(f"{DATA}/lai/MODIS/lai_0.5x0.5.nc","lai"))
add("mrro","LORA",  lambda: area_mean(f"{DATA}/mrro/LORA/LORA.nc","mrro",86400.0))             # kg m-2 s-1 -> mm/day
add("tas","CRU4.02",lambda: area_mean(f"{DATA}/tas/CRU4.02/tas.nc","tas"))                     # K
add("pr","GPCCv2018",lambda: area_mean(f"{DATA}/pr/GPCCv2018/pr.nc","pr"))                     # mm/day
add("rsds","CERESed4.2",lambda: area_mean(f"{DATA}/rsds/CERESed4.2/rsds.nc","rsds"))           # W m-2

# --- nbp / net land sink: top-down estimates (Pg C yr-1) ----------------------
# Net land sink 2015-2024 (Braghiere et al. GCB2025 study, top-down panel; values
# read from the paper figure - confirm exact numbers). Inversions = atmospheric
# CO2; O2 = O2/N2 constraint; Residual = via ocean sink.
# NOTE: TRENDY S2 nbp excludes land-use change, so models sit above these net-land
# fluxes (which include LUC); shown for reference, not a like-for-like target.
obs["nbp"].append({"name":"Inversions","value":1.35,"std":0.31})
obs["nbp"].append({"name":"O₂","value":0.82,"std":0.80})
obs["nbp"].append({"name":"Residual","value":1.25,"std":0.62})
# NOTE: models report mrso (total-column soil moisture); the only obs is mrsos
# (surface layer, WangMao) which is not comparable, so no mrso obs is added.
json.dump(obs, open(OUT,"w"))
for k,v in obs.items(): print(k, [f'{o["name"]}={o["value"]:.1f}±{o["std"]:.1f}' for o in v])
print("wrote", OUT)
