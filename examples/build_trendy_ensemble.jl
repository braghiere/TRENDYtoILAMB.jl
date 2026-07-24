#=
Build a TRENDY multi-model ENSEMBLE pseudo-model for ILAMB.

For each variable, regrid every model's already-converted CF file to a common
0.5deg grid (nearest neighbour), then take the EQUAL-WEIGHT MEAN across models
per cell / per month, keeping the mean only where >= MINMODELS models are
present. This is the SAME rule the web dashboard uses (see dashboard/preprocess.jl,
ensemble mean requires c >= 2), so the ILAMB ensemble row matches the website.

Output: one CF NetCDF per variable in
  <INROOT>/TRENDY-ENSEMBLE/<var>_Lmon_ENSEMBLE-TRENDY_historical_r1i1p1f1_gn_198001-202412.nc
laid out exactly like the individual converted models: var(time,lat,lon),
time_bounds(time,nb), units preserved from source, days-since-1850 noleap.
ilamb-run then reads it as just another model.

Usage: julia --project=. examples/build_trendy_ensemble.jl
       VARS=gpp,nbp julia --project=. examples/build_trendy_ensemble.jl
=#

using NCDatasets
using Printf

const INROOT   = get(ENV, "GM_INROOT", "/home/renatob/data/ilamb_output_v14_S2")
const OUTMODEL = "TRENDY-ENSEMBLE"
const Y0, Y1   = 1980, 2024
const NLON, NLAT = 720, 360               # 0.5 deg
const MINMODELS  = 2                        # matches dashboard (c >= 2)
const FILL       = Float32(-99999.0)

# variables to build: everything >=10 models provide (drops 1-model mislabels
# nee/evspsbl/hfls). Ordered flux -> pool -> hydro/met.
const VARS = ["gpp","npp","nbp","ra","rh","fFire",
              "cVeg","cSoil","cLitter","cProduct","burntArea",
              "lai","et","tran","mrro","mrso","pr","tas","rsds"]
# model/var combos to exclude from the ensemble (matches dashboard preprocess.jl):
# VISIT-UT tas has been corrected (+546.30 K) so it now rejoins; ED pr is ~12x too
# low (bad scaling, no clean factor) and its file is excluded from the benchmark.
const BADENS = Dict("pr" => ["ED"])

const tlon = collect(-179.75:0.5:179.75)
const tlat = collect(-89.75:0.5:89.75)
const months = [(y,m) for y in Y0:Y1 for m in 1:12]
const NT = length(months)
const midx = Dict((y,m) => i for (i,(y,m)) in enumerate(months))
const MLEN = (31,28,31,30,31,30,31,31,30,31,30,31)

decode_day(day::Real) = begin
    d = floor(Int, day); y = 1850 + fld(d, 365); r = d - (y-1850)*365; m = 1
    while m <= 12 && r >= MLEN[m]; r -= MLEN[m]; m += 1; end
    (y, min(m, 12))
end

function nn_index(src, tgt)
    idx = Vector{Int}(undef, length(tgt))
    for (k,t) in enumerate(tgt)
        j = searchsortedfirst(src, t)
        idx[k] = j <= 1 ? 1 : j > length(src) ? length(src) :
                 (abs(src[j]-t) < abs(src[j-1]-t) ? j : j-1)
    end
    idx
end

# regrid one model's variable to Float32 [NT,NLAT,NLON] (NaN where missing)
function regrid_model(model, var)
    d = joinpath(INROOT, model)
    isdir(d) || return nothing
    fs = filter(f -> startswith(basename(f), "$(var)_"), readdir(d, join=true))
    isempty(fs) && return nothing
    ds = NCDataset(fs[1])
    try
        latn = haskey(ds,"lat") ? "lat" : "latitude"
        lonn = haskey(ds,"lon") ? "lon" : "longitude"
        lat = Float64.(ds[latn][:]); lon = Float64.(ds[lonn][:])
        tvals = Float64.(ds["time"].var[:]); ym = decode_day.(tvals)
        keep = findall(t -> Y0 <= t[1] <= Y1, ym); isempty(keep) && return nothing
        lon = map(x -> x >= 180 ? x-360 : x, lon)
        lop = sortperm(lon); lap = sortperm(lat)
        ix = nn_index(lon[lop], tlon); iy = nn_index(lat[lap], tlat)
        v = ds[var]; dn = dimnames(v)
        td   = findfirst(==("time"), dn)
        fillv = get(v.attrib, "_FillValue", nothing)
        # collapse any extra (e.g. singleton soil layer) dim: CABLE-POP mrso is
        # (time,soil,lat,lon). Select layer 1 so the block is 3-D (time,lat,lon).
        isspatial(d) = d in ("time","lat","latitude","lon","longitude")
        extra = findall(d -> !isspatial(d), dn)
        kf, kl = first(keep), last(keep)
        selb = Any[Colon() for _ in dn]; selb[td] = kf:kl
        for e in extra; selb[e] = 1; end
        block = Array{Union{Missing,Float32}}(v[selb...])
        remdims = dn[[i for i in 1:length(dn) if !(i in extra)]]
        td   = findfirst(==("time"), remdims)
        latd = findfirst(x -> x in ("lat","latitude"), remdims)
        lond = findfirst(x -> x in ("lon","longitude"), remdims)
        out = fill(Float32(NaN), NT, NLAT, NLON)
        # annual (pool) vars carry ~1 step/year -> replicate to all 12 months.
        yrs = [ym[t][1] for t in keep]
        isannual = length(keep) <= round(Int, 1.5*length(unique(yrs)))
        for t in keep
            bi = t - kf + 1; s2 = Any[Colon(),Colon(),Colon()]; s2[td] = bi
            raw = block[s2...]
            slice = (latd < lond ? raw : permutedims(raw,(2,1)))[lap, lop]
            (y, mo) = ym[t]
            targets = isannual ? [midx[(y,mm)] for mm in 1:12 if haskey(midx,(y,mm))] :
                                 [midx[(y,mo)]]
            @inbounds for j in 1:NLAT, i in 1:NLON
                x = slice[iy[j], ix[i]]
                (x === missing || isnan(x)) && continue
                (fillv isa Number && x == fillv) && continue
                (x == -9999 || x == -99999) && continue
                for oi in targets; out[oi,j,i] = Float32(x); end
            end
        end
        return out
    finally
        close(ds)
    end
end

# grab units / long_name / _FillValue from the first model that has the var
function var_attrs(var, models)
    for m in models
        d = joinpath(INROOT, m)
        fs = isdir(d) ? filter(f -> startswith(basename(f), "$(var)_"), readdir(d, join=true)) : String[]
        isempty(fs) && continue
        ds = NCDataset(fs[1])
        try
            a = ds[var].attrib
            return (get(a,"units","1"), get(a,"long_name",var))
        finally close(ds) end
    end
    ("1", var)
end

function write_var(var, emean, units, longname)
    outdir = joinpath(INROOT, OUTMODEL); mkpath(outdir)
    fn = "$(var)_Lmon_ENSEMBLE-TRENDY_historical_r1i1p1f1_gn_$(Y0)01-$(Y1)12.nc"
    path = joinpath(outdir, fn)
    isfile(path) && rm(path)
    # time axis: days since 1850-01-01 (noleap), monthly midpoints + bounds
    days = Vector{Float64}(undef, NT); tb = zeros(Float64, 2, NT)
    for (i,(y,mo)) in enumerate(months)
        s = (y-1850)*365 + sum(MLEN[1:mo-1]; init=0); e = s + MLEN[mo]
        tb[1,i] = s; tb[2,i] = e; days[i] = (s+e)/2
    end
    ds = NCDataset(path, "c")
    try
        defDim(ds,"lat",NLAT); defDim(ds,"lon",NLON); defDim(ds,"time",NT); defDim(ds,"nb",2)
        defVar(ds,"time",days,("time",),
               attrib=Dict("units"=>"days since 1850-01-01","calendar"=>"noleap","bounds"=>"time_bounds"))
        # NCDatasets reverses dims on write: pass (nb,time) -> file time_bounds(time,nb)
        defVar(ds,"time_bounds",tb,("nb","time"))
        defVar(ds,"lat",tlat,("lat",),attrib=Dict("units"=>"degrees_north"))
        defVar(ds,"lon",tlon,("lon",),attrib=Dict("units"=>"degrees_east"))
        # emean is [NT,NLAT,NLON]; pass permuted (lon,lat,time) so file is (time,lat,lon)
        data = permutedims(emean,(3,2,1))
        defVar(ds,var,data,("lon","lat","time"),
               attrib=Dict("units"=>units,"long_name"=>longname,"_FillValue"=>FILL),
               shuffle=true, deflatelevel=4)
        ds.attrib["title"] = "TRENDY v14 S2 multi-model ensemble mean (>=$(MINMODELS) models)"
        ds.attrib["source"] = "Equal-weight mean across TRENDY v14/S2 models, 0.5deg NN regrid"
    finally close(ds) end
    path
end

function main()
    vars = haskey(ENV,"VARS") ? String.(split(ENV["VARS"],",")) : VARS
    models = sort(filter(d -> isdir(joinpath(INROOT,d)) && d != OUTMODEL && !startswith(d,"_"),
                         readdir(INROOT)))
    println("Ensemble over $(length(models)) models -> $(joinpath(INROOT,OUTMODEL))")
    for var in vars
        units, longname = var_attrs(var, models)
        esum = zeros(Float64, NT, NLAT, NLON); ecnt = zeros(Int16, NT, NLAT, NLON)
        nmod = 0
        excl = get(BADENS, var, String[])
        for m in models
            m in excl && (println("  skip $m (known $var data issue)"); continue)
            f = regrid_model(m, var)
            f === nothing && continue
            @inbounds for k in eachindex(f)
                x = f[k]; if !isnan(x); esum[k]+=x; ecnt[k]+=1; end
            end
            nmod += 1
        end
        nmod == 0 && (println("  $var: no model data, skip"); continue)
        emean = fill(FILL, NT, NLAT, NLON)
        @inbounds for k in eachindex(emean)
            ecnt[k] >= MINMODELS && (emean[k] = Float32(esum[k]/ecnt[k]))
        end
        path = write_var(var, emean, units, longname)
        valid = count(!=(FILL), emean)
        @printf("  %-10s %2d models  %s  valid=%.1f%%  -> %s\n",
                var, nmod, units, 100*valid/length(emean), basename(path))
    end
    println("done.")
end

main()
