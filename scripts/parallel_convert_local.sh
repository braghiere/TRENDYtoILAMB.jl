#!/usr/bin/env bash
# Parallel TRENDY->ILAMB conversion on a single multi-core node (no SLURM).
# Launches one convert_model_worker.jl process per model, capped at MAXJOBS
# concurrent. Workers have resume support (skip already-converted files).
#
# Env (with defaults for TRENDY v14 / S2):
#   TRENDY_DIR   input root containing <MODEL>/<SIM>/*.nc
#   OUTPUT_DIR   output root, one subdir per model
#   SIM          simulation subdirectory (S2)
#   OVERRIDE_START / OVERRIDE_END   filename date range (YYYYMM)
#   MAXJOBS      max concurrent worker processes
set -uo pipefail

TRENDY_DIR="${TRENDY_DIR:-/kiwi-data/Data/model/TRENDYv14/S2}"
OUTPUT_DIR="${OUTPUT_DIR:-/home/renatob/data/ilamb_output_v14_S2}"
SIM="${SIM:-S2}"
OVERRIDE_START="${OVERRIDE_START:-170001}"
OVERRIDE_END="${OVERRIDE_END:-202412}"
MAXJOBS="${MAXJOBS:-16}"
JULIA_PROJECT="${JULIA_PROJECT:-/home/renatob/TRENDYtoILAMB.jl}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOGS_DIR="${LOGS_DIR:-$OUTPUT_DIR/_worker_logs}"
mkdir -p "$LOGS_DIR" "$OUTPUT_DIR"

mapfile -t MODELS < <(find "$TRENDY_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".*" -printf "%f\n" | sort)
echo "Converting ${#MODELS[@]} models from $TRENDY_DIR (sim $SIM), up to $MAXJOBS at a time"

for MODEL in "${MODELS[@]}"; do
    # throttle to MAXJOBS concurrent workers
    while [ "$(jobs -rp | wc -l)" -ge "$MAXJOBS" ]; do wait -n; done
    (
        export MODEL TRENDY_DIR OUTPUT_DIR SIM OVERRIDE_START OVERRIDE_END
        julia --project="$JULIA_PROJECT" "$SCRIPT_DIR/convert_model_worker.jl" \
            > "$LOGS_DIR/$MODEL.log" 2>&1
        echo "[$(date +%H:%M:%S)] done $MODEL (exit $?)"
    ) &
done
wait
echo "ALL MODELS DONE"
