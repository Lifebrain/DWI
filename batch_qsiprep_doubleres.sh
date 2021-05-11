#!/bin/env bash
# Purpose: Run batch processing of dwi

# Location of the bids data. These scripts will automatically make 
# tmp directory ${BIDS_DIR}_tmp, outputs are placed in ${BIDS_DIR}/derivatives
BIDS_DIR="/cluster/projects/p274/projects/dwi_harmonization/data/uio"

# How many jobs in total to have submitted to the cluster. Takes 
# into account how many jobs you have submitted from before.
jobs_total=50

# Gets the scripts directory, even if you run the batch script from a different 
# directory. Taken from:
# https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

jobs_running=$(squeue -n qsiprep -u $USER | wc -l)
jobs_to_be_submitted=$((jobs_total-(jobs_running-1)))

# Create a logs directory if it does not exists
if [ ! -e logs ]; then
    mkdir logs
fi

# Go through data.csv and submit datasets not already in queue
i=0
for line in $(cat data.csv)
do
    if [ $i -eq 0 ]; then
        i=$((i+1))
        continue; 
    fi

    sub=$(echo $line | awk -F"," '{print $1}')
    ses=$(echo $line | awk -F"," '{print $2}')

    log=logs/slurm.qsiprep.${sub}.${ses}-cpu.log
    lock=lock/${sub}_${ses}.lock

    # Create lock directory if it does not exists.
    if [ ! -e lock ]; then
        mkdir lock
    fi

    if [ ! -e $BIDS_DIR/derivatives/qsiprep_highres/qsiprep/${sub}${ses/-/} ] && [ ! -e $log ] && [ ! -e $lock ]; then
        if [ $i -lt $((jobs_to_be_submitted+1)) ]; then
            # Make a lock file when it has been submitted, so that we do not double-post jobs
            echo $sub $ses $i

            touch $lock
            job_id=$(sbatch --parsable qsiprep_doubleres.sh $sub $ses $BIDS_DIR $SCRIPTS_DIR)
            echo "Submitted batch job $job_id"
            job_id_2=$(sbatch --parsable --dependency=afternotok:$job_id qsiprep-cuda_doubleres.sh $sub $ses $BIDS_DIR $SCRIPTS_DIR)
            echo "Submitted batch job $job_id_2"
            sbatch --dependency=afterok:$job_id_2 qsiprep-highres.sh $sub $ses $BIDS_DIR $SCRIPTS_DIR
            i=$((i+1))
        else
            echo "Submitted $jobs_to_be_submitted jobs."
            exit 0
        fi
    fi
done