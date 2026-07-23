"""
ILAMB Variable Case Mapping

This module defines the expected case for each ILAMB variable based on buildkite_ilamb.cfg.
TRENDY models use various cases, but ILAMB expects specific cases in filenames.

This mapping ensures TRENDYtoILAMB.jl outputs files that ILAMB can find.
"""

# Mapping: ILAMB variable (lowercase key) => Expected case in ILAMB
const ILAMB_VARIABLE_CASE = Dict{String, String}(
    # Carbon cycle fluxes (all lowercase)
    "gpp"    => "gpp",
    "nbp"    => "nbp", 
    "npp"    => "npp",
    "ra"     => "ra",
    "rh"     => "rh",
    "nee"    => "nee",  # Derived variable
    
    # Vegetation structure (lowercase)
    "lai"    => "lai",  # ILAMB: variable = "lai"
    
    # Carbon pools (camelCase starting with lowercase 'c')
    "csoil"    => "cSoil",     # ILAMB: alternate_vars = "cSoil"
    "cveg"     => "cVeg",      # ILAMB: alternate_vars = "cVeg"
    "clitter"  => "cLitter",
    "cproduct" => "cProduct",
    "cleaf"    => "cLeaf",
    "croot"    => "cRoot",
    "cwood"    => "cWood",
    "ccwd"     => "cCwd",
    
    # Fire (camelCase)
    "burntarea" => "burntArea",  # TRENDY survey: 14 models use this exact case
    "ffire"     => "fFire",      # TRENDY survey: 16 models use this exact case
    
    # Hydrology (all lowercase)
    "mrro"        => "mrro",       # Runoff
    "mrros"       => "mrros",      # Surface runoff
    "mrso"        => "mrso",       # Soil moisture
    "evapotrans"  => "et",         # TRENDY: evapotrans → ILAMB: et
    "et"          => "et",         # Accept et directly too
    "evspsbl"     => "evspsbl",    # Evaporation (alternate ILAMB name)
    "tran"        => "tran",       # Transpiration
    
    # Land use (camelCase)
    "fluc" => "fLuc",  # TRENDY survey: 17 models use this exact case
    
    # Forcing variables (all lowercase)
    "tas"  => "tas",   # Air temperature
    "pr"   => "pr",    # Precipitation
    "rsds" => "rsds",  # Shortwave radiation
    "msl"  => "msl",   # Mean sea level pressure
    
    # Add more as needed from TRENDY survey...
)

"""
    normalize_variable_case(variable::String) -> String

Normalize a variable name to the case expected by ILAMB.

# Arguments
- `variable`: Variable name from TRENDY file (any case)

# Returns
- Variable name in the case ILAMB expects

# Examples
```julia
normalize_variable_case("cSoil")   # Returns "cSoil"
normalize_variable_case("LAI")     # Returns "lai" (ISAM special case)
normalize_variable_case("lai")     # Returns "lai"
normalize_variable_case("gpp")     # Returns "gpp"
```
"""
function normalize_variable_case(variable::String)
    lowercase_var = lowercase(variable)
    
    # Look up in the mapping
    if haskey(ILAMB_VARIABLE_CASE, lowercase_var)
        return ILAMB_VARIABLE_CASE[lowercase_var]
    else
        # Default: preserve original case if not in mapping
        # This allows new variables to work without breaking existing ones
        @warn "Variable '$variable' not in ILAMB case mapping, preserving original case"
        return variable
    end
end

"""
    get_ilamb_variables() -> Vector{String}

Get list of all ILAMB variables in their expected case.
"""
function get_ilamb_variables()
    return sort(unique(values(ILAMB_VARIABLE_CASE)))
end
