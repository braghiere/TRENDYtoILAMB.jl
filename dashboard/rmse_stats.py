#!/usr/bin/env python
"""Extract per-model RMSE vs observations for the carbon-flux confrontations from
the ILAMB scalar_database.csv, for the dashboard's RMSE box plot.

Writes data/rmse.json:
  {"units": "g C m-2 day-1",
   "vars": [{"key","label","source","models":[{"m":<model>,"r":<rmse>}, ...]}, ...]}

Run after ilamb-run completes:  python dashboard/rmse_stats.py
"""
import json, os, pandas as pd

SCALARS = "/home/renatob/data/ilamb_run_v14_full_v2/scalar_database.csv"
OUT     = "/home/renatob/TRENDYtoILAMB.jl/dashboard/site/data/rmse.json"

# carbon-flux confrontations that have an observational product, and the obs to use
FLUXES = [("GrossPrimaryProductivity", "gpp",  "GPP",  "FLUXCOM"),
          ("EcosystemRespiration",     "reco", "RECO", "FLUXCOM"),
          ("NetEcosystemExchange",     "nee",  "NEE",  "FLUXCOM")]

df = pd.read_csv(SCALARS)
r = df[(df.ScalarName == "RMSE") & (df.Region == "global")]

out = {"units": "g C m-2 day-1", "vars": []}
for var, key, label, source in FLUXES:
    sub = r[(r.Variable == var) & (r.Source == source)]
    models = [{"m": m, "r": round(float(v), 4)}
              for m, v in sub[["Model", "Data"]].itertuples(index=False)
              if pd.notna(v) and m != "TRENDY-ENSEMBLE"]   # individual models only
    models.sort(key=lambda d: d["r"])
    out["vars"].append({"key": key, "label": label, "source": source, "models": models})
    ens = next((d["r"] for d in models if d["m"] == "TRENDY-ENSEMBLE"), None)
    print(f"{label:5} vs {source}: {len(models)} models, RMSE "
          f"{models[0]['r']:.3g}..{models[-1]['r']:.3g}"
          + (f", ensemble={ens:.3g}" if ens is not None else " (no ensemble yet)"))

json.dump(out, open(OUT, "w"))
print("wrote", OUT)
