"""
    convert_to_ilamb(dataset::TRENDYDataset; output_dir::String=".", override_start_date::Union{String,Nothing}=nothing, override_end_date::Union{String,Nothing}=nothing)

Convert a TRENDY dataset to ILAMB format.

Output filename format: {variable}_Lmon_{model}_historical_{simulation}_gn_{start_date}-{end_date}.nc
Example: gpp_Lmon_CARDAMOM_historical_S3_gn_200101-202112.nc

Arguments:
- dataset: TRENDYDataset to convert
- output_dir: Directory to write output files  
- override_start_date: Optional fixed start date (YYYYMM format) for filename standardization
- override_end_date: Optional fixed end date (YYYYMM format) for filename standardization

Note: override dates are used ONLY in filenames to ensure ILAMB pattern matching works.
The actual time values in the file reflect the true data coverage.
"""
function convert_to_ilamb(dataset::TRENDYDataset; output_dir::String=".", override_start_date::Union{String,Nothing}=nothing, override_end_date::Union{String,Nothing}=nothing)
    # Open input dataset
    ds_in = Dataset(dataset.path)
    
    # Get time information to determine date range
    time_var = ds_in["time"]
    time_units_attr = get(time_var.attrib, "units", nothing)
    if time_units_attr === nothing
        time_units_attr = get(time_var.attrib, "unit", nothing)
    end
    has_time_units = time_units_attr !== nothing
    time_units = something(time_units_attr, "days since 1850-01-01")
    calendar_attr = get(ds_in["time"].attrib, "calendar", "noleap")
    # Special cases: ISAM-style encoded times do not follow CF time units
    is_yearmonth_encoded = occursin("month as %Y%m", time_units)
    is_year_encoded = occursin("year as %Y", time_units)
    is_yearday_encoded = occursin("day as %Y%m%d", time_units)
    is_encoded_time = is_yearmonth_encoded || is_year_encoded || is_yearday_encoded
    reference_year = is_encoded_time ? 0 : parse_units(time_units)

    # Read time values with a robust fallback if CF decoding fails
    time_values = nothing
    decoded_times = nothing
    try
        decoded_times = time_var[:]
        time_values = decoded_times
    catch e
        @warn "Failed to decode time variable, reading raw numeric values" exception=(e, catch_backtrace())
        time_units = something(time_units_attr, "days since 1850-01-01")
        time_values = time_var.var[:]
    end
    
    # Check if time values are simple month indices (1, 2, 3, ... n)
    # This happens with CARDAMOM which lacks proper time units
    # Only treat as month indices if:
    # 1. Time units are missing or non-standard, AND
    # 2. Values form consecutive sequence starting from 1
    is_nonstandard_units = !has_time_units || !occursin(r"^(days|months|years|hours) since ", time_units)
    is_month_index = (length(time_values) > 1 && 
                     time_values[1] == 1 && 
                     time_values[2] == 2 &&
                     all(diff(time_values) .== 1) &&
                     is_nonstandard_units)
    
    # Helper to approximate year-month from day offset (for filename updates after cropping)
    approx_year_month(day::Real) = begin
        y = 1850 + floor(Int, day / 365)
        day_in_year = day - (y - 1850) * 365
        m = max(1, min(12, Int(ceil(day_in_year / (365 / 12)))))
        (y, m)
    end

    start_date = ""
    end_date = ""

    if is_yearmonth_encoded
        # Values are month indices (e.g., ISAM "month as %Y%m.%f")
        days, time_bounds = yearmonth_index_to_days(time_values)
        start_year, start_month = days_to_year_month(time_bounds[1, 1])
        end_year, end_month = days_to_year_month(time_bounds[end, 2] - 1)
        start_date = string(start_year) * lpad(start_month, 2, '0')
        end_date = string(end_year) * lpad(end_month, 2, '0')
    elseif is_year_encoded
        # Values are years (e.g., ISAM "year as %Y.%f": 1700, 1701, ..., 2023)
        # Annual data — create one time step per year with Jan 1 to Jan 1 bounds
        n = length(time_values)
        days = zeros(Float64, n)
        time_bounds = zeros(Float64, n, 2)
        for i in 1:n
            year = round(Int, time_values[i])
            start_day = days_since_1850_for_month_start(year, 1)
            end_day = days_since_1850_for_month_start(year + 1, 1)
            days[i] = start_day + (end_day - start_day) / 2
            time_bounds[i, 1] = start_day
            time_bounds[i, 2] = end_day
        end
        start_year = round(Int, time_values[1])
        end_year = round(Int, time_values[end])
        start_date = string(start_year) * "01"
        end_date = string(end_year) * "12"
        @info "Year-encoded time" n_years=n start_year=start_year end_year=end_year
    elseif is_yearday_encoded
        # Values encoded as YYYYMMDD (e.g., ISAM "day as %Y%m%d.%f")
        # Some files have broken (all-zero) time values — generate synthetic monthly time
        n = length(time_values)
        days = zeros(Float64, n)
        time_bounds = zeros(Float64, n, 2)
        if all(v -> v == 0 || isnan(v), time_values)
            # Broken time — assume TRENDY standard 1700–2023 monthly data
            @warn "Time values are all zero with '$time_units' encoding; generating synthetic monthly time from 1700" n_timesteps=n
            start_year_val = 1700
            for i in 1:n
                month_offset = i - 1
                y = start_year_val + div(month_offset, 12)
                m = (month_offset % 12) + 1
                sday = days_since_1850_for_month_start(y, m)
                eday = days_since_1850_for_month_end(y, m)
                days[i] = sday + (eday - sday) / 2
                time_bounds[i, 1] = sday
                time_bounds[i, 2] = eday
            end
            start_date = string(start_year_val) * "01"
            n_total_months = n
            end_year_val = start_year_val + div(n_total_months - 1, 12)
            end_month_val = ((n_total_months - 1) % 12) + 1
            end_date = string(end_year_val) * lpad(end_month_val, 2, '0')
        else
            # Parse YYYYMMDD-encoded values as monthly midpoints
            for i in 1:n
                v = round(Int, time_values[i])
                y = div(v, 10000)
                m = div(v % 10000, 100)
                m = max(1, min(12, m))
                sday = days_since_1850_for_month_start(y, m)
                eday = days_since_1850_for_month_end(y, m)
                days[i] = sday + (eday - sday) / 2
                time_bounds[i, 1] = sday
                time_bounds[i, 2] = eday
            end
            first_v = round(Int, time_values[1])
            last_v = round(Int, time_values[end])
            start_date = string(div(first_v, 10000)) * lpad(div(first_v % 10000, 100), 2, '0')
            end_date = string(div(last_v, 10000)) * lpad(div(last_v % 10000, 100), 2, '0')
        end
        @info "Day-encoded time" n_timesteps=n start_date=start_date end_date=end_date
    elseif is_month_index && dataset.model == "CARDAMOM"
        # CARDAMOM: Time values are month indices starting from 1
        # CARDAMOM data starts in January 2003
        n_months = length(time_values)
        start_year = 2003
        start_month = 1
        
        # Convert month indices to days since 1850 for internal processing
        days = zeros(Float64, n_months)
        time_bounds = zeros(Float64, n_months, 2)
        for i in 1:n_months
            month_offset = i - 1
            year = start_year + div(month_offset, 12)
            month = (month_offset % 12) + 1
            start_day = days_since_1850_for_month_start(year, month)
            end_day = days_since_1850_for_month_end(year, month)
            month_len = DAYS_PER_MONTH_NOLEAP[month]
            days[i] = start_day + month_len / 2
            time_bounds[i, 1] = start_day
            time_bounds[i, 2] = end_day
        end
    elseif decoded_times !== nothing && !isempty(decoded_times) && (decoded_times[1] isa NCDatasets.CFTime.AbstractCFDateTime || decoded_times[1] isa Dates.AbstractDateTime)
        # CFTime/DateTime: detect annual vs monthly resolution, then build bounds accordingly
        n = length(decoded_times)
        days = zeros(Float64, n)
        time_bounds = zeros(Float64, n, 2)
        y0 = Dates.year(decoded_times[1])
        m0 = Dates.month(decoded_times[1])

        # Detect temporal resolution: if the year advances between first two timesteps, it's annual
        is_annual_data = false
        if n >= 2
            y1 = Dates.year(decoded_times[2])
            is_annual_data = (y1 - y0) >= 1
        end

        if is_annual_data
            # Annual data: one time step per year, bounds span full year
            @info "Detected annual data from CFTime" n_years=n first_year=y0
            for i in 1:n
                y = Dates.year(decoded_times[i])
                sday = days_since_1850_for_month_start(y, 1)
                eday = days_since_1850_for_month_start(y + 1, 1)
                days[i] = sday + (eday - sday) / 2
                time_bounds[i, 1] = sday
                time_bounds[i, 2] = eday
            end
        else
            # Monthly data: step month by month from first year/month to ensure contiguity
            for i in 1:n
                month_idx = (m0 - 1) + (i - 1)
                y = y0 + div(month_idx, 12)
                m = (month_idx % 12) + 1
                sday = days_since_1850_for_month_start(y, m)
                eday = days_since_1850_for_month_end(y, m)
                days[i] = sday + (eday - sday) / 2
                time_bounds[i, 1] = sday
                time_bounds[i, 2] = eday
            end
        end
    elseif occursin("months since", lowercase(time_units))
        # Numeric months since a reference date; assume monthly cadence starting from the first value
        n = length(time_values)
        days = zeros(Float64, n)
        time_bounds = zeros(Float64, n, 2)
        base_month_index = round(Int, time_values[1])
        for i in 1:n
            month_offset = base_month_index + (i - 1)
            year = reference_year + div(month_offset, 12)
            month = (month_offset % 12) + 1
            sday = days_since_1850_for_month_start(year, month)
            eday = days_since_1850_for_month_end(year, month)
            days[i] = sday + (eday - sday) / 2
            time_bounds[i, 1] = sday
            time_bounds[i, 2] = eday
        end
    else
        # Fallback: continuous bounds from numeric days/years
        days = convert_time_to_days(time_values, reference_year; time_units=time_units, calendar=calendar_attr)
        time_bounds = continuous_bounds_from_time(days)
    end

    # No benchmark-dependent trimming; ensure time_bounds/time are contiguous and match data length
    time_indices_used = collect(1:length(time_values))

    # Calculate start and end dates if not set yet.
    # Derive them from the authoritative rebuilt time axis (time_bounds, in days
    # since 1850) rather than from raw decoded_times: for non-CF encodings such as
    # "months since", CFTime approximates a month as ~30.44 days, so its endpoints
    # drift by several months over a multi-century record (e.g. CABLE-POP showed
    # 2025-03 in the filename while the real last month is 2024-12).
    if isempty(start_date)
        start_year, start_month = days_to_year_month(time_bounds[1, 1])
        end_year, end_month = days_to_year_month(time_bounds[end, 2] - 1)
        start_date = string(start_year) * lpad(start_month, 2, '0')
        end_date = string(end_year) * lpad(end_month, 2, '0')
    end
    
    # Override dates if provided (for filename standardization across model files)
    # This ensures ILAMB's pattern matching works even when variables have different temporal coverage
    if override_start_date !== nothing
        start_date = override_start_date
    end
    if override_end_date !== nothing
        end_date = override_end_date
    end
    
    # Create ILAMB-compliant filename
    # Format: {variable}_Lmon_ENSEMBLE-{model}_historical_r1i1p1f1_gn_{start_date}-{end_date}.nc
    # Normalize variable case to match ILAMB expectations (e.g., LAI → lai, csoil → cSoil)
    normalized_var = normalize_variable_case(dataset.variable)
    filename = "$(normalized_var)_Lmon_ENSEMBLE-$(dataset.model)_historical_r1i1p1f1_gn_$(start_date)-$(end_date).nc"
    
    # Output directly in model directory (no S3 subdirectory)
    output_file = joinpath(output_dir, filename)
    mkpath(dirname(output_file))
    
    # Remove existing file if it exists
    isfile(output_file) && rm(output_file)
    
    # Create output dataset in define mode
    ds_out = Dataset(output_file, "c")
    
    # Define these outside the try block so they're available in the full function scope
    local units
    local var_atts
    
    try
        @info "Creating output file: $output_file"
        
        # Get variable attributes and standardize units first
        var_atts = ds_in[dataset.variable].attrib
        meta = get_variable_metadata(dataset.variable)
        raw_units = get(var_atts, "units", nothing)
        # Fall back to "unit" attribute if "units" is missing or non-string (e.g., NaN)
        if raw_units === nothing || !(raw_units isa AbstractString)
            raw_units = get(var_atts, "unit", meta.units)
        end
        if raw_units === nothing || !(raw_units isa AbstractString)
            raw_units = meta.units
        end
        units = standardize_units(raw_units)
        # If sanitization produces something obviously wrong, fall back to mapped metadata units
        if isempty(units) || units == raw_units || occursin(r"m1", units) || occursin(r"m\$1", raw_units)
            units = meta.units
        end
        # Safety net: never emit "unknown". If the variable has no registry mapping,
        # preserve the (standardized) source units so files stay CF-usable
        # (e.g. JSBACH hfls is "W m-2" at the source).
        if isempty(units) || units == "unknown"
            su = standardize_units(raw_units)
            units = (isempty(su) || su == "unknown") ? raw_units : su
        end
        @info "Variable metadata" variable=dataset.variable units=units
        
        # Get dimension sizes first (use ds_in.dim to get sizes, not variables)
        dim_sizes = Dict{String,Int}()
        for name in keys(ds_in.dim)
            dim_sizes[name] = ds_in.dim[name]
        end
        @info "Input dimensions:" dim_sizes
        
        # Define dimensions in a specific order with strict error handling
        # Handle both "lat"/"lon" and "latitude"/"longitude" naming conventions
        @info "Defining spatial dimensions"

        # Define lat dimension (from either "lat" or "latitude")
        lat_size = get(dim_sizes, "lat", get(dim_sizes, "latitude", nothing))
        if lat_size !== nothing
            if !("lat" in keys(ds_out.dim))
                defDim(ds_out, "lat", lat_size)
                @info "Successfully defined lat dimension" size=lat_size
            end
        end

        # Define lon dimension (from either "lon" or "longitude")
        lon_size = get(dim_sizes, "lon", get(dim_sizes, "longitude", nothing))
        if lon_size !== nothing
            if !("lon" in keys(ds_out.dim))
                defDim(ds_out, "lon", lon_size)
                @info "Successfully defined lon dimension" size=lon_size
            end
        end
        
        # Define time dimension with error handling
        @info "Defining time dimension" size=length(days)
        try
            if !("time" in keys(ds_out.dim))
                defDim(ds_out, "time", length(days))
                @info "Successfully defined time dimension"
            else
                @warn "time dimension already exists"
            end
        catch e
            @error "Failed to define time dimension" exception=(e, catch_backtrace())
            rethrow(e)
        end
        
        # Log time information for debugging
        @info "Raw time values:" first_10_values=time_values[1:min(10, length(time_values))] time_units=time_units
        @info "Using reference year" reference_year=reference_year
        @info "Computed days since 1850:" first_3_days=days[1:min(3, length(days))] last_3_days=days[max(1, end-2):end]
        
        # Define the nb dimension first
        if !("nb" in keys(ds_out.dim))
            defDim(ds_out, "nb", 2)
        end

        # Define time variable (time dimension should already exist)
        @info "Creating time variable" length=length(days)
        defVar(ds_out, "time", days, ("time",), 
               attrib = Dict(
                   "units" => "days since 1850-01-01",
                   "calendar" => "noleap",
                   "bounds" => "time_bounds"
               ))
        
        # Define time bounds variable.
        # NCDatasets REVERSES dimension order on write (verified empirically:
        # passing a Julia (n,2) array with dims ("time","nb") yields file tb(nb,time)).
        # CF requires time_bounds(time, nb) in the FILE, so pass a (2, n_times) array
        # with dims ("nb", "time"); NCDatasets reverses it to the CF (time, nb) layout.
        @info "Creating time_bounds variable" size=size(time_bounds)
        if size(time_bounds, 2) == 2  # Shape is (n_times, 2)
            defVar(ds_out, "time_bounds", permutedims(time_bounds, (2, 1)), ("nb", "time"))
        elseif size(time_bounds, 1) == 2  # Shape is (2, n_times)
            defVar(ds_out, "time_bounds", time_bounds, ("nb", "time"))
        else
            error("Unexpected time_bounds shape: $(size(time_bounds))")
        end
        
        # Copy lat/lon coordinates (handle both naming conventions)
        lat_var = haskey(ds_in, "lat") ? "lat" : (haskey(ds_in, "latitude") ? "latitude" : nothing)
        if lat_var !== nothing
            lat = ds_in[lat_var][:]
            defVar(ds_out, "lat", lat, ("lat",),
                   attrib = Dict("units" => "degrees_north"))
        end

        lon_var = haskey(ds_in, "lon") ? "lon" : (haskey(ds_in, "longitude") ? "longitude" : nothing)
        if lon_var !== nothing
            lon = ds_in[lon_var][:]
            defVar(ds_out, "lon", lon, ("lon",),
                   attrib = Dict("units" => "degrees_east"))
        end
        
        # Copy main variable data (use Array() to preserve shape, not [:] which flattens)
        var_data = Array(ds_in[dataset.variable])
        input_dims = dimnames(ds_in[dataset.variable])
        time_idx = findfirst(==("time"), input_dims)
        if time_idx !== nothing
        time_indices = time_indices_used === nothing ? collect(1:size(var_data, time_idx)) : time_indices_used
            maxlen = size(var_data, time_idx)
            if any(time_indices .> maxlen)
                @warn "Time indices exceed variable length; truncating to available range" maxlen=maxlen
                time_indices = filter(x -> x <= maxlen, time_indices)
            end
            inds = ntuple(i -> Colon(), ndims(var_data))
            inds = Base.setindex(inds, time_indices, time_idx)
            var_data = var_data[inds...]
        end
        
        # Apply unit conversions to data values if needed
        @info "Checking for unit conversions" raw_units=raw_units target_units=units
        var_data = convert_data_values(var_data, raw_units, units, dataset.variable)
        
        # Special handling for precipitation mm → kg m-2 s-1
        if dataset.variable == "pr" && occursin("mm", lowercase(raw_units))
            var_data = convert_precipitation_values(var_data, raw_units, "monthly")
        end
        
        @info "Creating main variable" variable=dataset.variable size=size(var_data)

        # Map input dimension names to output dimension names
        input_dims = dimnames(ds_in[dataset.variable])
        dim_name_map = Dict(
            "longitude" => "lon",
            "latitude" => "lat",
            "time" => "time",
            "lon" => "lon",
            "lat" => "lat"
        )
        output_dims = Tuple(get(dim_name_map, d, d) for d in input_dims)

        # Build output attributes - preserve _FillValue if it exists in source
        out_attribs = Dict{String, Any}(
            "units" => units,
            "long_name" => get(var_atts, "long_name", normalized_var)
        )
        if haskey(var_atts, "_FillValue")
            out_attribs["_FillValue"] = var_atts["_FillValue"]
        end

        # Write the main variable with zlib compression (shuffle + deflate).
        # TRENDY inputs are deflated; without this the ILAMB copies balloon ~5x
        # (e.g. a 0.5deg gpp file goes 0.77 GB -> 4 GB).
        defVar(ds_out, normalized_var, var_data, output_dims,
               attrib = out_attribs,
               shuffle = true, deflatelevel = 4)
        
    finally
        close(ds_in)
        close(ds_out)
    end
    
    return ILAMBDataset(
        output_file,
        normalized_var,
        units,
        "days since 1850-01-01",
        "noleap"
    )
end
