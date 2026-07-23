#!/bin/bash
#SBATCH --job-name=trendy_convert
#SBATCH --output=logs/convert_%A_%a.out
#SBATCH --error=logs/convert_%A_%a.err
#SBATCH --time=04:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --array=0-21

# Parallel TRENDY to ILAMB conversion script
# Converts one model per SLURM array job for maximum parallelization
# Each model takes ~30min-2hrs depending on data size

set -e

# Configuration
TRENDY_DIR="/home/renatob/data/TRENDYv13"
OUTPUT_DIR="/home/renatob/data/ilamb_test_output_full_v2"
JULIA_PROJECT="/home/renatob/TRENDYtoILAMB.jl"
LOGS_DIR="/home/renatob/data/logs"

# Create logs directory
mkdir -p "$LOGS_DIR"

# Get model name
# For SLURM: use array task ID to index into models list
# For GNU parallel: MODEL is already set as environment variable
if [ -z "$MODEL" ]; then
    # SLURM mode: get model from array
    MODELS=($(find "$TRENDY_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".*" -printf "%f\n" | sort))
    MODEL="${MODELS[$SLURM_ARRAY_TASK_ID]}"
fi

echo "=============================================="
echo "SLURM Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Model: $MODEL"
echo "Start time: $(date)"
echo "=============================================="
echo ""

# Check if model directory exists
if [ ! -d "$TRENDY_DIR/$MODEL" ]; then
    echo "ERROR: Model directory not found: $TRENDY_DIR/$MODEL"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR/$MODEL"

# Export environment variables for Julia script
export MODEL
export TRENDY_DIR
export OUTPUT_DIR

# Run Julia conversion worker script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
julia --project="$JULIA_PROJECT" "$SCRIPT_DIR/convert_model_worker.jl"

EXIT_CODE=$?

echo ""
echo "=============================================="
echo "Model: $MODEL"
echo "End time: $(date)"
echo "Exit code: $EXIT_CODE"
echo "=============================================="

exit $EXIT_CODE
