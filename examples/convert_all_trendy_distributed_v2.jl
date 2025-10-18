#=
Convert TRENDY NetCDF files to ILAMB format using Distributed Computing

This version uses a simpler approach with better error handling.

Usage:
    julia --project=. examples/convert_all_trendy_distributed_v2.jl
=#

using Distributed
using Printf

# Add workers
const N_WORKERS = 24  # Start conservative, can increase later
println("="^80)
println("🚀 DISTRIBUTED TRENDY TO ILAMB CONVERSION")
println("="^80)
println("Spawning $N_WORKERS worker processes...")

addprocs(N_WORKERS; exeflags="--project=.")

println("Workers spawned: $(nworkers())")
println("="^80)
println()

# Load packages on all workers
println("📦 Loading packages on all workers...")
@everywhere using TRENDYtoILAMB
@everywhere using NCDatasets
@everywhere using Printf

# Define conversion function on all workers
@everywhere begin
    """
    Convert a single file and return result
    """
    function convert_file_task(input_file, model, sim, var, output_dir)
        worker_id = myid()
        
        try
            # Validate file
            NCDataset(input_file) do ds
                if !("time" in keys(ds.dim))
                    return (false, model, sim, var, "No time dimension")
                end
            end
            
            # Convert
            dataset = TRENDYDataset(input_file, model, sim, var)
            ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
            
            # Verify
            verify_conversion(dataset, ilamb_dataset)
            
            # Get size
            size_mb = round(filesize(ilamb_dataset.path) / 1024 / 1024, digits=2)
            output_name = basename(ilamb_dataset.path)
            
            return (true, model, sim, var, "Success: $output_name ($size_mb MB) [Worker $worker_id]")
            
        catch e
            error_msg = string(typeof(e))
            if isa(e, ErrorException)
                if occursin("NetCDF: HDF error", string(e))
                    error_msg = "Corrupted NetCDF"
                elseif occursin("No time dimension", string(e))
                    error_msg = "Missing time dimension"
                else
                    error_msg = string(e)[1:min(100, length(string(e)))]
                end
            end
            return (false, model, sim, var, error_msg)
        end
    end
end

# Main execution on master process
println("📊 Collecting files to convert...")

const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const OUTPUT_DIR = "/home/renatob/data/ilamb_ready"

# ILAMB variables
const ILAMB_VARS = [
    "gpp", "nbp", "npp", "ra", "rh", "lai", 
    "mrro", "mrros", "mrso", "evapotrans",
    "cSoil", "cVeg", "cLitter", "cProduct",
    "burntArea", "fFire",
    "tas", "pr", "rsds",
]

# Collect all tasks
all_tasks = []
skipped_files = []

models = filter(x -> isdir(joinpath(TRENDY_DIR, x)) && !startswith(x, "."), readdir(TRENDY_DIR))

for model in models
    model_dir = joinpath(TRENDY_DIR, model)
    
    for sim in ["S0", "S1", "S2", "S3"]
        sim_dir = joinpath(model_dir, sim)
        !isdir(sim_dir) && continue
        
        # Create output directory
        output_dir = joinpath(OUTPUT_DIR, model)
        mkpath(output_dir)
        
        nc_files = filter(x -> endswith(x, ".nc"), readdir(sim_dir))
        
        for file in nc_files
            parts = split(basename(file), "_")
            if length(parts) < 3
                push!(skipped_files, joinpath(model, sim, file))
                continue
            end
            
            var = parts[end][1:end-3]
            
            if !(lowercase(var) in lowercase.(ILAMB_VARS))
                push!(skipped_files, joinpath(model, sim, file))
                continue
            end
            
            input_file = joinpath(sim_dir, file)
            
            # Check if already converted (for resuming)
            # Expected output pattern: var_Lmon_ENSEMBLE-model_historical_r1i1p1f1_gn_YYYYMM-YYYYMM.nc
            existing_files = filter(x -> startswith(x, "$(var)_Lmon_ENSEMBLE-$(model)_"), 
                                   readdir(output_dir))
            if !isempty(existing_files)
                push!(skipped_files, joinpath(model, sim, file) * " (already converted)")
                continue
            end
            
            push!(all_tasks, (input_file, model, sim, var, output_dir))
        end
    end
end

n_total = length(all_tasks)
n_skipped = length(skipped_files)

println("📊 Total files found: $(n_total + n_skipped)")
println("   ✓ Files to convert: $n_total")
println("   ⏭️  Files to skip: $n_skipped")
println()

if n_total == 0
    println("✅ All files already converted!")
    rmprocs(workers())
    exit(0)
end

println("⏱️  Starting distributed conversion...")
println()

# Process with pmap
start_time = time()
last_update_time = start_time
completed_count = 0
success_count = 0
failed_count = 0

# Progress callback
channel = RemoteChannel(() -> Channel{Int}(N_WORKERS))

results = pmap(all_tasks) do task
    input_file, model, sim, var, output_dir = task
    result = convert_file_task(input_file, model, sim, var, output_dir)
    put!(channel, 1)  # Signal completion
    return result
end

# Close channel
close(channel)

elapsed_time = time() - start_time

# Process results
println()
println("="^80)
println("Processing results...")
println("="^80)

successful_vars = Dict{String,Int}()
failed_files = []
error_types = Dict{String,Int}()

for (success, model, sim, var, msg) in results
    if success
        success_count += 1
        successful_vars[var] = get(successful_vars, var, 0) + 1
        println("✓ $model/$sim/$var: $msg")
    else
        failed_count += 1
        push!(failed_files, "$model/$sim/$var")
        error_types[msg] = get(error_types, msg, 0) + 1
        println("❌ $model/$sim/$var: $msg")
    end
end

# Final summary
println()
println("="^80)
println("=== CONVERSION SUMMARY ===")
println("="^80)
println("⏱️  Total time: $(round(elapsed_time/60, digits=1)) minutes ($(round(elapsed_time/3600, digits=2)) hours)")
println("👷 Workers: $N_WORKERS")
println()
println("📊 Files processed: $n_total")
println("   ✓ Successfully converted: $success_count")
println("   ❌ Failed: $failed_count")
println("   ⏭️  Skipped (non-ILAMB/existing): $n_skipped")

if success_count > 0
    success_rate = round(100 * success_count / n_total, digits=1)
    avg_rate = round(success_count / (elapsed_time / 3600), digits=1)
    println()
    println("📈 Success rate: $success_rate%")
    println("⚡ Average speed: $avg_rate files/hour")
    
    sequential_rate = 4.2  # Current observed rate
    speedup = avg_rate / sequential_rate
    println("🚀 Speedup vs sequential: $(round(speedup, digits=1))x faster")
end

println()
println("Success by ILAMB variable:")
for var in sort(collect(keys(successful_vars)))
    count = successful_vars[var]
    println("   ✓ $var: $count conversions")
end

if !isempty(error_types)
    println()
    println("Error types:")
    for (err, count) in sort(collect(error_types), by=x->x[2], rev=true)
        println("   - $err: $count")
    end
end

if !isempty(failed_files)
    n_show = min(20, length(failed_files))
    println()
    println("Failed files (showing $n_show of $(length(failed_files))):")
    for file in failed_files[1:n_show]
        println("   - $file")
    end
end

println()
println("="^80)
println("📁 Output directory: $OUTPUT_DIR")
println("="^80)

# Cleanup
println()
println("🧹 Removing worker processes...")
rmprocs(workers())
println("✅ Conversion complete!")
