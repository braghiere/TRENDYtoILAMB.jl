#=
Convert TRENDY NetCDF files to ILAMB format (DISTRIBUTED VERSION)

This script uses Julia's Distributed computing to process files in parallel
across multiple worker processes, avoiding NetCDF/HDF5 thread-safety issues.

Performance:
- Sequential: ~6 files/hour (1 core)
- Distributed (48 workers): ~150-250 files/hour (expected)
- Speedup: 25-40x faster

Usage:
    julia --project=. examples/convert_all_trendy_distributed.jl

The script will automatically spawn worker processes.
=#

using Distributed
using Printf

# Determine optimal number of workers
# For I/O-bound tasks, use fewer workers than CPU cores
const N_WORKERS = min(48, Sys.CPU_THREADS ÷ 2)

println("="^80)
println("🚀 DISTRIBUTED TRENDY TO ILAMB CONVERSION")
println("="^80)
println("CPU cores available: $(Sys.CPU_THREADS)")
println("Spawning $N_WORKERS worker processes...")
println("="^80)
println()

# Add worker processes
addprocs(N_WORKERS)

# Load packages on all workers
@everywhere begin
    using TRENDYtoILAMB
    using NCDatasets
    using Printf
end

@everywhere begin
    """
    Convert a single file on a worker process
    Returns: (success::Bool, file_path::String, error_msg::String)
    """
    function convert_single_file_worker(input_file::String, model::String, sim::String, 
                                       var::String, output_dir::String)
        worker_id = myid()
        file_name = basename(input_file)
        
        try
            # Quick validation
            NCDataset(input_file) do ds
                if !("time" in keys(ds.dim))
                    error("No time dimension found")
                end
            end
            
            # Convert
            dataset = TRENDYDataset(input_file, model, sim, var)
            ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
            
            # Verify
            verify_conversion(dataset, ilamb_dataset)
            
            # Get file size
            file_size = filesize(ilamb_dataset.path)
            
            success_msg = "[Worker $worker_id] ✓ $model/$sim/$var → $(basename(ilamb_dataset.path)) ($(round(file_size/1024/1024, digits=2)) MB)"
            
            return (true, joinpath(model, sim, file_name), success_msg, var)
            
        catch e
            error_msg = "[Worker $worker_id] ❌ $model/$sim/$var: $(typeof(e))"
            if isa(e, ErrorException)
                if occursin("NetCDF: HDF error", string(e))
                    error_msg *= " (Corrupted file)"
                elseif occursin("No time dimension", string(e))
                    error_msg *= " (Missing time dimension)"
                end
            end
            
            return (false, joinpath(model, sim, file_name), error_msg, "")
        end
    end
end

"""
Collect all files to process
"""
function collect_tasks(trendy_dir::String, output_base::String)
    ilamb_vars = [
        "gpp", "nbp", "npp", "ra", "rh", "lai", 
        "mrro", "mrros", "mrso", "evapotrans",
        "cSoil", "cVeg", "cLitter", "cProduct",
        "burntArea", "fFire",
        "tas", "pr", "rsds",
    ]
    
    all_tasks = []
    skipped_files = []
    
    models = filter(x -> isdir(joinpath(trendy_dir, x)) && !startswith(x, "."), readdir(trendy_dir))
    
    for model in models
        model_dir = joinpath(trendy_dir, model)
        
        for sim in ["S0", "S1", "S2", "S3"]
            sim_dir = joinpath(model_dir, sim)
            !isdir(sim_dir) && continue
            
            # Create output directory
            output_dir = joinpath(output_base, model)
            mkpath(output_dir)
            
            nc_files = filter(x -> endswith(x, ".nc"), readdir(sim_dir))
            
            for file in nc_files
                parts = split(basename(file), "_")
                if length(parts) < 3
                    push!(skipped_files, joinpath(model, sim, file))
                    continue
                end
                
                var = parts[end][1:end-3]  # Remove .nc
                
                if !(lowercase(var) in lowercase.(ilamb_vars))
                    push!(skipped_files, joinpath(model, sim, file))
                    continue
                end
                
                input_file = joinpath(sim_dir, file)
                push!(all_tasks, (input_file, model, sim, var, output_dir))
            end
        end
    end
    
    return all_tasks, skipped_files
end

"""
Convert all files using distributed processing
"""
function convert_all_trendy_files_distributed(trendy_dir::String; output_base::String="output")
    println("📊 Collecting files to convert...")
    all_tasks, skipped_files = collect_tasks(trendy_dir, output_base)
    
    println("📊 Files to convert: $(length(all_tasks))")
    println("📊 Files to skip: $(length(skipped_files))")
    println()
    println("⏱️  Starting distributed conversion with $N_WORKERS workers...")
    println()
    
    start_time = time()
    last_progress_time = start_time
    completed = 0
    
    # Process files using pmap (parallel map across workers)
    results = pmap(all_tasks; on_error=identity) do task
        input_file, model, sim, var, output_dir = task
        convert_single_file_worker(input_file, model, sim, var, output_dir)
    end
    
    elapsed_time = time() - start_time
    
    # Process results
    successful_vars = Dict{String,Int}()
    failed_files = String[]
    error_types = Dict{String,Int}()
    
    println("\n" * "="^80)
    println("Processing results...")
    for (success, file_path, msg, var) in results
        println(msg)
        if success
            successful_vars[var] = get(successful_vars, var, 0) + 1
        else
            push!(failed_files, file_path)
            # Extract error type from message
            if occursin("Corrupted", msg)
                error_types["Corrupted NetCDF"] = get(error_types, "Corrupted NetCDF", 0) + 1
            elseif occursin("Missing time", msg)
                error_types["Missing time dimension"] = get(error_types, "Missing time dimension", 0) + 1
            else
                error_types["Other error"] = get(error_types, "Other error", 0) + 1
            end
        end
    end
    
    # Summary
    converted_files = length(results) - length(failed_files)
    
    println()
    println("="^80)
    println("=== CONVERSION SUMMARY ===")
    println("="^80)
    println("⏱️  Total time: $(round(elapsed_time/60, digits=1)) minutes ($(round(elapsed_time/3600, digits=2)) hours)")
    println("👷 Workers used: $N_WORKERS")
    println()
    println("📊 Files processed: $(length(all_tasks))")
    println("   ✓ Successfully converted: $converted_files")
    println("   ❌ Failed conversions: $(length(failed_files))")
    println("   ⏭️  Skipped (non-ILAMB): $(length(skipped_files))")
    
    if converted_files > 0
        success_rate = round(100 * converted_files / length(all_tasks), digits=1)
        avg_rate = round(converted_files / (elapsed_time / 3600), digits=1)
        println()
        println("📈 Success rate: $success_rate%")
        println("⚡ Average speed: $avg_rate files/hour")
        
        # Calculate speedup vs sequential
        sequential_rate = 6.0  # files/hour from current run
        speedup = avg_rate / sequential_rate
        println("🚀 Speedup vs sequential: $(round(speedup, digits=1))x faster")
    end
    
    ilamb_vars = ["gpp", "nbp", "npp", "ra", "rh", "lai", "mrro", "mrros", "mrso", 
                  "evapotrans", "cSoil", "cVeg", "cLitter", "cProduct", "burntArea", 
                  "fFire", "tas", "pr", "rsds"]
    
    println()
    println("Success by ILAMB variable:")
    for var in sort(ilamb_vars)
        successes = get(successful_vars, var, 0)
        if successes > 0
            println("   ✓ $var: $successes conversions")
        end
    end
    
    if !isempty(error_types)
        println()
        println("Error types encountered:")
        for (error_type, count) in sort(collect(error_types), by=x->x[2], rev=true)
            println("   - $error_type: $count occurrences")
        end
    end
    
    if !isempty(failed_files) && length(failed_files) <= 20
        println()
        println("⚠️  Failed files:")
        for file in failed_files
            println("   - $file")
        end
    elseif length(failed_files) > 20
        println()
        println("⚠️  Failed files (showing first 20 of $(length(failed_files))):")
        for file in failed_files[1:20]
            println("   - $file")
        end
    end
    
    println()
    println("="^80)
    println("📁 Output directory: $output_base")
    println("="^80)
end

# Main execution
const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const OUTPUT_DIR = "/home/renatob/data/ilamb_ready"

try
    convert_all_trendy_files_distributed(TRENDY_DIR, output_base=OUTPUT_DIR)
finally
    # Clean up workers
    rmprocs(workers())
    println("\n✅ Worker processes terminated")
end
