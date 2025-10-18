"""
    convert_to_ilamb(dataset::TRENDYDataset; output_dir::String=".")

Convert a TRENDY dataset to ILAMB format.
"""
function convert_to_ilamb(dataset::TRENDYDataset; output_dir::String=".")
    # Open input dataset
    ds_in = Dataset(dataset.path)
    
    # Create output filename and ensure directory exists
    output_file = joinpath(output_dir, 
                          "$(dataset.model)_$(dataset.simulation)_$(dataset.variable)_ILAMB.nc")
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
        
        # Handle time dimension
        years = ds_in["time"][:]
        time_units = ds_in["time"].attrib["units"]
        @info "Raw time values:" first_10_years=years[1:10] time_units=time_units
        
        # Parse reference year from units
        reference_year = parse_units(time_units)
        @info "Using reference year" reference_year=reference_year
        
        # Convert to days since 1850
        days = convert_time_to_days(years, reference_year)
        time_bounds = create_time_bounds(years, reference_year)
        
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
        defVar(ds_out, "time_bounds", time_bounds, ("time", "nb"))
        
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