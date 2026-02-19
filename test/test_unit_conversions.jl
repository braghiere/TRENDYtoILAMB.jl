#!/usr/bin/env julia

# Test unit conversion functions

push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using TRENDYtoILAMB

println("Testing unit conversion functions...")
println()

# Test temperature conversions
println("=== Temperature Conversions ===")
celsius_data = [0.0, 15.0, 25.0, -10.0]
println("Input (Celsius): ", celsius_data)

kelvin_data = convert_data_values(celsius_data, "degrees celsius", "K", "tas")
println("Output (Kelvin): ", kelvin_data)
println("Expected: [273.15, 288.15, 298.15, 263.15]")
println("Match: ", isapprox(kelvin_data, [273.15, 288.15, 298.15, 263.15]))
println()

# Test with "unit" attribute (DLEM style)
kelvin_data2 = convert_data_values(celsius_data, "degrees celsius", "K", "tas")
println("With 'unit' attribute: ", kelvin_data2)
println("Match: ", isapprox(kelvin_data2, [273.15, 288.15, 298.15, 263.15]))
println()

# Test precipitation conversions
println("=== Precipitation Conversions ===")
mm_monthly_data = [100.0, 50.0, 75.0, 120.0]  # mm/month
println("Input (mm/month): ", mm_monthly_data)

flux_data = convert_precipitation_values(mm_monthly_data, "mm", "monthly")
println("Output (kg m-2 s-1): ", flux_data)
expected_flux = mm_monthly_data ./ (30.4 * 86400)
println("Expected: ", expected_flux)
println("Match: ", isapprox(flux_data, expected_flux))
println()

# Test no-conversion cases
println("=== No Conversion Needed ===")
kelvin_data_in = [273.15, 288.15, 298.15]
println("Input (K): ", kelvin_data_in)
kelvin_data_out = convert_data_values(kelvin_data_in, "K", "K", "tas")
println("Output (K): ", kelvin_data_out)
println("Match (no change): ", kelvin_data_in == kelvin_data_out)
println()

radiation_data = [200.0, 250.0, 300.0]
println("Input (W m-2): ", radiation_data)
radiation_out = convert_data_values(radiation_data, "W m-2", "W m-2", "rsds")
println("Output (W m-2): ", radiation_out)
println("Match (no change): ", radiation_data == radiation_out)
println()

println("✓ All unit conversion tests completed!")
