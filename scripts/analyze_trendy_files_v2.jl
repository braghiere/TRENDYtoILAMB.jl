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

    # Handle AD format with month names (now handled earlier with AD removal)
    month_names_pattern = r"years? since (\d+)-(\w{3})-(\d{1,2})(?:st|nd|rd|th)?"
    if occursin(month_names_pattern, unit_str)
        m = match(month_names_pattern, unit_str)
        if !isnothing(m)
            year = parse(Int, m[1])
            month_name = uppercasefirst(lowercase(m[2]))
            day = parse(Int, m[3])
            
            # Map month names to numbers
            month_map = Dict(
                "Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4,
                "May" => 5, "Jun" => 6, "Jul" => 7, "Aug" => 8,
                "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12
            )
            
            month = get(month_map, month_name, 1)
            return ("year", string(Date(year, month, day)))
        end
    end

    # Check standard patterns
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
            # Special handling for time units and conversion of AD dates
            if attr == "units" && any(d -> d == "time", dimnames(ds[var]))
                unit_str = ds[var].attrib[attr]
                # Replace AD dates with standard format
                unit_str = replace(unit_str, r"AD (\d+)" => s"\1")
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
    
    # Sort files by filename to ensure consistent order
    sort!(nc_files, by=basename)
    
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
    
    # Print some basic statistics
    println("\nQuick summary:")
    
    # Analyze time units
    time_unit_info = Dict{String, Dict{String, Int}}()
    unit_type_count = Dict{String, Int}()  # Track total count per unit type
    total_time_vars = 0
    for (file, analysis) in analyses
        for (var, info) in get(analysis, "variables", Dict())
            attrs = get(info, "attributes", Dict())
            if haskey(attrs, "units_type")
                unit_type = attrs["units_type"]
                ref_date = attrs["reference_date"]
                total_time_vars += 1
                
                # Count unit types
                unit_type_count[unit_type] = get(unit_type_count, unit_type, 0) + 1
                
                if !haskey(time_unit_info, unit_type)
                    time_unit_info[unit_type] = Dict{String, Int}()
                end
                
                if !haskey(time_unit_info[unit_type], ref_date)
                    time_unit_info[unit_type][ref_date] = 0
                end
                time_unit_info[unit_type][ref_date] += 1
            end
        end
    end
    
    println("\nTime unit analysis:")
    println("Total variables with time units: ", total_time_vars)
    
    # Sort unit types by frequency first
    sorted_unit_types = sort(collect(unit_type_count), by=x->x[2], rev=true)
    for (unit_type, total_count) in sorted_unit_types
        pct = round(total_count * 100 / total_time_vars, digits=1)
        println("\n$unit_type ($total_count variables, $pct%):")
        
        # Get and sort references for this unit type
        refs = time_unit_info[unit_type]
        sorted_refs = sort(collect(refs), by=x->x[2], rev=true)
        
        # Print reference dates and their frequencies
        for (ref_date, count) in sorted_refs
            ref_pct = round(count * 100 / total_count, digits=1)
            println("  - $ref_date: $count occurrences ($ref_pct% of $unit_type)")
        end
    end
    
    # Count and analyze variables
    var_info = Dict{String, Int}()
    var_types = Dict{String, Set{String}}()
    for (file, analysis) in analyses
        for (var, info) in get(analysis, "variables", Dict())
            # Count variable occurrences
            var_info[var] = get(var_info, var, 0) + 1
            
            # Track variable types
            var_type = get(info, "type", "unknown")
            if !haskey(var_types, var)
                var_types[var] = Set{String}()
            end
            push!(var_types[var], var_type)
        end
    end
    
    # Print variable analysis
    println("\nVariable analysis:")
    println("Total unique variables: ", length(var_info))
    println("\nMost common variables:")
    sorted_vars = sort(collect(var_info), by=x->x[2], rev=true)
    for (var, count) in sorted_vars[1:min(10, length(sorted_vars))]
        type_str = join(collect(var_types[var]), ", ")
        pct = round(count * 100 / length(nc_files), digits=1)
        println("  - $var: $count files ($pct%) [types: $type_str]")
    end
    
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
end