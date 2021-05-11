#!/bin/bash 
# Purpose: Running qsiprep with eddy

#SBATCH -J qsiprep_hr
#SBATCH --cpus-per-task=3
#SBATCH --mem-per-cpu=8GB
#SBATCH --time=03:00:00
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

#singularity variables
highres=1.25    # high resolution

echo $BIDS_DIR $BIDS_DIR_TMP $SCRIPTS_DIR $WORK_DIR

log_name=logs/slurm.qsiprep.${sub}.${ses}-cpu-highres.log

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

singularity run --cleanenv --contain \
-B ${TOOLS_DIR} \
-B ${BIDS_DIR_TMP}/:/data_in \
-B ${BIDS_DIR}/:${BIDS_DIR} \
-B ${SCRIPTS_DIR}/:${SCRIPTS_DIR} \
-B ${BIDS_DIR}/derivatives/qsiprep_highres:/data_out \
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
--output-resolution ${highres} \
--hmc-model eddy \
--eddy_config ${SCRIPTS_DIR}/tmp/eddy_params/${sub}_${ses}_eddy_params.json \
--output-space T1w \
--nthreads ${SLURM_CPUS_PER_TASK} \
-vv

# delete files in work directory and bids_tmp if qsiprep completed successfully.
if [ $? == 0 ]; then
   rm -rf $WORK_DIR/qsiprep_wf/single_subject_${sub/sub-/}${ses/-/}_wf
   rm -rf $WORK_DIR/reportlets/qsiprep/${sub}${ses/-/}
   rm -rf ${BIDS_DIR}/derivatives/qsiprep_highres/qsiprep/${sub}${ses/-/}/anat
   rm -rf ${BIDS_DIR}/derivatives/qsiprep/${sub}${ses/-/}
fi