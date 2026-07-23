#!/bin/bash

# Helper script to submit parallel TRENDY conversion jobs and monitor progress

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TRENDY_DIR="/home/renatob/data/TRENDYv13"
OUTPUT_DIR="/home/renatob/data/ilamb_test_output_full_v2"
LOGS_DIR="/home/renatob/data/logs"

# Count models (directories only, no CSV files)
MODEL_COUNT=$(find "$TRENDY_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".*" | wc -l)

echo "=============================================="
echo "TRENDY to ILAMB Parallel Conversion"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  Input: $TRENDY_DIR"
echo "  Output: $OUTPUT_DIR"
echo "  Models: $MODEL_COUNT"
echo "  Script: $SCRIPT_DIR/parallel_convert_trendy.sh"
echo ""

# Create output directory and logs
mkdir -p "$OUTPUT_DIR"
mkdir -p "$LOGS_DIR"

# List models
echo "Models to convert:"
find "$TRENDY_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".*" -printf "%f\n" | sort | nl
echo ""

# Check if SLURM is available
if command -v sbatch &> /dev/null; then
    echo "SLURM detected. Submitting array job..."
    echo ""
    
    # Make script executable
    chmod +x "$SCRIPT_DIR/parallel_convert_trendy.sh"
    
    # Submit job array
    JOB_ID=$(sbatch --parsable "$SCRIPT_DIR/parallel_convert_trendy.sh")
    
    echo "✓ Submitted SLURM job array: $JOB_ID"
    echo ""
    echo "Monitor progress:"
    echo "  squeue -u $USER"
    echo "  tail -f logs/convert_${JOB_ID}_*.out"
    echo ""
    echo "Check success rate:"
    echo "  sacct -j $JOB_ID --format=JobID,JobName,State,ExitCode,Elapsed"
    echo ""
    echo "View logs:"
    echo "  ls -lh logs/convert_${JOB_ID}_*.out"
    echo ""
    
else
    echo "SLURM not available. Using GNU parallel to convert models..."
    echo ""
    
    # Check if parallel is available
    if ! command -v parallel &> /dev/null; then
        echo "ERROR: Neither SLURM nor GNU parallel are available"
        echo "Please install GNU parallel or run conversion sequentially"
        exit 1
    fi
    
    # Number of parallel jobs (adjust based on available cores and memory)
    NUM_JOBS=${NUM_JOBS:-21}  # Default: 21 jobs (one per model)
    echo "Parallel jobs: $NUM_JOBS"
    echo ""
    
    # Export environment variables
    export TRENDY_DIR
    export OUTPUT_DIR
    export SLURM_ARRAY_TASK_ID
    
    # Get model list (directories only)
    MODELS=($(find "$TRENDY_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".*" -printf "%f\n" | sort))
    
    TOTAL=${#MODELS[@]}
    echo "Converting $TOTAL models with GNU parallel..."
    echo ""
    
    # Create simple wrapper function for parallel
    convert_model() {
        local MODEL="$1"
        export MODEL
        bash "$SCRIPT_DIR/parallel_convert_trendy.sh" 2>&1 | tee "$LOGS_DIR/convert_${MODEL}.log"
        return ${PIPESTATUS[0]}
    }
    export -f convert_model
    export SCRIPT_DIR
    
    # Run parallel conversion
    START_TIME=$(date +%s)
    
    printf '%s\n' "${MODELS[@]}" | \
        parallel --jobs "$NUM_JOBS" \
                 --bar \
                 --joblog "$LOGS_DIR/parallel_joblog.txt" \
                 convert_model {}
    
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    
    # Check results
    SUCCEEDED=$(awk '$7 == 0 && NR > 1' "$LOGS_DIR/parallel_joblog.txt" | wc -l)
    FAILED=$(awk '$7 != 0 && NR > 1' "$LOGS_DIR/parallel_joblog.txt" | wc -l)
    
    echo ""
    echo "=============================================="
    echo "Conversion complete"
    echo "  Time: ${ELAPSED}s ($((ELAPSED/60)) minutes)"
    echo "  Succeeded: $SUCCEEDED/$TOTAL"
    echo "  Failed: $FAILED/$TOTAL"
    echo "=============================================="
    
    exit $( [ $FAILED -eq 0 ] && echo 0 || echo 1 )
fi
