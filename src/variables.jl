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
    "npp" => (
        name = "npp",
        long_name = "Net Primary Production",
        units = "kg m-2 s-1",
        standard_name = "net_primary_productivity_of_carbon"
    ),
    "nbp" => (
        name = "nbp",
        long_name = "Net Biome Production",
        units = "kg m-2 s-1",
        standard_name = "surface_net_downward_mass_flux_of_carbon_dioxide_expressed_as_carbon_due_to_all_land_processes"
    ),
    "ra" => (
        name = "ra",
        long_name = "Autotrophic Respiration",
        units = "kg m-2 s-1",
        standard_name = "plant_respiration_carbon_flux"
    ),
    "rh" => (
        name = "rh",
        long_name = "Heterotrophic Respiration",
        units = "kg m-2 s-1",
        standard_name = "heterotrophic_respiration_carbon_flux"
    ),
    "lai" => (
        name = "lai",
        long_name = "Leaf Area Index",
        units = "1",
        standard_name = "leaf_area_index"
    ),
    "evapotrans" => (
        name = "et",
        long_name = "Evapotranspiration",
        units = "kg m-2 s-1",
        standard_name = "water_evapotranspiration_flux"
    ),
    "mrro" => (
        name = "mrro",
        long_name = "Total Runoff",
        units = "kg m-2 s-1",
        standard_name = "runoff_flux"
    ),
    "mrros" => (
        name = "mrros",
        long_name = "Surface Runoff",
        units = "kg m-2 s-1",
        standard_name = "surface_runoff_flux"
    ),
    "mrso" => (
        name = "mrso",
        long_name = "Total Soil Moisture Content",
        units = "kg m-2",
        standard_name = "mass_content_of_water_in_soil"
    ),
    "cLitter" => (
        name = "cLitter",
        long_name = "Carbon in Litter",
        units = "kg m-2",
        standard_name = "litter_carbon_content"
    ),
    "cProduct" => (
        name = "cProduct",
        long_name = "Carbon in Products",
        units = "kg m-2",
        standard_name = "carbon_content_of_products_of_anthropogenic_land_use_change"
    ),
    "burntArea" => (
        name = "burntArea",
        long_name = "Burnt Area Fraction",
        units = "1",
        standard_name = "burned_area_fraction"
    ),
    "fFire" => (
        name = "fFire",
        long_name = "Carbon Emission from Fire",
        units = "kg m-2 s-1",
        standard_name = "surface_upward_mass_flux_of_carbon_dioxide_expressed_as_carbon_due_to_emission_from_fires"
    ),
    "tas" => (
        name = "tas",
        long_name = "Near-Surface Air Temperature",
        units = "K",
        standard_name = "air_temperature"
    ),
    "pr" => (
        name = "pr",
        long_name = "Precipitation",
        units = "kg m-2 s-1",
        standard_name = "precipitation_flux"
    ),
    "rsds" => (
        name = "rsds",
        long_name = "Surface Downwelling Shortwave Radiation",
        units = "W m-2",
        standard_name = "surface_downwelling_shortwave_flux_in_air"
    ),
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