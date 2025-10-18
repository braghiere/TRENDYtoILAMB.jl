#=
Convert TRENDY NetCDF files to ILAMB format

This script processes TRENDY model output files and converts them to the format
required by the International Land Model Benchmarking (ILAMB) system.

TRENDY Dataset Characteristics (based on analysis of TRENDYv13):
- Total files: ~840 NetCDF files across multiple models and simulations
- Models: Various (CABLE-POP, CLASSIC, CLM5, DLEM, IBIS, ISAM, JSBACH, JULES, 
          LPJ-GUESS, LPJmL, LPJwsl, LPX-Bern, OCN, ORCHIDEE, SDGVM, VISIT)
- Simulations: S0, S1, S2, S3 (different forcing scenarios)

Time Representation Challenges:
- Time units vary significantly:
  * 35% use "days since YYYY-MM-DD"
  * 6.6% use "years since YYYY-MM-DD"
  * 4.4% use "months since YYYY-MM-DD"
  * 4.1% use "hours since YYYY-MM-DD"
  * 50% have non-standard or missing time units
- Reference dates vary: 1700-01-01 (most common), 0001-01-01, 1699-12-31, etc.
- Some files use AD format: "years since AD 1700-Jan-1st"

Spatial Representation:
- Variable names: lat/latitude, lon/longitude (both used)
- Grid sizes vary by model
- Most common variable: "time" (96.5% of files)

Known Issues:
- Some files may be corrupted (HDF errors)
- Time unit parsing requires robust error handling
- Missing or malformed metadata in some files

Output Format:
- ILAMB-compliant NetCDF files
- Standardized time representation
- Consistent variable naming and metadata
=#

using TRENDYtoILAMB
using NCDatasets
using Printf

"""
Convert all TRENDY files in a directory to ILAMB format.

Based on analysis of TRENDYv13 dataset:
- 840 total NetCDF files across multiple models
- Time units vary: days (35%), years (6.6%), months (4.4%), hours (4.1%), unknown (49.8%)
- Reference dates vary: 1700-01-01 (most common), 0001-01-01, 1699-12-31, etc.
- Some files may be corrupted and will be skipped
"""
function convert_all_trendy_files(trendy_dir::String; output_base::String="output")
    # List of variables that ILAMB uses (based on ILAMB benchmarking requirements)
    ilamb_vars = [
        # Carbon cycle fluxes
        "gpp", "nbp", "npp", "ra", "rh", "lai", 
        # Hydrology
        "mrro", "mrros", "mrso", "evapotrans",
        # Carbon pools
        "cSoil", "cVeg", "cLitter", "cProduct",
        # Fire
        "burntArea", "fFire",
        # Forcing variables (used in ILAMB SoilCarbon and other confrontations)
        "tas",    # Near-surface air temperature
        "pr",     # Precipitation
        "rsds",   # Surface downward shortwave radiation
        # Add more ILAMB variables here as needed
    ]

    # Get all model directories
    models = filter(x -> isdir(joinpath(trendy_dir, x)) && !startswith(x, "."), readdir(trendy_dir))
    
    # Statistics tracking
    total_files = 0
    converted_files = 0
    failed_files = String[]
    skipped_files = String[]  # Track skipped files (non-ILAMB vars, corrupted, etc.)
    successful_vars = Dict{String,Int}()  # Track success by variable
    error_types = Dict{String,Int}()  # Track types of errors encountered
    
    for model in models
        println("\nProcessing model: $model")
        model_dir = joinpath(trendy_dir, model)
        
        # Process each simulation type (S0-S3)
        for sim in ["S0", "S1", "S2", "S3"]
            sim_dir = joinpath(model_dir, sim)
            
            # Skip if simulation directory doesn't exist
            !isdir(sim_dir) && continue
            
            # Create output directory for this model (no simulation subdirectory)
            output_dir = joinpath(output_base, model)
            mkpath(output_dir)
            
            # Process only ILAMB-relevant NetCDF files
            nc_files = filter(x -> endswith(x, ".nc"), readdir(sim_dir))
            
            for file in nc_files
                # Extract variable name from filename
                # Assuming format: ModelName_SimType_Variable.nc
                parts = split(basename(file), "_")
                if length(parts) < 3
                    println("  ⚠️  Skipping $file (unexpected filename format)")
                    push!(skipped_files, joinpath(model, sim, file))
                    continue
                end
                
                var = parts[end][1:end-3]  # Remove .nc extension
                
                # Skip if not an ILAMB variable
                if !(lowercase(var) in lowercase.(ilamb_vars))
                    push!(skipped_files, joinpath(model, sim, file))
                    continue
                end
                
                total_files += 1
                input_file = joinpath(sim_dir, file)
                println("  Converting $file (ILAMB variable: $var)...")
                
                try
                    # Quick validation: try opening the file first
                    println("    📖 Validating NetCDF file...")
                    try
                        NCDataset(input_file) do ds
                            # Check if file has time dimension
                            if !("time" in keys(ds.dim))
                                error("No time dimension found")
                            end
                        end
                    catch e
                        if isa(e, ErrorException) && occursin("NetCDF: HDF error", string(e))
                            error("Corrupted NetCDF file (HDF error)")
                        end
                        rethrow(e)
                    end
                    
                    println("    📖 Reading input file...")
                    dataset = TRENDYDataset(
                        input_file,
                        model,
                        sim,
                        var
                    )
                    
                    println("    🔄 Converting to ILAMB format...")
                    ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
                    
                    # Get output file size
                    output_file = ilamb_dataset.path
                    file_size = filesize(output_file)
                    
                    println("    ✓ Created $(basename(output_file)) ($(round(file_size/1024/1024, digits=2)) MB)")
                    
                    println("    🔍 Verifying conversion...")
                    verify_conversion(dataset, ilamb_dataset)
                    
                    # Analyze the output file
                    ds = NCDataset(output_file)
                    dims = dimnames(ds)
                    vars = keys(ds)
                    println("    📊 Output file stats:")
                    println("       - Dimensions: $dims")
                    println("       - Variables: $vars")
                    println("       - Time points: $(length(ds["time"]))")
                    close(ds)
                    
                    converted_files += 1
                    successful_vars[var] = get(successful_vars, var, 0) + 1
                    
                    # Force garbage collection every file to prevent memory buildup
                    GC.gc()
                    
                    # Aggressive GC every 10 files
                    if converted_files % 10 == 0
                        println("    🗑️  Running garbage collection ($(converted_files) files converted)...")
                        GC.gc(true)
                    end
                    
                catch e
                    error_type = string(typeof(e))
                    error_types[error_type] = get(error_types, error_type, 0) + 1
                    
                    println("    ❌ Error converting $file:")
                    println("       $(typeof(e)): $e")
                    
                    # Provide helpful error context
                    if isa(e, ErrorException)
                        if occursin("NetCDF: HDF error", string(e))
                            println("       💡 This appears to be a corrupted NetCDF file")
                        elseif occursin("No time dimension", string(e))
                            println("       💡 File lacks required time dimension")
                        elseif occursin("time", lowercase(string(e)))
                            println("       💡 Time-related error (check time units/calendar)")
                        end
                    end
                    
                    push!(failed_files, joinpath(model, sim, file))
                    
                    # Force GC after errors too
                    GC.gc()
                end
            end
        end
    end
    
    # Print summary
    println("\n" * "="^60)
    println("=== Conversion Summary ===")
    println("="^60)
    println("Total NetCDF files found: $(total_files + length(skipped_files))")
    println("  - ILAMB-relevant files processed: $total_files")
    println("  - Non-ILAMB files skipped: $(length(skipped_files))")
    println("\nConversion Results:")
    println("  ✓ Successfully converted: $converted_files")
    println("  ❌ Failed conversions: $(length(failed_files))")
    
    if converted_files > 0
        success_rate = round(100 * converted_files / total_files, digits=1)
        println("  📊 Success rate: $success_rate%")
    end
    
    println("\nSuccess by ILAMB variable:")
    for var in sort(ilamb_vars)
        successes = get(successful_vars, var, 0)
        if successes > 0
            println("  ✓ $var: $successes conversions")
        else
            println("  - $var: 0 conversions (no files found or all failed)")
        end
    end
    
    if !isempty(error_types)
        println("\nError types encountered:")
        for (error_type, count) in sort(collect(error_types), by=x->x[2], rev=true)
            println("  - $error_type: $count occurrences")
        end
    end
    
    if !isempty(failed_files)
        println("\n⚠️  Failed files ($(length(failed_files))):")
        for (i, file) in enumerate(failed_files)
            if i <= 20  # Show first 20 failures
                println("  - $file")
            elseif i == 21
                println("  ... and $(length(failed_files) - 20) more")
                break
            end
        end
    end
    
    println("\n" * "="^60)
    println("Output directory: $output_base")
    println("="^60)
end

# Path to TRENDY data
const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const OUTPUT_DIR = "/home/renatob/data/ilamb_ready"

# Create output directory if it doesn't exist
mkpath(OUTPUT_DIR)

# Convert all files
@info "Starting conversion of all TRENDY files..."
convert_all_trendy_files(TRENDY_DIR, output_base=OUTPUT_DIR)