#=
Test distributed conversion on a small subset

Run with:
    julia --project=. examples/test_distributed_conversion.jl
=#

using Distributed

println("="^80)
println("🧪 TESTING DISTRIBUTED CONVERSION")
println("="^80)

# Add just a few workers for testing
const N_TEST_WORKERS = 4
println("Spawning $N_TEST_WORKERS worker processes for testing...")
addprocs(N_TEST_WORKERS)

# Load packages on all workers
@everywhere begin
    using TRENDYtoILAMB
    using NCDatasets
end

@everywhere begin
    function convert_single_file_worker(input_file::String, model::String, sim::String, 
                                       var::String, output_dir::String)
        worker_id = myid()
        file_name = basename(input_file)
        
        try
            NCDataset(input_file) do ds
                if !("time" in keys(ds.dim))
                    error("No time dimension found")
                end
            end
            
            dataset = TRENDYDataset(input_file, model, sim, var)
            ilamb_dataset = convert_to_ilamb(dataset, output_dir=output_dir)
            verify_conversion(dataset, ilamb_dataset)
            
            file_size = filesize(ilamb_dataset.path)
            success_msg = "[Worker $worker_id] ✓ $model/$var → $(basename(ilamb_dataset.path)) ($(round(file_size/1024/1024, digits=2)) MB)"
            
            return (true, file_name, success_msg)
            
        catch e
            error_msg = "[Worker $worker_id] ❌ $model/$var: $(typeof(e))"
            return (false, file_name, error_msg)
        end
    end
end

# Test files
const TRENDY_DIR = "/home/renatob/data/TRENDYv13"
const TEST_OUTPUT = "/home/renatob/data/ilamb_ready_test_distributed"

if isdir(TEST_OUTPUT)
    println("🗑️  Cleaning previous test output...")
    rm(TEST_OUTPUT, recursive=true)
end
mkpath(TEST_OUTPUT)

# Collect test files
test_files = []
ilamb_vars = ["gpp", "npp", "cSoil", "lai"]

models = filter(x -> isdir(joinpath(TRENDY_DIR, x)) && !startswith(x, "."), readdir(TRENDY_DIR))

for (i, model) in enumerate(models)
    if i > 4  # Test with 4 models
        break
    end
    
    model_dir = joinpath(TRENDY_DIR, model)
    for sim in ["S3"]
        sim_dir = joinpath(model_dir, sim)
        !isdir(sim_dir) && continue
        
        nc_files = filter(x -> endswith(x, ".nc"), readdir(sim_dir))
        
        for file in nc_files
            parts = split(basename(file), "_")
            length(parts) < 3 && continue
            
            var = parts[end][1:end-3]
            
            if lowercase(var) in lowercase.(ilamb_vars)
                output_dir = joinpath(TEST_OUTPUT, model)
                mkpath(output_dir)
                push!(test_files, (joinpath(sim_dir, file), model, sim, var, output_dir))
                break  # Just one file per model
            end
        end
    end
end

println()
println("📊 Test files selected: $(length(test_files))")
for (file, model, sim, var, _) in test_files
    println("   - $model/$sim: $var ($(round(filesize(file)/1024/1024, digits=1)) MB)")
end
println()

println("⏱️  Starting distributed conversion test...")
start_time = time()

# Process files using pmap
results = pmap(test_files) do task
    input_file, model, sim, var, output_dir = task
    try
        convert_single_file_worker(input_file, model, sim, var, output_dir)
    catch e
        worker_id = myid()
        error_msg = "[Worker $worker_id] ❌ Error: $e"
        return (false, basename(input_file), error_msg)
    end
end

elapsed = time() - start_time

# Print results
println()
converted_count = 0
failed_count = 0

for result in results
    success, file, msg = result
    println(msg)
    if success
        converted_count += 1
    else
        failed_count += 1
    end
end

# Summary
println()
println("="^80)
println("🎯 TEST RESULTS")
println("="^80)
println("⏱️  Time: $(round(elapsed, digits=2)) seconds")
println("👷 Workers: $N_TEST_WORKERS")
println()
println("✓ Converted: $converted_count")
println("❌ Failed: $failed_count")

if converted_count > 0
    rate_per_hour = (converted_count / elapsed) * 3600
    println()
    println("⚡ Rate: $(round(rate_per_hour, digits=1)) files/hour")
    
    total_files = 840
    est_hours = total_files / rate_per_hour
    println("📈 Estimated time for full conversion: $(round(est_hours, digits=1)) hours")
    
    sequential_rate = 6.0
    speedup = rate_per_hour / sequential_rate
    println("🚀 Speedup vs sequential: $(round(speedup, digits=1))x")
end

println()
println("📁 Test output: $TEST_OUTPUT")
println("="^80)

# Cleanup
rmprocs(workers())
println("\n✅ Test complete! Worker processes terminated.")
