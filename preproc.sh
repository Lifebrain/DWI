#!/bin/bash

parm=$1
ses=$2
SING="singularity exec $HOME/containers/FSL_ANTS_MRTRIX.6.0.2_2.2.0_3.0RC3.sif"

# define the folder that includes the BIDS structured subject directories
BIDS_root=$HOME/testBIDS/BIDS
# specify the folder where outputs should go
BIDS_deriv=$HOME/DWI_EnergI/derivatives
# specify the folder for the DWI preprocessing output
BIDS_DWIpreproc=$BIDS_deriv/DWIpreproc

# create output folder for subjects
mkdir -p $BIDS_DWIpreproc/${parm}/${ses}/dwi
mkdir $BIDS_DWIpreproc/${parm}/${ses}/fmap

cd $BIDS_root

if [ -f "$BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_preproc.nii.gz" ]; then
   echo "DWI Preprocessing for ${parm}_${ses} has already run"

else

   # Denoise, extend to 7x7x7 patch size because we have 100 volumes, which is getting close to the 5×5×5=125
   $SING dwidenoise $BIDS_root/$parm/$ses/dwi/${parm}_${ses}*.nii.gz $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_denoised.nii.gz -noise $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_noise.nii.gz

   # check residual map, should look completely random, i.e. no structure left
   $SING mrcalc $BIDS_root/$parm/$ses/dwi/${parm}_${ses}*.nii.gz $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_denoised.nii.gz -subtract $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_residualNoise.nii.gz  
   ## ??????

   # remove Gibb’s ringing artefacts
   # axes option must be adjusted to your dataset: With this option, you inform the algorithm of the plane in which you acquired your data: 
   # –axes 0,1 means you acquired axial slices; -axes 0,2 refers to coronal slices and –axes 1,2 to sagittal slices
   $SING mrdegibbs $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_denoised.nii.gz $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_denoised_unring.nii.gz -axes 0,1

   # check result
   $SING mrcalc $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_denoised.nii.gz $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_denoised_unring.nii.gz -subtract $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_residualUnringed.nii.gz

   # extract the b0 volumes from dwi series --> NEEDS TO BE CHECKED BUT SHOULD BE A MORE GENERAL VERSION THAN THE OLD ONE BELOW
   $SING dwiextract -bzero $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_denoised_unring.nii.gz -fslgrad $BIDS_root/${parm}/${ses}/dwi/${parm}_${ses}*.bvec $BIDS_root/${parm}/${ses}/dwi/${parm}_${ses}*.bval $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_b0.nii.gz -export_grad_fsl $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_b0.bvec $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_b0.bval

   # extract the b0 volumes from inverted PE series --> NEEDS TO BE CHECKED BUT SHOULD BE A MORE GENERAL VERSION THAN THE OLD ONE BELOW
   $SING dwiextract -bzero $BIDS_root/${parm}/${ses}/fmap/${parm}_${ses}_*dir-PA*.nii.gz -fslgrad $BIDS_root/${parm}/${ses}/fmap/${parm}_${ses}_*dir-PA*.bvec $BIDS_root/${parm}/${ses}/fmap/${parm}_${ses}_*dir-PA*.bval $BIDS_DWIpreproc/${parm}/${ses}/fmap/${parm}_${ses}_b0.nii.gz -export_grad_fsl $BIDS_DWIpreproc/${parm}/${ses}/fmap/${parm}_${ses}_b0.bvec $BIDS_DWIpreproc/${parm}/${ses}/fmap/${parm}_${ses}_b0.bval

   # merge all b0 together in 1 file
   $SING fslmerge -t $BIDS_DWIpreproc/${parm}/${ses}/dwi/{parm}_${ses}_all_b0.nii.gz $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_b0.nii.gz $BIDS_DWIpreproc/${parm}/${ses}/fmap/${parm}_${ses}_b0.nii.gz


   # generate acqparams.txt file (only once needed, should be identical for all)
   # printf "0 -1 0 0.0383\n0 -1 0 0.0383\n0 -1 0 0.0383\n0 -1 0 0.0383\n0 -1 0 0.0383\n0 -1 0 0.0383\n0 -1 0 0.0383\n0 -1 0 0.0383\n0 -1 0 0.0383\n0 -1 0 0.0383\n0 1 0 0.0383\n0 1 0 0.0383\n0 1 0 0.0383\n0 1 0 0.0383\n" > ./acqparams.txt

   # run topup
   echo "Running topup on $parm"
   $SING topup --imain=$BIDS_DWIpreproc/${parm}/${ses}/dwi/{parm}_${ses}_all_b0.nii.gz --datain=$BIDS_DWIpreproc/acqparams.txt --config=b02b0.cnf --out=$BIDS_DWIpreproc/${parm}/${ses}/dwi/topup_results --iout=$BIDS_DWIpreproc/${parm}/${ses}/dwi/hifi_b0 --fout=$BIDS_DWIpreproc/${parm}/${ses}/dwi/topup_fieldmap --logout=$BIDS_DWIpreproc/${parm}/${ses}/logs/topup_log.txt

   # create non-distorted brain mask --> MAYBE DO DIFFERENTLY, VIA SEGMENTATION & COREGISTRATION
   echo "Creating brain-mask on $parm"
   $SING fslmaths $BIDS_DWIpreproc/${parm}/${ses}/dwi/hifi_b0 -Tmean $BIDS_DWIpreproc/${parm}/${ses}/dwi/hifi_b0_mean
   # brain extract the mean b0
   $SING bet $BIDS_DWIpreproc/${parm}/${ses}/dwi/hifi_b0_mean $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_b0_brain -m -R -f 0.2 -g 0.1
   # fix potential holes using ants
   $SING ImageMath 3 $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_brain_mask.nii.gz 'FillHoles' $BIDS_DWIpreproc/${parm}/${ses}/dwi/${parm}_${ses}_b0_brain_mask.nii.gz

   # mkdir check_mask
   # cp ${parm}/hifi_b0_mean.nii.gz check_mask/${parm}_b0mean.nii.gz
   # cp ${parm}/hifi_b0_brain_mask.nii.gz check_mask/${parm}_mask.nii.gz

   # create index file that tells eddy which of the lines in the acqparams.txt file is relevant for the dwi passed into eddy (only once needed, should be identical for all)
   # indx=""
   # for ((i=1; i<=100; i+=1)); do indx="$indx 1"; done
   # echo $indx > index.txt
fi
