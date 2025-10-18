# TRENDY Format

The TRENDY format refers to the standardized NetCDF file format used in the TRENDY (Trends in Net Land-Atmosphere Carbon Exchange) model intercomparison project.

## File Structure

TRENDY files typically contain:

- Spatial dimensions: `lat`, `lon`
- Temporal dimension: `time` (in years)
- Variables with attributes:
  - Main variable (e.g., `cVeg`)
  - Coordinates (`lat`, `lon`, `time`)

## Units

TRENDY files often use the following units:
- Carbon pools: `gC/m^2`
- Fluxes: `gC/m^2/yr`
- Time: `years`

## Example

Here's an example of a typical TRENDY file structure:

```
netcdf CLM6.0_S3_cVeg {
dimensions:
    lat = 192 ;
    lon = 288 ;
    time = 324 ;
variables:
    float cVeg(time, lat, lon) ;
        cVeg:units = "gC/m^2" ;
        cVeg:long_name = "Carbon in Vegetation" ;
    double lat(lat) ;
        lat:units = "degrees_north" ;
    double lon(lon) ;
        lon:units = "degrees_east" ;
    int time(time) ;
        time:units = "yr" ;
}
```