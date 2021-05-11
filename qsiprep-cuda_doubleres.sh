#!/bin/bash 
# Purpose: Running qsiprep with eddy

#SBATCH -J qsiprep_gpu
#SBATCH --cpus-per-task=3
#SBATCH --mem-per-cpu=8GB
#SBATCH --time=06:00:00

# p274_lcbc: gpu-1
#SBATCH --account=p274_lcbc
#SBATCH --output logs/slurm-%j.txt
#SBATCH --partition=accel
#SBATCH --gres=gpu:1
##SBATCH --nice=100000
##SBATCH -x gpu-2

TOOLS_DIR="/cluster/projects/p274/tools/"

module purge
echo "LOADING SINGULARITY MODULE"
module load singularity/3.4.2
echo `which singularity`
set -o errexit
unset PYTHONPATH
module load Anaconda3

sub=${1}
ses=${2}
BIDS_DIR=${3}
SCRIPTS_DIR=${4}

BIDS_DIR_TMP=${BIDS_DIR}_tmp

site_name=$(echo $BIDS_DIR | awk -F"/" '{print $NF}')
WORK_DIR="/cluster/projects/p274/projects/dwi_harmonization/work/$site_name"

# Find native resolution by using mri_info
dwi_file=$(ls ${BIDS_DIR_TMP}/${sub}${ses/-/}/dwi/*.nii.gz | head -1)
origres=$(/cluster/projects/p274/tools/mri/freesurfer/freesurfer.6.0.1/bin/mri_info \
    ${dwi_file} | grep "voxel sizes" | awk -F"," '{print $2}' | sed 's/ //g')

echo $BIDS_DIR $BIDS_DIR_TMP $SCRIPTS_DIR $WORK_DIR

log_name=logs/slurm.qsiprep.${sub}.${ses}-gpu.log

if [ -e "$log_name" ]; then
    exit 1
fi

mv logs/slurm-${SLURM_JOBID}.txt $log_name

#RUN QSIPREP
export SINGULARITYENV_ANTS_RANDOM_SEED=999

if [ ! -e ${BIDS_DIR}/derivatives/qsiprep_origres ]; then
    mkdir -p ${BIDS_DIR}/derivatives/qsiprep_origres
fi
if [ ! -e ${BIDS_DIR}/derivatives/qsiprep_highres ]; then
    mkdir -p ${BIDS_DIR}/derivatives/qsiprep_highres
fi

singularity run --cleanenv --contain --nv \
    -B ${TOOLS_DIR} \
    -B ${BIDS_DIR_TMP}/:/data_in \
    -B ${BIDS_DIR}/:${BIDS_DIR} \
    -B ${SCRIPTS_DIR}/:${SCRIPTS_DIR} \
    -B ${BIDS_DIR}/derivatives/qsiprep_origres:/data_out \
    -B ${WORK_DIR}:/work \
    -B /tmp:/tmp \
    /cluster/projects/p274/tools/bids/qsiprep/0.12.1_fsl-6.0.4/*qsiprep*.sif \
    /data_in \
    /data_out \
    participant \
    -w /work \
    --participant-label ${sub}${ses/-/} \
    --skip_bids_validation \
    --use-plugin ${SCRIPTS_DIR}/tmp/qsiprep_plugin/${sub}_${ses}_qsiprep_plugin.yml \
    --fs-license-file ${TOOLS_DIR}/bids/qsiprep/0.8.0/freesurfer_license.txt \
    --unringing-method mrdegibbs \
    --dwi-denoise-window 5 \
    --output-resolution ${origres} \
    --hmc-model eddy \
    --eddy_config ${SCRIPTS_DIR}/tmp/eddy_params/${sub}_${ses}_eddy_params.json \
    --output-space T1w \
    --nthreads ${SLURM_CPUS_PER_TASK} \
    -vv

