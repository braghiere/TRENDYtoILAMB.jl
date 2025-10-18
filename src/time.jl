"""
    parse_units(time_units::String)

Parse time units string and extract the reference year.
Handles special cases like 'years since AD 0-Jan-1st' and 'months since YYYY-MM-DD'.
"""
function parse_units(time_units::String)
    # Remove (double) suffix if present
    time_units = replace(time_units, r"\s*\(double\)" => "")
    
    # Handle "AD" prefix
    time_units = replace(time_units, "years since AD " => "years since ")
    
    # Handle bare year/yr units (no reference year specified - assume year 0)
    if time_units == "yr" || time_units == "years"
        return 0
    end
    
    # Extract year from the reference date
    year_patterns = [
        r"(?:years|months|days|yr) since (\d+)", # Basic year
        r"(?:years|months|days|yr) since (\d{4})-\d{1,2}-\d{1,2}", # ISO date format
    ]
    
    for pattern in year_patterns
        m = match(pattern, time_units)
        if m !== nothing
            return parse(Int, m[1])
        end
    end
    
    error("Could not parse reference year from units: $time_units")
end

"""
    convert_time_to_days(times::Vector{<:Any}, reference_year::Int=1850)

Convert time values to days since a reference date.
Handles both DateTime objects and numeric year values.
"""
function convert_time_to_days(times::Vector{<:Any}, reference_year::Int=1850)
    days = Vector{Int}(undef, length(times))
    
    for (i, t) in enumerate(times)
        if t isa AbstractFloat || t isa Integer
            # Handle numeric year values
            days[i] = floor(Int, (t - reference_year) * 365)
        elseif t isa NCDatasets.DateTimeNoLeap || t isa Dates.AbstractDateTime
            # For NCDatasets datetime types, just compute the offset in years and days
            days[i] = (Dates.year(t) - reference_year) * 365 + (Dates.dayofyear(t) - 1)
        else
            error("Unsupported time type: $(typeof(t))")
        end
    end
    
    return days
end

"""
    create_time_bounds(years::Vector{<:Real}, reference_year::Int=1850)

Create time bounds array for ILAMB format.
Returns an Array{Float64,2} with dimensions (n_times, 2) containing start and end days.
"""
function create_time_bounds(years::Vector{<:Real}, reference_year::Int=1850)
    n_years = length(years)
    bounds = zeros(Float64, n_years, 2)
    
    for (i, year) in enumerate(years)
        # Calculate the time at the start of the month
        bounds[i, 1] = convert_time_to_days([year], reference_year)[1]
        # For the end bound, advance by 1/12 of a year (monthly data)
        bounds[i, 2] = convert_time_to_days([year + 1/12], reference_year)[1] - 1
    end
    
    return bounds
end

"""
    create_time_bounds(datetimes::Vector, reference_year::Int=1850)

Create time bounds array for ILAMB format from DateTime objects.
Handles NCDatasets.DateTimeNoLeap and other datetime types.
Returns an Array{Float64,2} with dimensions (n_times, 2) containing start and end days.
"""
function create_time_bounds(datetimes::Vector, reference_year::Int=1850)
    # Check if we have DateTime-like objects (not numeric)
    if !isempty(datetimes) && !(eltype(datetimes) <: Real)
        # Convert datetimes to days since reference_year
        days = convert_time_to_days(datetimes, reference_year)
        
        n_times = length(days)
        bounds = zeros(Float64, n_times, 2)
        
        for i in 1:n_times
            if i == 1
                # For the first time point, estimate the start bound
                if n_times > 1
                    dt = (days[2] - days[1]) / 2
                    bounds[i, 1] = days[i] - dt
                    bounds[i, 2] = days[i] + dt
                else
                    # Only one time point - use ±15 days
                    bounds[i, 1] = days[i] - 15
                    bounds[i, 2] = days[i] + 15
                end
            elseif i == n_times
                # For the last time point
                dt = (days[i] - days[i-1]) / 2
                bounds[i, 1] = days[i] - dt
                bounds[i, 2] = days[i] + dt
            else
                # For middle points, use midpoints between adjacent times
                bounds[i, 1] = (days[i-1] + days[i]) / 2
                bounds[i, 2] = (days[i] + days[i+1]) / 2
            end
        end
        
        return bounds
    else
        # Numeric values - use the existing method
        return create_time_bounds(convert(Vector{Float64}, datetimes), reference_year)
    end
end