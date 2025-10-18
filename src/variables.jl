# Dictionary mapping TRENDY variable names to ILAMB names and metadata
const VARIABLE_MAPPINGS = Dict(
    "cVeg" => (
        name = "cVeg",
        long_name = "Carbon in Vegetation",
        units = "kg m-2",
        standard_name = "vegetation_carbon_content"
    ),
    "cSoil" => (
        name = "cSoil",
        long_name = "Carbon in Soil",
        units = "kg m-2",
        standard_name = "soil_carbon_content"
    ),
    "gpp" => (
        name = "gpp",
        long_name = "Gross Primary Production",
        units = "kg m-2 s-1",
        standard_name = "gross_primary_productivity_of_carbon"
    ),
    # Add more variables as needed
)

"""
    get_variable_metadata(trendy_var::String)

Get ILAMB-compatible metadata for a TRENDY variable.
"""
function get_variable_metadata(trendy_var::String)
    get(VARIABLE_MAPPINGS, trendy_var) do
        @warn "No metadata mapping found for variable: $trendy_var"
        (
            name = trendy_var,
            long_name = trendy_var,
            units = "unknown",
            standard_name = trendy_var
        )
    end
end