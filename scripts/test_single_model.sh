#!/bin/bash

# Quick test of the parallel conversion with a single model (JULES)
# This verifies the scripts work before submitting the full job array

set -e

echo "=============================================="
echo "Testing parallel conversion with JULES model"
echo "=============================================="
echo ""

TRENDY_DIR="/home/renatob/data/TRENDYv13"
OUTPUT_DIR="/home/renatob/data/ilamb_test_output_full_v2"
JULIA_PROJECT="/home/renatob/TRENDYtoILAMB.jl"
LOGS_DIR="/home/renatob/data/logs"

# Set environment variables
export MODEL="JULES"
export TRENDY_DIR
export OUTPUT_DIR
export SLURM_ARRAY_TASK_ID=0

# Create directories
mkdir -p "$OUTPUT_DIR/JULES"
mkdir -p "$LOGS_DIR"

echo "Model: JULES"
echo "Input: $TRENDY_DIR/JULES/S3"
echo "Output: $OUTPUT_DIR/JULES"
echo ""

# Check if SLURM is available
if command -v sbatch &> /dev/null; then
    echo "SLURM detected. Submitting single test job..."
    sbatch --array=0 --wait /home/renatob/TRENDYtoILAMB.jl/scripts/parallel_convert_trendy.sh
    EXIT_CODE=$?
else
    echo "SLURM not available. Running directly..."
    bash /home/renatob/TRENDYtoILAMB.jl/scripts/parallel_convert_trendy.sh
    EXIT_CODE=$?
fi

echo ""
echo "=============================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ Test conversion completed successfully"
    echo ""
    echo "Verifying output..."
    julia /home/renatob/TRENDYtoILAMB.jl/scripts/verify_conversion.jl "$OUTPUT_DIR"
    
    echo ""
    echo "Ready to submit full job array:"
    echo "  bash /home/renatob/TRENDYtoILAMB.jl/scripts/submit_parallel_conversion.sh"
else
    echo "✗ Test conversion failed"
    echo "Check $LOGS_DIR/convert_*.err for details"
fi
echo "=============================================="

exit $EXIT_CODE
