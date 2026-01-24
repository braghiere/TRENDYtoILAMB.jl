# Module-level constants for time calculations
const DAYS_PER_MONTH_APPROX = 365.0 / 12.0  # ~30.4167 days per month (365/12)

# Days per month for noleap calendar (no Feb 29)
const DAYS_PER_MONTH_NOLEAP = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

"""
    days_since_1850_for_month_start(year::Int, month::Int)

Calculate days since 1850-01-01 for the start of a given month (noleap calendar).
"""
function days_since_1850_for_month_start(year::Int, month::Int)
    # Days from 1850 to start of year
    days = (year - 1850) * 365
    # Add days for months before this one
    for m in 1:(month-1)
        days += DAYS_PER_MONTH_NOLEAP[m]
    end
    return days
end

"""
    days_since_1850_for_month_end(year::Int, month::Int)

Calculate days since 1850-01-01 for the end of a given month (noleap calendar).
Returns the start of the next month (exclusive end bound), following CF conventions.
"""
function days_since_1850_for_month_end(year::Int, month::Int)
    # End bound is the start of the next month (exclusive)
    if month == 12
        return days_since_1850_for_month_start(year + 1, 1)
    else
        return days_since_1850_for_month_start(year, month + 1)
    end
end

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
        r"(?:years|months|days|hours|yr) since (\d+)", # Basic year
        r"(?:years|months|days|hours|yr) since (\d{4})-\d{1,2}-\d{1,2}", # ISO date format
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

Convert time values to days since 1850-01-01 (noleap calendar).
Handles both DateTime objects and numeric year values.
For monthly data, returns the mid-month day value.
"""
function convert_time_to_days(times::Vector{<:Any}, reference_year::Int=1850; time_units::Union{Nothing,String}=nothing, calendar::String="noleap")
    days = Vector{Float64}(undef, length(times))

    # Detect base unit if provided (days/months/years/hours)
    base_unit::Symbol = :years
    if time_units !== nothing
        units_lower = lowercase(time_units)
        if occursin("days since", units_lower)
            base_unit = :days
        elseif occursin("hours since", units_lower)
            base_unit = :hours
        elseif occursin("months since", units_lower)
            base_unit = :months
        elseif occursin("years since", units_lower) || occursin("yr since", units_lower)
            base_unit = :years
        end
    end

    for (i, t) in enumerate(times)
        if t isa AbstractFloat || t isa Integer
            # Numeric value: interpret according to units
            if base_unit == :days
                offset_days = float(t)
                days[i] = offset_days + (reference_year - 1850) * 365
            elseif base_unit == :hours
                offset_days = float(t) / 24
                days[i] = offset_days + (reference_year - 1850) * 365
            elseif base_unit == :months
                month_index = round(Int, t)
                year = reference_year + div(month_index, 12)
                month = (month_index % 12) + 1
                start_day = days_since_1850_for_month_start(year, month)
                days_in_month = DAYS_PER_MONTH_NOLEAP[month]
                days[i] = start_day + days_in_month / 2
            else
                # Treat as years since reference_year
                absolute_year = reference_year + float(t)
                days[i] = (absolute_year - 1850) * 365
            end
        elseif t isa NCDatasets.CFTime.AbstractCFDateTime || t isa Dates.AbstractDateTime
            # For NCDatasets/CFTime datetime types (DateTimeNoLeap, DateTime360Day, etc.)
            # Compute proper mid-month time value for noleap calendar
            year = Dates.year(t)
            month = Dates.month(t)

            # Get the start of the month and add half the month's days
            month_start = days_since_1850_for_month_start(year, month)
            days_in_month = DAYS_PER_MONTH_NOLEAP[month]
            # Use floor to get integer mid-month day (matching FLUXCOM convention)
            days[i] = month_start + div(days_in_month, 2)
        else
            error("Unsupported time type: $(typeof(t))")
        end
    end

    return days
end

"""
    continuous_bounds_from_time(days::Vector{<:Real})

Create contiguous time bounds given time coordinate centers (days since 1850).
Bounds are midpoints between adjacent times, with first/last extrapolated.
Returns Array{Float64,2} of size (n_times, 2).
"""
function continuous_bounds_from_time(days::Vector{<:Real})
    n = length(days)
    bounds = zeros(Float64, n, 2)

    if n == 1
        half_width = 15.5  # rough half-month for single point
        bounds[1, 1] = days[1] - half_width
        bounds[1, 2] = days[1] + half_width
        return bounds
    end

    for i in 1:n
        if i == 1
            half_span = (days[2] - days[1]) / 2
            bounds[i, 1] = days[1] - half_span
            bounds[i, 2] = days[1] + half_span
        elseif i == n
            half_span = (days[n] - days[n-1]) / 2
            bounds[i, 1] = days[i] - half_span
            bounds[i, 2] = days[i] + half_span
        else
            bounds[i, 1] = (days[i-1] + days[i]) / 2
            bounds[i, 2] = (days[i] + days[i+1]) / 2
        end
    end

    return bounds
end

"""
    create_time_bounds(years::Vector{<:Real}, reference_year::Int=1850)

Create time bounds array for ILAMB format.
Returns an Array{Float64,2} with dimensions (n_times, 2) containing start and end days.
For yearly data (when consecutive values differ by ~1), creates yearly bounds.
For monthly data (when consecutive values differ by ~1/12), creates monthly bounds.
"""
function create_time_bounds(years::Vector{<:Real}, reference_year::Int=1850)
    days = convert_time_to_days(years, reference_year; time_units="years since $(reference_year)-01-01")
    return continuous_bounds_from_time(days)
end

"""
    create_time_bounds(datetimes::Vector, reference_year::Int=1850)

Create time bounds array for ILAMB format from DateTime objects.
Handles NCDatasets.DateTimeNoLeap and other datetime types.
Returns an Array{Float64,2} with dimensions (n_times, 2) containing start and end days.
Uses proper calendar month boundaries for noleap calendar.
"""
function create_time_bounds(datetimes::Vector, reference_year::Int=1850)
    # Check if we have DateTime-like objects (not numeric)
    if !isempty(datetimes) && !(eltype(datetimes) <: Real)
        n_times = length(datetimes)
        bounds = zeros(Float64, n_times, 2)

        for i in 1:n_times
            dt = datetimes[i]
            year = Dates.year(dt)
            month = Dates.month(dt)

            # Use proper calendar month boundaries
            bounds[i, 1] = days_since_1850_for_month_start(year, month)
            bounds[i, 2] = days_since_1850_for_month_end(year, month)
        end

        return bounds
    else
        # Numeric values - use the existing method
        return create_time_bounds(convert(Vector{Float64}, datetimes), reference_year)
    end
end

"""
    create_time_bounds_from_days(days::Vector{Int})

Create time bounds array for monthly data from days since 1850.
Returns bounds as a 2 x n_times array (start_days, end_days for each month).
"""
function create_time_bounds_from_days(days::Vector{Int})
    return continuous_bounds_from_time(days)
end

"""
    yearmonth_index_to_days(time_values::Vector{<:Real})

Treat numeric time values as contiguous month indices (1 → Jan of reference year 0).
Returns a tuple `(days, time_bounds)` where `days` are mid-month days since 1850-01-01
and `time_bounds` has shape (n, 2) with start/end days.
"""
function yearmonth_index_to_days(time_values::Vector{<:Real})
    n_months = length(time_values)
    days = zeros(Float64, n_months)
    time_bounds = zeros(Float64, n_months, 2)
    for i in 1:n_months
        v = round(Int, time_values[i])
        y = div(v, 12)
        m = v - y * 12
        if m == 0
            y -= 1
            m = 12
        end
        sday = days_since_1850_for_month_start(y, m)
        eday = days_since_1850_for_month_end(y, m)
        days[i] = sday + (eday - sday) / 2
        time_bounds[i, 1] = sday
        time_bounds[i, 2] = eday
    end
    return days, time_bounds
end

"""
    days_to_year_month(day::Real)

Approximate conversion from days since 1850-01-01 to (year, month) in a noleap calendar.
"""
function days_to_year_month(day::Real)
    year = 1850 + floor(Int, day / 365)
    day_in_year = day - (year - 1850) * 365
    month = max(1, min(12, ceil(Int, (day_in_year / 365) * 12)))
    return year, month
end
