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
    time_values = ds_in["time"][:]
    
    # Get time units with fallback
    time_units = get(ds_in["time"].attrib, "units", "days since 1850-01-01")
    reference_year = parse_units(time_units)
    
    # Check if time values are simple month indices (1, 2, 3, ... n)
    # This happens with CARDAMOM which lacks proper time units
    is_month_index = (length(time_values) > 1 && 
                     time_values[1] == 1 && 
                     time_values[2] == 2 &&
                     all(diff(time_values) .== 1))
    
    if is_month_index && dataset.model == "CARDAMOM"
        # CARDAMOM: Time values are month indices starting from 1
        # CARDAMOM data starts in January 2003
        n_months = length(time_values)
        start_year = 2003
        start_month = 1
        
        # Calculate end year and month
        total_months = start_month - 1 + n_months
        end_year = start_year + div(total_months - 1, 12)
        end_month = ((total_months - 1) % 12) + 1
        
        # Format dates as YYYYMM
        start_date = string(start_year) * lpad(start_month, 2, '0')
        end_date = string(end_year) * lpad(end_month, 2, '0')
        
        # Convert month indices to days since 1850 for internal processing
        days = zeros(Int, n_months)
        for i in 1:n_months
            month_offset = i - 1
            year = start_year + div(month_offset, 12)
            month = (month_offset % 12) + 1
            # Days since 1850-01-01 to the middle of this month
            days_to_year = (year - 1850) * 365
            days_to_month = floor(Int, (month - 0.5) * 365.0 / 12.0)
            days[i] = days_to_year + days_to_month
        end
        
        time_bounds = create_time_bounds_from_days(days)
    else
        # Normal case: convert time values using the standard method
        days = convert_time_to_days(time_values, reference_year)
        time_bounds = create_time_bounds(time_values, reference_year)
        
        # Calculate start and end dates
        # If time_values are already datetime objects, extract year/month directly
        if !isempty(time_values) && (time_values[1] isa NCDatasets.CFTime.AbstractCFDateTime || 
                                      time_values[1] isa Dates.AbstractDateTime)
            start_year = Dates.year(time_values[1])
            start_month = Dates.month(time_values[1])
            end_year = Dates.year(time_values[end])
            end_month = Dates.month(time_values[end])
        else
            # Fallback: calculate from days since 1850
            start_days_since_1850 = days[1]
            start_years_from_1850 = start_days_since_1850 / 365.0
            start_year = 1850 + floor(Int, start_years_from_1850)
            start_day_in_year = start_days_since_1850 - (start_year - 1850) * 365.0
            start_month = max(1, min(12, ceil(Int, (start_day_in_year / 365.0) * 12)))
            if start_month == 0
                start_month = 1
            end
            
            end_days_since_1850 = days[end]
            end_years_from_1850 = end_days_since_1850 / 365.0
            end_year = 1850 + floor(Int, end_years_from_1850)
            end_day_in_year = end_days_since_1850 - (end_year - 1850) * 365.0
            end_month = max(1, min(12, ceil(Int, (end_day_in_year / 365.0) * 12)))
            if end_month == 0
                end_month = 12
            end
        end
        
        # Format dates as YYYYMM
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
        units = get(var_atts, "units", "unknown")
        units = standardize_units(units)
        @info "Variable metadata" variable=dataset.variable units=units
        
        # Get dimension sizes first
        dim_sizes = Dict{String,Int}()
        for name in dimnames(ds_in)
            dim_sizes[name] = length(ds_in[name])
        end
        @info "Input dimensions:" dim_sizes
        
        # Define dimensions in a specific order with strict error handling
        spatial_dims = ["lat", "lon"]
        @info "Defining spatial dimensions"
        for dim in spatial_dims
            if haskey(dim_sizes, dim)
                try
                    @info "Defining $dim dimension" size=dim_sizes[dim]
                    if !(dim in keys(ds_out.dim))
                        defDim(ds_out, dim, dim_sizes[dim])
                        @info "Successfully defined $dim dimension"
                    else
                        @warn "$dim dimension already exists"
                    end
                catch e
                    @error "Failed to define $dim dimension" exception=(e, catch_backtrace())
                    rethrow(e)
                end
            end
        end
        
        # Define time dimension with error handling
        @info "Defining time dimension" size=dim_sizes["time"]
        try
            if !("time" in keys(ds_out.dim))
                defDim(ds_out, "time", dim_sizes["time"])
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
        @info "Creating time_bounds variable"
        # time_bounds should be (nb, time) from create_time_bounds_from_days
        # but defVar expects (time, nb), so we need to transpose if needed
        if size(time_bounds, 1) == 2  # It's (2, n_times), need to transpose
            defVar(ds_out, "time_bounds", permutedims(time_bounds, (2, 1)), ("time", "nb"))
        else
            defVar(ds_out, "time_bounds", time_bounds, ("time", "nb"))
        end
        
        # Copy lat/lon coordinates
        if haskey(ds_in, "lat")
            lat = ds_in["lat"][:]
            defVar(ds_out, "lat", lat, ("lat",),
                   attrib = Dict("units" => "degrees_north"))
        end
        
        if haskey(ds_in, "lon")
            lon = ds_in["lon"][:]
            defVar(ds_out, "lon", lon, ("lon",),
                   attrib = Dict("units" => "degrees_east"))
        end
        
        # Copy main variable data
        var_data = ds_in[dataset.variable][:]
        @info "Creating main variable" variable=dataset.variable
        defVar(ds_out, dataset.variable, var_data, dimnames(ds_in[dataset.variable]),
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