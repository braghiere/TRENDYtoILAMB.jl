# ILAMB Format

The ILAMB (International Land Model Benchmarking) format is a standardized NetCDF format used for model benchmarking.

## File Structure

ILAMB files require:

- Spatial dimensions: `lat`, `lon`
- Temporal dimension: `time`
- Time bounds dimension: `nb`
- Variables:
  - Main variable (e.g., `cVeg`)
  - Coordinates (`lat`, `lon`, `time`)
  - `time_bounds`

## Units

ILAMB requires CF-compliant units:
- Carbon pools: `kg m-2`
- Fluxes: `kg m-2 s-1`
- Time: `days since YYYY-MM-DD`

## Example

Here's an example of an ILAMB-compatible file structure:

```
netcdf CLM5.0_S3_cVeg_ILAMB {
dimensions:
    lat = 192 ;
    lon = 288 ;
    time = 324 ;
    nb = 2 ;
variables:
    float cVeg(time, lat, lon) ;
        cVeg:units = "kg m-2" ;
        cVeg:long_name = "Carbon in Vegetation" ;
    double lat(lat) ;
        lat:units = "degrees_north" ;
    double lon(lon) ;
        lon:units = "degrees_east" ;
    double time(time) ;
        time:units = "days since 1850-01-01" ;
        time:calendar = "noleap" ;
        time:bounds = "time_bounds" ;
    double time_bounds(time, nb) ;
}
```