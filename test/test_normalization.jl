#!/usr/bin/env julia

# Test the ILAMB variable case normalization

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using TRENDYtoILAMB

println("Testing ILAMB variable case normalization...")
println()

# Test cases from TRENDY survey
test_cases = [
    # (input, expected_output)
    ("cSoil", "cSoil"),      # Already correct
    ("csoil", "cSoil"),      # Lowercase → camelCase
    ("CSOIL", "cSoil"),      # Uppercase → camelCase
    ("LAI", "lai"),          # ISAM special case: uppercase → lowercase
    ("lai", "lai"),          # Already correct (20 models)
    ("cVeg", "cVeg"),        # Already correct
    ("cveg", "cVeg"),        # Lowercase → camelCase
    ("gpp", "gpp"),          # Already correct
    ("GPP", "gpp"),          # Uppercase → lowercase
    ("npp", "npp"),          # Already correct
    ("burntArea", "burntArea"),  # Already correct
    ("burntarea", "burntArea"),  # Lowercase → camelCase
    ("fFire", "fFire"),      # Already correct
    ("ffire", "fFire"),      # Lowercase → camelCase
    ("fLuc", "fLuc"),        # Already correct
    ("fluc", "fLuc"),        # Lowercase → camelCase
    ("evapotrans", "et"),    # CRITICAL: TRENDY evapotrans → ILAMB et
    ("et", "et"),            # Direct et also works
]

println("Testing $(length(test_cases)) cases:")
println()

global all_passed = true
for (input, expected) in test_cases
    result = normalize_variable_case(input)
    passed = result == expected
    global all_passed = all_passed && passed
    
    status = passed ? "✓" : "✗"
    println("$status  $input → $result $(passed ? "" : "(expected: $expected)")")
end

println()
if all_passed
    println("✓ All tests passed!")
else
    println("✗ Some tests failed")
    exit(1)
end

println()
println("Available ILAMB variables:")
for var in get_ilamb_variables()
    println("  - $var")
end
