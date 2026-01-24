"""
    convert_to_ilamb(dataset::TRENDYDataset; output_dir::String=".")

Convert a TRENDY dataset to ILAMB format.

Output filename format: {variable}_Lmon_{model}_historical_{simulation}_gn_{start_date}-{end_date}.nc
Example: gpp_Lmon_CARDAMOM_historical_S3_gn_200101-202112.nc
"""
function convert_to_ilamb(dataset::TRENDYDataset; output_dir::String=".")
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
    # Special case: ISAM-style encoded months do not follow CF time units
    is_yearmonth_encoded = occursin("month as %Y%m", time_units)
    reference_year = is_yearmonth_encoded ? 0 : parse_units(time_units)

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
        # CFTime/DateTime: build bounds by stepping monthly from the first year/month to ensure contiguity
        n = length(decoded_times)
        days = zeros(Float64, n)
        time_bounds = zeros(Float64, n, 2)
        y0 = Dates.year(decoded_times[1])
        m0 = Dates.month(decoded_times[1])
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

    # Calculate start and end dates if not set yet
    if isempty(start_date)
        if decoded_times !== nothing && !isempty(decoded_times) && (decoded_times[1] isa NCDatasets.CFTime.AbstractCFDateTime || 
                                      decoded_times[1] isa Dates.AbstractDateTime)
            start_year = Dates.year(decoded_times[1])
            start_month = Dates.month(decoded_times[1])
            end_year = Dates.year(decoded_times[end])
            end_month = Dates.month(decoded_times[end])
        else
            start_days_since_1850 = days[1]
            start_years_from_1850 = start_days_since_1850 / 365.0
            start_year = 1850 + floor(Int, start_years_from_1850)
            start_day_in_year = start_days_since_1850 - (start_year - 1850) * 365.0
            start_month = max(1, min(12, ceil(Int, (start_day_in_year / 365.0) * 12)))
            
            end_days_since_1850 = days[end]
            end_years_from_1850 = end_days_since_1850 / 365.0
            end_year = 1850 + floor(Int, end_years_from_1850)
            end_day_in_year = end_days_since_1850 - (end_year - 1850) * 365.0
            end_month = max(1, min(12, ceil(Int, (end_day_in_year / 365.0) * 12)))
        end
        start_date = string(start_year) * lpad(start_month, 2, '0')
        end_date = string(end_year) * lpad(end_month, 2, '0')
    end
    
    # Create ILAMB-compliant filename
    # Format: {variable}_Lmon_ENSEMBLE-{model}_historical_r1i1p1f1_gn_{start_date}-{end_date}.nc
    filename = "$(dataset.variable)_Lmon_ENSEMBLE-$(dataset.model)_historical_r1i1p1f1_gn_$(start_date)-$(end_date).nc"
    
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
        raw_units = something(raw_units, get(var_atts, "unit", meta.units))
        units = standardize_units(raw_units)
        # If sanitization produces something obviously wrong, fall back to mapped metadata units
        if units == raw_units || occursin(r"m1", units) || occursin(r"m\\$1", raw_units)
            units = meta.units
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
        
        # Define time bounds variable
        @info "Creating time_bounds variable" size=size(time_bounds)
        # CF convention expects time_bounds(time, nb) in the file.
        # NCDatasets uses Julia's column-major ordering, so:
        # - Julia array shape (n_times, 2) with dims ("time", "nb") -> file has (nb, time)
        # - Julia array shape (2, n_times) with dims ("nb", "time") -> file has (time, nb) ✓
        # We need the second form for CF compliance.
        if size(time_bounds, 2) == 2  # Shape is (n_times, 2)
            # Transpose to (2, n_times) and use dims ("nb", "time") for correct file layout
            defVar(ds_out, "time_bounds", permutedims(time_bounds, (2, 1)), ("nb", "time"))
        elseif size(time_bounds, 1) == 2  # Shape is (2, n_times)
            # Already in correct shape, use dims ("nb", "time")
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

        defVar(ds_out, dataset.variable, var_data, output_dims,
               attrib = Dict(
                   "units" => units,
                   "long_name" => get(var_atts, "long_name", dataset.variable)
               ))
        
    finally
        close(ds_in)
        close(ds_out)
    end
    
    return ILAMBDataset(
        output_file,
        dataset.variable,
        units,
        "days since 1850-01-01",
        "noleap"
    )
end
