# TRENDY Dashboard (Phase 0 — GPP)

A lightweight, static web dashboard for exploring TRENDY v14/S2 model output —
inspired by the OCO product monitor. No backend: Julia packs the data into a
compact store and a static HTML/JS page renders it client-side.

## Layout
```
dashboard/
  preprocess.jl        # Julia: netCDF -> packed Int16 store + manifest.json
  site/
    index.html         # UI
    app.js             # canvas map + time slider + click-for-timeseries
    style.css
    data/
      manifest.json    # grid, time axis, packing, model list
      gpp/<MODEL>.bin  # Int16 [time,lat,lon], lon-fastest (little-endian)
```

## Build the data
From the package root:
```bash
julia --project=. dashboard/preprocess.jl            # all models
MODELS=CABLE-POP,ORCHIDEE julia --project=. dashboard/preprocess.jl   # subset
```
This reads the converted ILAMB files under `ilamb_output_v14_S2/<MODEL>/gpp_*.nc`,
selects months 1980-01…2024-12, nearest-neighbour regrids each month to a common
1° grid (360×180), converts to `g C m-2 day-1`, packs to Int16 (scale 0.001),
and writes one `.bin` per model plus `manifest.json`.

Edit the constants at the top of `preprocess.jl` to change variable, grid,
year range, or packing.

## View it
Serve the `site/` directory statically (loopback is fine for a shared node):
```bash
cd dashboard/site && python3 -m http.server 8000 --bind 127.0.0.1
```
then open http://localhost:8000 .

## Features (Phase 0)
- Map of GPP for a selected **model** and **month**, with a time slider + play.
- Click any land cell → **monthly time series** at that location for the model.
- Viridis colormap with a fixed display range (`vmin`/`vmax` in the manifest).

## Roadmap
- Phase 1: ensemble mean/spread, model−ensemble difference, all ILAMB variables.
- Phase 2: migrate the store to Zarr (chunked, cloud-native), host on GitHub Pages,
  link cells to their ILAMB scores.
