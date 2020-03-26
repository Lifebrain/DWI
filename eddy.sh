#!/bin/bash

parm=$1
ses=$2
SING="singularity exec --nv $HOME/containers/FSL_ANTS_MRTRIX.6.0.2_2.2.0_3.0RC3.sif"

BIDS_root=$HOME/testBIDS/BIDS
BIDS_deriv=$HOME/DWI_EnergI/derivatives
BIDS_DWIpreproc=$BIDS_deriv/DWIpreproc

mkdir -p $BIDS_DWIpreproc/${parm}/${ses}/dwi
mkdir $BIDS_DWIpreproc/${parm}/${ses}/fmap

cd $BIDS_root

if [ -f "$BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_preproc.nii.gz" ]; then
   echo "DWI Preprocessing for ${parm}_${ses} has already run"

else

   echo "Running eddy on $parm"
   $SING eddy_cuda --imain=$BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_denoised_unring.nii.gz --mask=$BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_brain_mask --acqp=$BIDS_DWIpreproc/acqparams.txt --index=$BIDS_DWIpreproc/index.txt --bvecs=$BIDS_root/${parm}/${ses}/dwi/${parm}_${ses}_dwi.bvec --bvals=$BIDS_root/${parm}/${ses}/dwi/${parm}_${ses}_dwi.bval --fwhm=0 --flm=quadratic --topup=$BIDS_DWIpreproc/${parm}/${ses}/dwi/topup_results --repol --residuals --cnr_maps --slspec=$BIDS_DWIpreproc/sl_order.txt --out=$BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_preproc

   echo "Doing quality control on $parm"
   $SING eddy_quad $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_preproc -idx $BIDS_DWIpreproc/index.txt -par $BIDS_DWIpreproc/acqparams.txt -m $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_brain_mask -b $BIDS_root/${parm}/${ses}/dwi/${parm}_${ses}_dwi.bval -g $BIDS_root/${parm}/${ses}/dwi/${parm}_${ses}_dwi.bvec -f $BIDS_DWIpreproc/${parm}/${ses}/dwi/topup_fieldmap -s $BIDS_DWIpreproc/sl_order.txt 

   # dtifit preferably runs with single-shell data and b-values below 1500, so here the b=700 images are extracted
   $SING dwiextract -singleshell -shell 0,700 -bzero $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_preproc.nii.gz -fslgrad $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_preproc.eddy_rotated_bvecs $BIDS_root/${parm}/${ses}/dwi/${parm}_${ses}_dwi.bval $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_preproc700.nii.gz -export_grad_fsl $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_preproc700.bvec $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_preproc700.bval

fi
