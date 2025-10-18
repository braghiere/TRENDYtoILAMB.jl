using NCDatasets
using JSON
using Printf
using Statistics
using Dates

using NCDatasets: Dataset, dimnames, unlimited

"""
Normalize a time unit string to a standard format.
Returns a tuple of (unit, reference_date).
"""
function normalize_time_unit(unit_str::AbstractString)
    # Common patterns
    year_patterns = [
        r"years? since (\d{1,4})-(\d{1,2})-(\d{1,2})",
        r"years? since AD (\d{1,4})-(\w{3})-(\d{1,2})",
        r"years? since (\d{1,4})-(\d{1,2})-(\d{1,2}) \d{2}:\d{2}:\d{2}"
    ]
    day_patterns = [
        r"days since (\d{1,4})-(\d{1,2})-(\d{1,2})",
        r"days since (\d{1,4})-(\d{1,2})-(\d{1,2}) \d{2}:\d{2}:\d{2}"
    ]
    month_patterns = [
        r"months? since (\d{1,4})-(\d{1,2})-(\d{1,2})",
        r"months? since (\d{1,4})-(\d{1,2})-(\d{1,2}) \d{2}:\d{2}:\d{2}"
    ]
    hour_patterns = [
        r"hours? since (\d{1,4})-(\d{1,2})-(\d{1,2})",
        r"hours? since (\d{1,4})-(\d{1,2})-(\d{1,2}) \d{2}:\d{2}:\d{2}"
    ]

    # Special formats
    if occursin(r"year as %Y\.%f", unit_str)
        return ("year", "decimal")
    elseif occursin(r"month as %Y%m\.%f", unit_str)
        return ("month", "decimal")
    elseif occursin(r"day as %Y%m%d\.%f", unit_str)
        return ("day", "decimal")
    elseif unit_str == "yr"
        return ("year", "unspecified")
    end

    # Check each pattern
    for (patterns, unit) in [(year_patterns, "year"), 
                            (day_patterns, "day"),
                            (month_patterns, "month"),
                            (hour_patterns, "hour")]
        for pattern in patterns
            m = match(pattern, unit_str)
            if !isnothing(m)
                try
                    date = Date(parse(Int, m[1]), parse(Int, m[2]), parse(Int, m[3]))
                    return (unit, string(date))
                catch e
                    @warn "Could not parse date from: $unit_str" exception=e
                    return (unit, "invalid_date")
                end
            end
        end
    end
    
    return ("unknown", unit_str)
end

"""
Normalize a time unit string to a standard format.
Returns a tuple of (unit, reference_date).
"""
function normalize_time_unit(unit_str::AbstractString)
    # Common patterns
    year_patterns = [
        r"years? since (\d{1,4})-(\d{1,2})-(\d{1,2})",
        r"years? since AD (\d{1,4})-(\w{3})-(\d{1,2})",
        r"years? since (\d{1,4})-(\d{1,2})-(\d{1,2}) \d{2}:\d{2}:\d{2}"
    ]
    day_patterns = [
        r"days since (\d{1,4})-(\d{1,2})-(\d{1,2})",
        r"days since (\d{1,4})-(\d{1,2})-(\d{1,2}) \d{2}:\d{2}:\d{2}"
    ]
    month_patterns = [
        r"months? since (\d{1,4})-(\d{1,2})-(\d{1,2})",
        r"months? since (\d{1,4})-(\d{1,2})-(\d{1,2}) \d{2}:\d{2}:\d{2}"
    ]
    hour_patterns = [
        r"hours? since (\d{1,4})-(\d{1,2})-(\d{1,2})",
        r"hours? since (\d{1,4})-(\d{1,2})-(\d{1,2}) \d{2}:\d{2}:\d{2}"
    ]

    # Special formats
    if occursin(r"year as %Y\.%f", unit_str)
        return ("year", "decimal")
    elseif occursin(r"month as %Y%m\.%f", unit_str)
        return ("month", "decimal")
    elseif occursin(r"day as %Y%m%d\.%f", unit_str)
        return ("day", "decimal")
    elseif unit_str == "yr"
        return ("year", "unspecified")
    end

    # Check each pattern
    for (patterns, unit) in [(year_patterns, "year"), 
                            (day_patterns, "day"),
                            (month_patterns, "month"),
                            (hour_patterns, "hour")]
        for pattern in patterns
            m = match(pattern, unit_str)
            if !isnothing(m)
                try
                    date = Date(parse(Int, m[1]), parse(Int, m[2]), parse(Int, m[3]))
                    return (unit, string(date))
                catch e
                    @warn "Could not parse date from: $unit_str" exception=e
                    return (unit, "invalid_date")
                end
            end
        end
    end
    
    return ("unknown", unit_str)
end

"""
Analyze a single NetCDF file and return a dictionary of its properties
"""
function analyze_netcdf(filepath::String)
    ds = Dataset(filepath)
    analysis = Dict{String, Any}()
    
    # Get filename
    analysis["filename"] = basename(filepath)
    
    # Analyze dimensions
    dims = Dict{String, Any}()
    for dim in dimnames(ds)
        dims[dim] = Dict(
            "size" => size(ds.dim[dim]),
            "unlimited" => dim == unlimited(ds)
        )
    end
    analysis["dimensions"] = dims
    
    # Analyze variables
    vars = Dict{String, Any}()
    for var in keys(ds)
        var_dict = Dict{String, Any}()
        var_dict["dimensions"] = dimnames(ds[var])
        var_dict["type"] = string(eltype(ds[var]))
        var_dict["size"] = size(ds[var])
        
        # Get all attributes
        attrs = Dict{String, Any}()
        for attr in keys(ds[var].attrib)
            # Special handling for time units
            if attr == "units" && any(d -> d == "time", dimnames(ds[var]))
                unit_str = ds[var].attrib[attr]
                unit_type, ref_date = normalize_time_unit(unit_str)
                attrs["units_raw"] = unit_str
                attrs["units_type"] = unit_type
                attrs["reference_date"] = ref_date
            else
                attrs[attr] = ds[var].attrib[attr]
            end
        end
        var_dict["attributes"] = attrs
        
        # Sample some statistics if numeric
        if eltype(ds[var]) <: Number && !startswith(var, "LATLON")
            try
                data = ds[var][:]
                valid_data = data[.!ismissing.(data)]
                if !isempty(valid_data)
                    var_dict["statistics"] = Dict(
                        "min" => Float64(minimum(valid_data)),
                        "max" => Float64(maximum(valid_data)),
                        "mean" => Float64(mean(valid_data))
                    )
                end
            catch e
                @warn "Could not compute statistics for $var" exception=e
            end
        end
        
        vars[var] = var_dict
    end
    analysis["variables"] = vars
    
    # Get global attributes
    global_attrs = Dict{String, Any}()
    for attr in keys(ds.attrib)
        global_attrs[attr] = ds.attrib[attr]
    end
    analysis["global_attributes"] = global_attrs
    
    close(ds)
    return analysis
end

"""
Analyze all NetCDF files in a directory recursively
"""
function analyze_trendy_directory(dir::String, output_file::String)
    # Find all .nc files recursively
    nc_files = String[]
    for (root, dirs, files) in walkdir(dir)
        for file in files
            if endswith(file, ".nc")
                push!(nc_files, joinpath(root, file))
            end
        end
    end
    
    # Analyze each file
    analyses = Dict{String, Any}()
    for (i, file) in enumerate(nc_files)
        @printf("Analyzing file %d/%d: %s\n", i, length(nc_files), basename(file))
        try
            analyses[file] = analyze_netcdf(file)
        catch e
            @warn "Failed to analyze file: $file" exception=e
        end
    end
    
    # Save results
    open(output_file, "w") do f
        JSON.print(f, analyses, 2)  # indent=2 for pretty printing
    end
    
    # Print summary
    println("\nAnalysis complete!")
    println("Total files analyzed: ", length(nc_files))
    println("Results saved to: ", output_file)
    
    return analyses
end

# Main execution
if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 1
        println("Usage: julia analyze_trendy_files.jl <trendy_directory>")
        exit(1)
    end
    
    trendy_dir = ARGS[1]
    output_file = "trendy_analysis.json"
    
    analyses = analyze_trendy_directory(trendy_dir, output_file)
    
    # Print some basic statistics
    println("\nQuick summary:")
    
    # Count unique time units
    time_units = Set{String}()
    for (file, analysis) in analyses
        if haskey(analysis["variables"], "time") && 
           haskey(analysis["variables"]["time"]["attributes"], "units")
            push!(time_units, analysis["variables"]["time"]["attributes"]["units"])
        end
    end
    println("\nUnique time units found:")
    for unit in time_units
        println("  - ", unit)
    end
    
    # Count unique variable names
    var_names = Set{String}()
    for (file, analysis) in analyses
        union!(var_names, keys(analysis["variables"]))
    end
    println("\nTotal unique variables found: ", length(var_names))
    println("Sample of variables:")
    for var in Iterators.take(var_names, 10)
        println("  - ", var)
    end
end