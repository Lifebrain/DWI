#!/bin/env bash
# Purpose: Take care of the eddy_param.json file.

if [ $# -lt 4 ]; then
    echo "usage: $0 <BIDS_DIR> <SCRIPTS_DIR> <sub-id> <ses-id>"
    exit 1
else
    BIDS_DIR=$1
    SCRIPTS_DIR=$2
    sub=$3
    ses=$4
fi
shift 4
use_cuda="false"
# Handle optional parameters
while :; do
    case $1 in 
        --use_cuda|--use-cuda)
            use_cuda="true"
        ;;
        --)                             # End of all options
            shift 
            break
        ;;
        -?*)
            printf "WARNING: Unknown option (ignored): %s\n" "$1" >&2
        ;;
        *)
            break
    esac

    shift
done

# Create tmp directories:
if [ ! -e ${SCRIPTS_DIR}/tmp/slspec_files ]; then
    mkdir -p ${SCRIPTS_DIR}/tmp/slspec_files
fi

if [ ! -e ${SCRIPTS_DIR}/tmp/eddy_params ]; then
    mkdir -p ${SCRIPTS_DIR}/tmp/eddy_params
fi

if [ ! -e ${SCRIPTS_DIR}/tmp/qsiprep_plugin ]; then
    mkdir -p ${SCRIPTS_DIR}/tmp/qsiprep_plugin
fi

# 1. Get slm option
slm_option=$(python utils/check_bvec.py ${BIDS_DIR} ${sub} ${ses})

# 2. Create slspec file
# slspec file - filename has to be absolute path
slspec_filename=${SCRIPTS_DIR}/tmp/slspec_files/${sub}_${ses}_slspec.txt
python utils/extract_slice_timings.py ${BIDS_DIR} ${sub} ${ses} ${slspec_filename}

# 3. Edit .json files with eddy parameters
sed "s/SLM_REPLACE/${slm_option}/g; \
s/NUM_THREADS_REPLACE/${SLURM_CPUS_PER_TASK}/g; \
s)SLSPEC_FILE_REPLACE)${slspec_filename})g; \
s/USE_CUDA_OPTION/${use_cuda}/g;" \
${SCRIPTS_DIR}/utils/eddy_param_template.json > ${SCRIPTS_DIR}/tmp/eddy_params/${sub}_${ses}_eddy_params.json

# 4. Create qsiprep_plugin.yml
MEM_PER_CPU_GB=${SLURM_MEM_PER_CPU/GB/}
total_gb=$((SLURM_CPUS_PER_TASK*MEM_PER_CPU_GB/1000))
sed "s/MEM_GB_TOTAL_REPLACE/${total_gb}/g;\
     s/N_PROC_REPLACE/${SLURM_CPUS_PER_TASK}/g" ${SCRIPTS_DIR}/utils/qsiprep_plugin_template.yml > ${SCRIPTS_DIR}/tmp/qsiprep_plugin/${sub}_${ses}_qsiprep_plugin.yml