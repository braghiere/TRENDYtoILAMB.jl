"""
Utilities for standardizing ILAMB filename date ranges.

ILAMB's ModelResult class searches for files using a regex pattern based on
the first file it finds. If different variables have different date ranges in
their filenames, ILAMB won't find them all.

Solution: Use a standardized date range in filenames per model, even if the
actual data coverage varies. ILAMB handles missing data with fill values.
"""

using NCDatasets
using Dates

"""
    get_model_date_range(model_dir::String) -> (start_date::String, end_date::String)

Scan all NetCDF files for a model to determine a standardized date range.

Returns:  
- start_date: Earliest date in format "YYYYMM" (e.g., "170001")
- end_date: Latest date in format "YYYYMM" (e.g., "202312")

Strategy:
1. Find the earliest start date across all files
2. Find the latest end date across all files  
3. Return this as the "standard" range for filename generation

This ensures all files for a model have the same date pattern in filenames,
allowing ILAMB's file discovery to work properly.
"""
function get_model_date_range(model_dir::String)
    earliest_start = Date(3000, 1, 1)  # Far future
    latest_end = Date(1000, 1, 1)      # Far past
    
    nc_files = filter(f -> endswith(f, ".nc"), readdir(model_dir, join=true))
    isempty(nc_files) && return ("170001", "202312")  # Default range
    
    for file in nc_files
        try
            ds = Dataset(file, "r")
            
            # Skip if no time dimension
            if !haskey(ds, "time")
                close(ds)
                continue
            end
            
            time_var = ds["time"]
            time_vals = time_var[:]
            
            # Parse time units
            units_str = get(time_var.attrib, "units", "")
            calendar = get(time_var.attrib, "calendar", "standard")
            
            # Extract reference date from units (e.g., "days since 1700-01-01")
            m = match(r"(\w+) since (\d{4})-(\d{2})-(\d{2})", units_str)
            if m === nothing
                close(ds)
                continue
            end
            
            ref_year = parse(Int, m.captures[2])
            ref_month = parse(Int, m.captures[3])
            ref_day = parse(Int, m.captures[4])
            ref_date = Date(ref_year, ref_month, ref_day)
            
            # Calculate actual start and end dates
            first_time = time_vals[1]
            last_time = time_vals[end]
            
            # Convert time values to dates (handle days/months units)
            if occursin("day", lowercase(units_str))
                start_date = ref_date + Day(round(Int, first_time))
                end_date = ref_date + Day(round(Int, last_time))
            elseif occursin("month", lowercase(units_str))
                start_date = ref_date + Month(round(Int, first_time))
                end_date = ref_date + Month(round(Int, last_time))
            else
                close(ds)
                continue
            end
            
            # Track earliest/latest
            if start_date < earliest_start
                earliest_start = start_date
            end
            if end_date > latest_end
                latest_end = end_date
            end
            
            close(ds)
        catch e
            @warn "Error reading $file for date range: $e"
            continue
        end
    end
    
    # Format as YYYYMM
    start_str = string(year(earliest_start)) * lpad(month(earliest_start), 2, '0')
    end_str = string(year(latest_end)) * lpad(month(latest_end), 2, '0')
    
    return (start_str, end_str)
end

"""
    get_standard_date_range() -> (String, String)

Return a fixed standard date range for all TRENDY models.

Uses: 170001-202312 (Jan 1700 - Dec 2023)

This is the most common range across TRENDY v13 models and ensures
maximum compatibility with ILAMB.
"""
function get_standard_date_range()
    return ("170001", "202312")
end
