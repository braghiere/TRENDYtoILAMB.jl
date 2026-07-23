#=
Dashboard preprocessing (Phase 1): pack several TRENDY variables into a compact,
browser-loadable store for the static viewer in dashboard/site/.

For each variable it:
  - reads each model's converted file, selects months 1980-01 .. 2024-12,
  - nearest-neighbour regrids each month to a common 1 deg grid (360x180),
  - converts to display units and packs to Int16 (per-variable scale),
  - writes site/data/<var>/<MODEL>.bin  (Int16 [time,lat,lon], lon fastest),
  - accumulates the ENSEMBLE mean and spread (std across models) -> two extra bins,
  - accumulates the area-weighted GLOBAL MEAN time series per model + ensemble.

Outputs:
  site/data/manifest.json           grid, time axis, variable + model metadata
  site/data/<var>/<MODEL>.bin       per-model packed field
  site/data/<var>/ENSEMBLE-mean.bin, ENSEMBLE-std.bin
  site/data/globalmeans.json        {var: {model: [nt floats]}}

Usage: julia --project=. dashboard/preprocess.jl
       VARS=gpp,lai  MODELS=CABLE-POP,ORCHIDEE julia --project=. dashboard/preprocess.jl
=#

using NCDatasets
using Printf

jnum(x) = string(x)
jarr(v) = "[" * join(jnum.(v), ",") * "]"
jstrarr(v) = "[" * join(["\"$(s)\"" for s in v], ",") * "]"

# variable registry: source name => (factor to display unit, units, int16 scale,
#                                     display vmin, vmax, diverging?)
const VARDEF = Dict(
    "gpp"  => (86_400_000.0, "g C m-2 day-1", 0.001, 0.0, 12.0, false),
    "npp"  => (86_400_000.0, "g C m-2 day-1", 0.001, -1.0, 6.0, false),
    "nbp"  => (86_400_000.0, "g C m-2 day-1", 0.001, -3.0, 3.0, true),
    "ra"   => (86_400_000.0, "g C m-2 day-1", 0.001, 0.0, 8.0,  false),
    "rh"   => (86_400_000.0, "g C m-2 day-1", 0.001, 0.0, 6.0,  false),
    "cVeg" => (1.0,          "kg C m-2",      0.005, 0.0, 25.0, false),
    "cSoil"=> (1.0,          "kg C m-2",      0.01,  0.0, 50.0, false),
    "lai"  => (1.0,          "m2 m-2",        0.001, 0.0, 7.0,  false),
    "et"   => (86_400.0,     "mm day-1",      0.001, 0.0, 6.0,  false),
    "tran" => (86_400.0,     "mm day-1",      0.001, 0.0, 4.0,  false),
    "mrro" => (86_400.0,     "mm day-1",      0.001, 0.0, 6.0,  false),
    "mrso" => (1.0,          "kg m-2",        0.1,   0.0, 1500.0, false),
    "pr"   => (86_400.0,     "mm day-1",      0.001, 0.0, 10.0, false),
    "tas"  => (1.0,          "K",             0.02,  240.0, 310.0, false),
    "rsds" => (1.0,          "W m-2",         0.02,  0.0, 320.0, false),
)
const VARORDER = ["gpp","npp","nbp","ra","rh","cVeg","cSoil","lai","et","tran","mrro","mrso","pr","tas","rsds"]
# model/var combos excluded from the ENSEMBLE mean/std (kept as individual layers):
# VISIT-UT tas corrected (+546.30 K) so it rejoins; ED pr is ~12x too low (bad scaling).
const BADENS = Dict("pr" => ["ED"])

const FILLI16   = Int16(-32768)
const Y0, Y1    = 1980, 2024
const NLON, NLAT = 360, 180
const INROOT    = "/home/renatob/data/ilamb_output_v14_S2"
const OUTROOT   = joinpath(@__DIR__, "site", "data")

tlon = collect(-179.5:1.0:179.5)
tlat = collect(-89.5:1.0:89.5)
const COSW = cosd.(tlat)                       # area weights (lat)
months = [(y, m) for y in Y0:Y1 for m in 1:12]
const NT = length(months)
midx = Dict((y, m) => i for (i, (y, m)) in enumerate(months))
const MLEN = (31,28,31,30,31,30,31,31,30,31,30,31)
function decode_noleap(day::Real)
    d = floor(Int, day); y = 1850 + fld(d, 365); r = d - (y - 1850) * 365; m = 1
    while m <= 12 && r >= MLEN[m]; r -= MLEN[m]; m += 1; end
    (y, min(m, 12))
end
function nn_index(src, tgt)
    idx = Vector{Int}(undef, length(tgt))
    for (k, t) in enumerate(tgt)
        j = searchsortedfirst(src, t)
        idx[k] = j <= 1 ? 1 : j > length(src) ? length(src) :
                 (abs(src[j]-t) < abs(src[j-1]-t) ? j : j-1)
    end
    idx
end

# regrid one model's variable to Float32 [NT,NLAT,NLON] (NaN where missing)
function regrid_model(model, srcvar, factor)
    d = joinpath(INROOT, model)
    isdir(d) || return nothing
    fs = filter(f -> startswith(basename(f), "$(srcvar)_"), readdir(d, join=true))
    isempty(fs) && return nothing
    ds = NCDataset(fs[1])
    try
        latn = haskey(ds,"lat") ? "lat" : "latitude"; lonn = haskey(ds,"lon") ? "lon" : "longitude"
        lat = Float64.(ds[latn][:]); lon = Float64.(ds[lonn][:])
        tvals = Float64.(ds["time"].var[:]); ym = decode_noleap.(tvals)
        keep = findall(t -> Y0 <= t[1] <= Y1, ym); isempty(keep) && return nothing
        lon = map(x -> x >= 180 ? x-360 : x, lon)
        lop = sortperm(lon); lap = sortperm(lat)
        ix = nn_index(lon[lop], tlon); iy = nn_index(lat[lap], tlat)
        var = ds[srcvar]; dn = dimnames(var)
        td = findfirst(==("time"), dn)
        # some models carry an extra (e.g. singleton soil layer) dim, e.g. CABLE-POP
        # mrso(time,soil,lat,lon). Select layer 1 of any non-time/lat/lon dim so the
        # read collapses to a 3-D (time,lat,lon) block.
        isspatial(d) = d in ("time","lat","latitude","lon","longitude")
        extra = findall(d -> !isspatial(d), dn)
        kf, kl = first(keep), last(keep)
        selb = Any[Colon() for _ in dn]; selb[td] = kf:kl
        for e in extra; selb[e] = 1; end
        block = Array{Union{Missing,Float32}}(var[selb...])
        remdims = dn[[i for i in 1:length(dn) if !(i in extra)]]
        td = findfirst(==("time"), remdims)
        latd = findfirst(x -> x in ("lat","latitude"), remdims)
        lond = findfirst(x -> x in ("lon","longitude"), remdims)
        out = fill(Float32(NaN), NT, NLAT, NLON)
        # annual (pool) variables carry ~1 timestep/year -> replicate across the 12
        # months of that year so the monthly axis is filled (map + totals correct).
        yrs = [ym[t][1] for t in keep]
        isannual = length(keep) <= round(Int, 1.5*length(unique(yrs)))
        for t in keep
            bi = t - kf + 1; s2 = Any[Colon(),Colon(),Colon()]; s2[td] = bi
            raw = block[s2...]
            slice = (latd < lond ? raw : permutedims(raw, (2,1)))[lap, lop]
            (y, mo) = ym[t]
            targets = isannual ? [midx[(y,mm)] for mm in 1:12 if haskey(midx,(y,mm))] : [midx[(y,mo)]]
            @inbounds for j in 1:NLAT, i in 1:NLON
                v = slice[iy[j], ix[i]]
                (v === missing || isnan(v) || v == -9999) && continue
                val = Float32(v) * factor
                for oi in targets; out[oi, j, i] = val; end
            end
        end
        return out
    finally
        close(ds)
    end
end

pack(field, scale) = [isnan(v) ? FILLI16 : round(Int16, clamp(v/scale, -32000, 32000)) for v in field]
writebin(path, i16) = open(io -> write(io, permutedims(i16, (3,2,1))), path, "w")

# area-weighted global mean per month for a Float32 field
function global_means(field)
    gm = Vector{Float64}(undef, NT)
    for t in 1:NT
        num = 0.0; den = 0.0
        @inbounds for j in 1:NLAT, i in 1:NLON
            v = field[t, j, i]
            if !isnan(v); num += v*COSW[j]; den += COSW[j]; end
        end
        gm[t] = den > 0 ? num/den : NaN
    end
    gm
end

function main()
    vars = haskey(ENV,"VARS") ? split(ENV["VARS"], ",") : VARORDER
    # TRENDY-ENSEMBLE is an ILAMB pseudo-model we write into INROOT; it is NOT a
    # source model for the dashboard (the dashboard builds its own ENSEMBLE-mean).
    allmodels = sort(filter(d -> isdir(joinpath(INROOT,d)) && !startswith(d,"_") && d != "TRENDY-ENSEMBLE", readdir(INROOT)))
    models = haskey(ENV,"MODELS") ? String.(split(ENV["MODELS"], ",")) : allmodels
    gmeans = Dict{String,Dict{String,Vector{Float64}}}()
    varmeta = String[]
    donemodels = String[]

    for v in vars
        haskey(VARDEF, v) || (println("skip unknown var $v"); continue)
        factor, units, scale, vmin, vmax, diver = VARDEF[v]
        mkpath(joinpath(OUTROOT, v))
        println("=== $v ($units) ===")
        # ensemble accumulators
        esum = zeros(Float64, NT, NLAT, NLON); esq = zeros(Float64, NT, NLAT, NLON)
        ecnt = zeros(Int32, NT, NLAT, NLON)
        gmeans[v] = Dict{String,Vector{Float64}}()
        vmodels = String[]
        for m in models
            f = regrid_model(m, v, factor)
            f === nothing && (println("  $m: no data"); continue)
            writebin(joinpath(OUTROOT, v, "$(m).bin"), pack(f, scale))
            gmeans[v][m] = global_means(f)
            # keep the individual layer but exclude known-corrupt model/var combos
            # from the ensemble (VISIT-UT tas sign-flip, ED pr ~13x scaling).
            if !(m in get(BADENS, v, String[]))
                @inbounds for k in eachindex(f)
                    x = f[k]; if !isnan(x); esum[k]+=x; esq[k]+=x*x; ecnt[k]+=1; end
                end
            else
                println("  $m: excluded from $v ensemble (known data issue)")
            end
            push!(vmodels, m); (m in donemodels) || push!(donemodels, m)
            @printf("  %-12s ok\n", m)
        end
        # ensemble mean & std (require >=2 models at a cell)
        emean = fill(Float32(NaN), NT, NLAT, NLON); estd = fill(Float32(NaN), NT, NLAT, NLON)
        @inbounds for k in eachindex(emean)
            c = ecnt[k]
            if c >= 2
                mu = esum[k]/c; emean[k] = mu
                estd[k] = sqrt(max(0.0, esq[k]/c - mu*mu))
            end
        end
        writebin(joinpath(OUTROOT, v, "ENSEMBLE-mean.bin"), pack(emean, scale))
        writebin(joinpath(OUTROOT, v, "ENSEMBLE-std.bin"),  pack(estd, scale))
        gmeans[v]["ENSEMBLE-mean"] = global_means(emean)
        gmeans[v]["ENSEMBLE-std"]  = global_means(estd)
        push!(varmeta, "{\"name\":\"$v\",\"units\":\"$units\",\"scale\":$scale,\"vmin\":$vmin,\"vmax\":$vmax,\"diverging\":$(diver)}")
        println("  ensemble mean/std written ($(length(vmodels)) models)")
    end

    # write globalmeans.json
    open(joinpath(OUTROOT, "globalmeans.json"), "w") do io
        print(io, "{")
        for (vi, v) in enumerate(vars)
            haskey(gmeans, v) || continue
            print(io, vi>1 ? "," : "", "\"$v\":{")
            ks = collect(keys(gmeans[v]))
            for (ki, k) in enumerate(ks)
                ser = [isnan(x) ? "null" : @sprintf("%.4g", x) for x in gmeans[v][k]]
                print(io, ki>1 ? "," : "", "\"$k\":[", join(ser, ","), "]")
            end
            print(io, "}")
        end
        print(io, "}")
    end

    modellist = vcat(["ENSEMBLE-mean","ENSEMBLE-std"], donemodels)
    tstr = [@sprintf("%04d-%02d", y, m) for (y,m) in months]
    open(joinpath(OUTROOT, "manifest.json"), "w") do io
        print(io, "{",
            "\"fill\":$(Int(FILLI16)),\"nlon\":$NLON,\"nlat\":$NLAT,\"nt\":$NT,",
            "\"layout\":\"time_lat_lon_int16le\",",
            "\"lon\":", jarr(tlon), ",\"lat\":", jarr(tlat), ",",
            "\"times\":", jstrarr(tstr), ",",
            "\"models\":", jstrarr(modellist), ",",
            "\"variables\":[", join(varmeta, ","), "]",
            "}")
    end
    println("done: $(length(vars)) vars x $(length(donemodels)) models -> $OUTROOT")
end

main()
