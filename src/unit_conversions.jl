"""
Unit conversion functions for actual data values (not just unit strings).

This module handles conversion of data values when TRENDY models provide
variables in different units than ILAMB expects.
"""

"""
    convert_data_values(data::Array, from_units::String, to_units::String, variable::String) -> Array

Convert data values from one unit to another.

# Arguments
- `data`: Array of data values
- `from_units`: Original units (from TRENDY file)
- `to_units`: Target units (expected by ILAMB)
- `variable`: Variable name (for context-specific conversions)

# Returns
- Converted data array (or original if no conversion needed)

# Supported Conversions
- Temperature: Celsius/celsius → Kelvin (add 273.15)
- Precipitation: mm → kg m-2 s-1 (requires time context, handled separately)
- Radiation: W m-2 → W m-2 (no conversion)
"""
function convert_data_values(data::Array, from_units::AbstractString, to_units::AbstractString, variable::AbstractString)
    # Normalize unit strings for comparison
    from_clean = strip(lowercase(from_units))
    to_clean = strip(lowercase(to_units))
    
    # No conversion needed if units match
    if from_clean == to_clean
        @info "No unit conversion needed" from=from_units to=to_units
        return data
    end
    
    @info "Converting data values" from=from_units to=to_units variable=variable
    
    # Temperature conversions
    if variable == "tas" || occursin("temperature", lowercase(variable))
        if (occursin("celsius", from_clean) || occursin("degc", from_clean) || 
            occursin("degree c", from_clean) || occursin("deg c", from_clean)) && 
           (to_clean == "k" || occursin("kelvin", to_clean))
            @info "Converting temperature: Celsius → Kelvin (+273.15)"
            return data .+ 273.15
        elseif (from_clean == "k" || occursin("kelvin", from_clean)) && 
               (occursin("celsius", to_clean) || occursin("degc", to_clean))
            @info "Converting temperature: Kelvin → Celsius (-273.15)"
            return data .- 273.15
        end
    end
    
    # Precipitation conversions
    # Note: mm to kg m-2 s-1 requires time interval information
    # mm/month, mm/year, etc. need different conversion factors
    # This is handled in a separate function with time context
    if variable == "pr" || occursin("precip", lowercase(variable))
        if occursin("mm", from_clean) && occursin("kg m-2 s-1", to_clean)
            @warn "Precipitation conversion mm → kg m-2 s-1 requires time context" from=from_units
            # Will be handled by convert_precipitation_values()
            return data
        end
    end
    
    # Radiation conversions (W m-2 is standard, no conversion typically needed)
    if variable == "rsds" || occursin("radiation", lowercase(variable))
        if occursin("w", from_clean) && occursin("m", from_clean) && 
           occursin("w", to_clean) && occursin("m", to_clean)
            @info "Radiation units already in W m-2, no conversion needed"
            return data
        end
    end
    
    # If we reach here, we don't have a conversion for this unit pair
    @warn "No conversion available for units" from=from_units to=to_units variable=variable
    return data
end

"""
    convert_precipitation_values(data::Array, from_units::String, time_interval::String) -> Array

Convert precipitation from mm (accumulated) to kg m-2 s-1 (flux).

# Arguments
- `data`: Precipitation values in mm
- `from_units`: Original units (should contain "mm")
- `time_interval`: Time interval ("monthly", "daily", "yearly")

# Returns
- Precipitation in kg m-2 s-1

# Note
- 1 mm of water = 1 kg m-2 (density of water)
- Monthly: divide by ~2.628e6 seconds (30.4 days average)
- Daily: divide by 86400 seconds
- Yearly: divide by ~3.154e7 seconds (365.25 days)
"""
function convert_precipitation_values(data::Array, from_units::AbstractString, time_interval::AbstractString)
    from_clean = strip(lowercase(from_units))
    
    if !occursin("mm", from_clean)
        @warn "Expected mm units for precipitation" units=from_units
        return data
    end
    
    # Conversion factors: mm to kg m-2 s-1
    # 1 mm = 1 kg m-2, then divide by seconds in the interval
    seconds_per_month = 30.4 * 86400  # ~2.628e6
    seconds_per_day = 86400
    seconds_per_year = 365.25 * 86400  # ~3.154e7
    
    interval_clean = strip(lowercase(time_interval))
    
    if occursin("month", interval_clean) || occursin("mon", interval_clean)
        @info "Converting precipitation: mm/month → kg m-2 s-1"
        return data ./ seconds_per_month
    elseif occursin("day", interval_clean) || occursin("daily", interval_clean)
        @info "Converting precipitation: mm/day → kg m-2 s-1"
        return data ./ seconds_per_day
    elseif occursin("year", interval_clean) || occursin("annual", interval_clean) || occursin("yr", interval_clean)
        @info "Converting precipitation: mm/year → kg m-2 s-1"
        return data ./ seconds_per_year
    else
        @warn "Unknown time interval for precipitation conversion" interval=time_interval
        # Default to monthly if uncertain
        @warn "Assuming monthly interval for mm → kg m-2 s-1 conversion"
        return data ./ seconds_per_month
    end
end
