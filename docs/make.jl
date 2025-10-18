using Documenter
using Pkg

# Temporarily add the package in dev mode if not already present
if !haskey(Pkg.project().dependencies, "TRENDYtoILAMB")
    Pkg.develop(PackageSpec(path=joinpath(@__DIR__, "..")))
    Pkg.instantiate()
end

using TRENDYtoILAMB

makedocs(
    sitename = "TRENDYtoILAMB.jl",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://braghiere.github.io/TRENDYtoILAMB.jl"
    ),
    modules = [TRENDYtoILAMB],
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "Getting Started" => "manual/getting_started.md",
            "TRENDY Format" => "manual/trendy_format.md",
            "ILAMB Format" => "manual/ilamb_format.md",
        ],
        "API Reference" => "api.md",
    ]
)

deploydocs(
    repo = "github.com/braghiere/TRENDYtoILAMB.jl.git",
)