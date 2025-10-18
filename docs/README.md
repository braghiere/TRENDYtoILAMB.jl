# Documentation Generation and Deployment

The documentation for TRENDYtoILAMB.jl is built using [Documenter.jl](https://juliadocs.github.io/Documenter.jl/stable/).

## Local Build

To build the documentation locally:

1. Change to the docs directory:
   ```bash
   cd docs
   ```

2. Start Julia with the docs project:
   ```bash
   julia --project=.
   ```

3. Build the documentation:
   ```julia
   include("make.jl")
   ```

## Automatic Deployment

Documentation is automatically deployed by GitHub Actions when you push to the main branch. To set this up:

1. Go to your repository's Settings → Secrets and Variables → Actions
2. Add a new repository secret named `DOCUMENTER_KEY` with your documentation deployment key
3. The documentation will be deployed to GitHub Pages automatically

For more information about setting up documentation deployment, see the [Documenter.jl Authentication guide](https://documenter.juliadocs.org/stable/man/hosting/#Authentication).