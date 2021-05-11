# qsiprep
Scripts for preprocessing DWI data with qsiprep with eddy cuda.

## Installation
The singularity image used for running qsiprep can be downloaded from docker hub with the command:
```
sudo singularity pull qsiprep-0.12.1_fsl-6.0.4_patched.sif docker://fredrmag/qsiprep:0.12.1_fsl-6.0.4_patch
```

## Usage
The main script is `batch_qsiprep_doubleres.sh`. It will submit the subjects and sessions in `data.csv` to the cluster.