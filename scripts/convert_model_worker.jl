#!/usr/bin/env julia

# Worker script to convert a single TRENDY model to ILAMB format
# Called by parallel_convert_trendy.sh

using TRENDYtoILAMB
using NCDatasets

# Get configuration from environment variables
model = ENV["MODEL"]
trendy_dir = ENV["TRENDY_DIR"]
output_dir = ENV["OUTPUT_DIR"]

println("Processing model: ", model)
println("=" ^ 80)

# ILAMB-relevant variables
ilamb_vars = [
    "gpp", "lai", "nbp", "nee", "pr", "rh", "tas", "et", "evapotrans",
    "burntarea", "cVeg", "cSoil", "fFire", "ra", "npp", "cProduct",
    "mrso", "mrro", "mrros", "evspsbl", "hfls", "hfss", "rlds", "rlus", "rsds", "rsus",
    "cLitter", "tran"
]

# Process only S3 simulation (historical + all forcings)
sim_dir = joinpath(trendy_dir, model, "S3")

if !isdir(sim_dir)
    println("⚠️  S3 directory not found for ", model, ", skipping")
    exit(0)
end

# Create model output directory
model_output = joinpath(output_dir, model)
mkpath(model_output)

# Get all NetCDF files
nc_files = filter(x -> endswith(x, ".nc"), readdir(sim_dir))

println("Found ", length(nc_files), " NetCDF files")
println("")

# Statistics
total = 0
converted = 0
skipped = 0
failed = 0

for file in nc_files
    global total, converted, skipped, failed
    
    # Extract variable name from filename (format: ModelName_SimType_Variable.nc)
    parts = split(basename(file), "_")
    if length(parts) < 3
        println("  ⚠️  Skipping ", file, " (unexpected format)")
        skipped += 1
        continue
    end
    
    var = String(parts[end][1:end-3])  # Remove .nc extension
    
    # Skip if not an ILAMB variable
    if !(lowercase(var) in lowercase.(ilamb_vars))
        skipped += 1
        continue
    end
    
    # Check if already converted (resume support)
    normalized_var = normalize_variable_case(var)
    existing = filter(x -> startswith(x, normalized_var * "_Lmon_ENSEMBLE-" * model * "_"), 
                     readdir(model_output))
    if !isempty(existing)
        println("  ✓ ", var, " already converted, skipping")
        skipped += 1
        continue
    end
    
    total += 1
    input_file = joinpath(sim_dir, file)
    
    println("  Converting ", var, " from ", basename(file), "...")
    
    try
        # Validate file can be opened
        NCDataset(input_file) do ds
            if !("time" in keys(ds.dim))
                error("No time dimension found")
            end
        end
        
        # Convert with standardized date range
        dataset = TRENDYDataset(input_file, model, "S3", var)
        
        ilamb_dataset = convert_to_ilamb(dataset, 
                                        output_dir=model_output,
                                        override_start_date="170001",
                                        override_end_date="202312")
        
        output_file = ilamb_dataset.path
        file_size = filesize(output_file) / 1024 / 1024  # MB
        
        println("    ✓ Created ", basename(output_file), " (", round(file_size, digits=1), " MB)")
        converted += 1
        
    catch e
        println("    ✗ Failed: ", e)
        failed += 1
    end
    
    # Force garbage collection
    GC.gc()
end

println("")
println("=" ^ 80)
println("Model ", model, " completed:")
println("  Processed: ", total, " files")
println("  Converted: ", converted, " files")
println("  Skipped: ", skipped, " files")
println("  Failed: ", failed, " files")
println("=" ^ 80)

exit(failed > 0 ? 1 : 0)
