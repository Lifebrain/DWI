#!/bin/bash 
# Purpose: Running qsiprep with eddy

#SBATCH -J qsiprep
#SBATCH --cpus-per-task=3
#SBATCH --mem-per-cpu=8GB
#SBATCH --time=12:00:00
#SBATCH --account=p274
#SBATCH --output logs/slurm-%j.txt

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

if [ ! -e $WORK_DIR ]; then
    mkdir -p $WORK_DIR
fi

echo $BIDS_DIR $BIDS_DIR_TMP $SCRIPTS_DIR $WORK_DIR

log_name=logs/slurm.qsiprep.${sub}.${ses}-cpu.log

if [ -e "$log_name" ]; then
        exit 1
fi

mv logs/slurm-${SLURM_JOBID}.txt $log_name

# Create symlinks
echo "Create symlinks"
bash utils/create_symlinks.sh ${BIDS_DIR} ${BIDS_DIR_TMP} ${sub} ${ses}

# Create eddy_param file, slspec_file and qsiprep_plugin.yml
echo "Create eddy_param file, slspec_file and qsiprep_plugin.yml"
bash utils/create_tmp_files.sh ${BIDS_DIR} ${SCRIPTS_DIR} ${sub} ${ses} --use_cuda

# delete lock file
echo "Delete lock file"
lock=lock/${sub}_${ses}.lock
rm $lock

#RUN QSIPREP
export SINGULARITYENV_ANTS_RANDOM_SEED=999

if [ ! -e ${BIDS_DIR}/derivatives ]; then
    mkdir -p ${BIDS_DIR}/derivatives
fi

singularity run --cleanenv --contain \
-B ${TOOLS_DIR} \
-B ${BIDS_DIR_TMP}/:/data_in \
-B ${BIDS_DIR}/:${BIDS_DIR} \
-B ${SCRIPTS_DIR}/:${SCRIPTS_DIR} \
-B ${BIDS_DIR}/derivatives:/data_out \
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
--output-resolution 1.25 \
--hmc-model eddy \
--eddy_config ${SCRIPTS_DIR}/tmp/eddy_params/${sub}_${ses}_eddy_params.json \
--output-space T1w \
--nthreads ${SLURM_CPUS_PER_TASK} \
-vv