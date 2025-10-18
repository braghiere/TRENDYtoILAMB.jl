"""
    convert_time_to_days(years::Vector{Int}, reference_year::Int=1850)

Convert years to days since a reference date.
"""
function convert_time_to_days(years::Vector{<:Integer}, reference_year::Int=1850)
    days = (Int.(years) .- reference_year) .* 365
    return days
end

"""
    create_time_bounds(years::Vector{Int}, reference_year::Int=1850)

Create time bounds array for ILAMB format.
Returns an Array{Float64,2} with dimensions (n_times, 2) containing start and end days.
"""
function create_time_bounds(years::Vector{<:Integer}, reference_year::Int=1850)
    n_years = length(years)
    bounds = zeros(Float64, n_years, 2)
    
    for (i, year) in enumerate(years)
        bounds[i, 1] = convert_time_to_days([year], reference_year)[1]
        bounds[i, 2] = convert_time_to_days([Int(year) + 1], reference_year)[1] - 1
    end
    
    return bounds
end