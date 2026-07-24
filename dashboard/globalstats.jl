#=
Recompute dashboard/site/data/globalmeans.json as physically meaningful global
aggregates and tag each variable's global-metric units in manifest.json:
  - carbon fluxes (g C m-2 day-1)  -> global TOTAL in Pg C yr-1
  - carbon pools  (kg C m-2)       -> global TOTAL in Pg C
  - other (lai, et, ...)           -> area-weighted MEAN in native units
Reads the packed Int16 bins (fast); does not touch the map data.
=#
using Printf
const D = get(ENV, "GM_DATA_DIR", joinpath(@__DIR__, "site", "data"))  # per-scenario override
const R = 6.371e6                                  # Earth radius (m)

read_manifest() = read(joinpath(D, "manifest.json"), String)
# tiny helpers to pull fields we need out of the manifest JSON text
function jfield(txt, key)
    m = match(Regex("\"$key\":\\s*([0-9.eE+-]+)"), txt); parse(Float64, m.captures[1])
end
function jarray(txt, key)
    m = match(Regex("\"$key\":\\[([^\\]]*)\\]"), txt); parse.(Float64, split(m.captures[1], ","))
end
function jstrarray(txt, key)
    m = match(Regex("\"$key\":\\[([^\\]]*)\\]"), txt)
    [strip(s, ['"',' ']) for s in split(m.captures[1], ",")]
end

txt = read_manifest()
nlon = Int(jfield(txt,"nlon")); nlat = Int(jfield(txt,"nlat")); nt = Int(jfield(txt,"nt"))
fill = Int(jfield(txt,"fill")); lat = jarray(txt,"lat"); models = jstrarray(txt,"models")
# variable scales & names from the "variables" block
vblock = match(r"\"variables\":\[(.*)\]", txt).captures[1]
vars = [(name=m.captures[1], scale=parse(Float64,m.captures[2]))
        for m in eachmatch(r"\{\"name\":\"([^\"]+)\",\"units\":\"[^\"]*\",\"scale\":([0-9.eE+-]+)", vblock)]

# per-latitude-row cell area (m^2), 1-deg grid
cellA = [R^2 * deg2rad(1.0) * (sin(deg2rad(l+0.5)) - sin(deg2rad(l-0.5))) for l in lat]

# global-metric kind + units per variable
gmkind = Dict("gpp"=>:flux,"nbp"=>:flux,"npp"=>:flux,"ra"=>:flux,"rh"=>:flux,"reco"=>:flux,"fFire"=>:flux,
              "cVeg"=>:pool,"cSoil"=>:pool,"cLitter"=>:pool)
gmunits = Dict(:flux=>"Pg C yr-1", :pool=>"Pg C")

const block = nlat*nlon
const rowA = [cellA[((k-1) ÷ nlon) + 1] for k in 1:block]   # per-cell area, lon-fastest

function series(raw, scale, kind)
    s = Vector{Float64}(undef, nt)
    @inbounds for t in 1:nt
        base = (t-1)*block; acc = 0.0; wsum = 0.0; nval = 0
        for k in 1:block
            v = raw[base+k]; v == fill && continue
            nval += 1
            val = v*scale; a = rowA[k]
            if kind === :flux;      acc += val*a*365.0*1e-15
            elseif kind === :pool;  acc += val*a*1e-12
            else;                   acc += val*a; wsum += a
            end
        end
        # empty timesteps -> NaN (not 0) so short-record models (e.g. CARDAMOM 2003-)
        # aren't diluted when averaged over the full window
        s[t] = kind === :mean ? (wsum > 0 ? acc/wsum : NaN) : (nval > 0 ? acc : NaN)
    end
    s
end

open(joinpath(D,"globalmeans.json"),"w") do io
    print(io,"{")
    for (vi,v) in enumerate(vars)
        kind = get(gmkind, v.name, :mean)
        print(io, vi>1 ? "," : "", "\"$(v.name)\":{")
        first=true
        for m in models
            f = joinpath(D, v.name, "$(m).bin"); isfile(f) || continue
            raw = reinterpret(Int16, read(f))
            s = series(raw, v.scale, kind)
            ser = [isnan(x) ? "null" : @sprintf("%.5g",x) for x in s]
            print(io, first ? "" : ",", "\"$m\":[", join(ser,","), "]"); first=false
        end
        print(io,"}")
        println("  $(v.name): $(kind)")
    end
    print(io,"}")
end
println("globalmeans.json recomputed (Pg C yr-1 for fluxes, Pg C for pools, native mean otherwise)")
