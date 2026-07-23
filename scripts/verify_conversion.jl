#!/usr/bin/env julia

"""
Verification script for parallel TRENDY conversion
Checks that all converted files have standardized date ranges
"""

using Printf

output_dir = length(ARGS) > 0 ? ARGS[1] : "/home/renatob/data/ilamb_test_output_full_v2"

println("=" ^ 80)
println("Verifying TRENDY Conversion - Date Range Standardization")
println("=" ^ 80)
println("Output directory: $output_dir")
println()

if !isdir(output_dir)
    println("ERROR: Directory not found: $output_dir")
    exit(1)
end

# Get all model directories
models = filter(x -> isdir(joinpath(output_dir, x)) && !startswith(x, "."), 
               readdir(output_dir))
sort!(models)

println("Found $(length(models)) models")
println()

# Statistics
total_files = 0
models_ok = 0
models_inconsistent = 0
models_no_files = 0

expected_pattern = "170001-202312"

for model in models
    model_dir = joinpath(output_dir, model)
    nc_files = filter(x -> endswith(x, ".nc"), readdir(model_dir))
    
    if isempty(nc_files)
        println("⚠️  $model: No files found")
        models_no_files += 1
        continue
    end
    
    # Extract date patterns from all files
    date_patterns = Set{String}()
    for file in nc_files
        m = match(r"_(\d{6})-(\d{6})\.nc$", file)
        if m !== nothing
            date_range = "$(m.captures[1])-$(m.captures[2])"
            push!(date_patterns, date_range)
        end
    end
    
    total_files += length(nc_files)
    
    # Check consistency
    if length(date_patterns) == 1 && expected_pattern in date_patterns
        println("✓ $model: $(length(nc_files)) files, all $expected_pattern")
        models_ok += 1
    elseif length(date_patterns) == 1
        println("⚠️  $model: $(length(nc_files)) files, but unexpected pattern: $(collect(date_patterns)[1])")
        models_inconsistent += 1
    else
        println("✗ $model: $(length(nc_files)) files, INCONSISTENT patterns: $(collect(date_patterns))")
        models_inconsistent += 1
        # Show details
        for pattern in sort(collect(date_patterns))
            count = sum(occursin(pattern, f) for f in nc_files)
            println("    - $pattern: $count files")
        end
    end
end

println()
println("=" ^ 80)
println("Summary:")
println("=" ^ 80)
println(@sprintf "  Total models: %d", length(models))
println(@sprintf "  ✓ Consistent: %d (%.1f%%)", models_ok, 100*models_ok/length(models))
println(@sprintf "  ✗ Inconsistent: %d (%.1f%%)", models_inconsistent, 100*models_inconsistent/length(models))
println(@sprintf "  ⚠ No files: %d (%.1f%%)", models_no_files, 100*models_no_files/length(models))
println(@sprintf "  Total files: %d", total_files)
println("=" ^ 80)

if models_inconsistent > 0
    println()
    println("❌ VERIFICATION FAILED: Some models have inconsistent date patterns")
    exit(1)
else
    println()
    println("✅ VERIFICATION PASSED: All models have standardized date ranges")
    exit(0)
end
