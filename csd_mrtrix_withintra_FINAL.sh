cat >preamble <<EOF

#!/bin/bash

SING="singularity exec $HOME/containers/FSL_ANTS_MRTRIX.6.0.2_2.2.0_3.0RC3.sif"

BIDS_root=$HOME/DWI_EnergI
BIDS_deriv=$HOME/DWI_EnergI/derivatives
BIDS_DWImrtrix=$BIDS_deriv/MRtrix
BIDS_DWIpreproc=$BIDS_deriv/DWIpreproc

mkdir -p $BIDS_DWImrtrix

cd BIDS_root

EOF

. ./preamble

for parm in sub-* ; do
   
	for ses_fp in $parm/ses-* ; do

   	ses=$(echo $ses_fp | cut -d"/" -f2);

		cat preamble - >dwi2response.job <<EOF

		# create tissue type segmentation --> could also base this on freesurfer parcellation image
		$SING 5ttgen fsl $BIDS_root/$parm/$ses/anat/${parm}_${ses}*T1w.nii $BIDS_DWImrtrix/$parm/$ses/anat/${parm}_${ses}_5tt.mif -nocrop

		# coregister T1 to DWI via flirt
		$SING fslmaths $BIDS_DWIpreproc/${parm}/$ses/dwi/hifi_b0.nii.gz -Tmean  $BIDS_DWImrtrix/${parm}/$ses/dwi/hifi_b0_mean.nii.gz
		$SING flirt -in $BIDS_root/$parm/$ses/anat/${parm}_${ses}*T1w.nii -ref $BIDS_DWImrtrix/${parm}/$ses/dwi/hifi_b0_mean.nii.gz -cost mutualinfo -dof 6 -omat $BIDS_DWImrtrix/$parm/$ses/anat/${parm}_${ses}_struct2dwi.mat -out $BIDS_DWImrtrix/$parm/$ses/anat/${parm}_${ses}_r2dwi.nii.gz

		# convert matrix to mrtrix-format
		$SING transformconvert $BIDS_DWImrtrix/$parm/$ses/anat/${parm}_${ses}_struct2dwi.mat $BIDS_root/$parm/$ses/anat/${parm}_${ses}*T1w.nii $BIDS_DWImrtrix/${parm}/$ses/dwi/hifi_b0_mean.nii.gz flirt_import $BIDS_DWImrtrix/$parm/$ses/anat/${parm}_${ses}_struct2dwi_mrtrix.txt

		# apply matrix
		$SING mrtransform $BIDS_DWImrtrix/$parm/$ses/anat/${parm}_${ses}_5tt.mif -linear $BIDS_DWImrtrix/$parm/$ses/anat/${parm}_${ses}_struct2dwi_mrtrix.txt -interp nearest $BIDS_DWImrtrix/$parm/$ses/anat/${parm}_${ses}_5tt_r2dwi.mif

		# create a GM/WM Boundary seed mask to define plausible streamline starting
		$SING 5tt2gmwmi $BIDS_DWImrtrix/$parm/$ses/anat/${parm}_${ses}_5tt_r2dwi.mif $BIDS_DWImrtrix/$parm/$ses/anat/${parm}_${ses}_gmwmSeed_r2dwi.mif

	   # Calculate tissue response functions UPDATED APRIL 2019
	   $SING dwi2response dhollander $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.nii.gz $BIDS_DWImrtrix/$parm/$ses/dwi/response_wm.txt $BIDS_DWImrtrix/$parm/$ses/dwi/response_gm.txt $BIDS_DWImrtrix/$parm/$ses/dwi/response_csf.txt -voxels $BIDS_DWImrtrix/$parm/$ses/dwi/voxels.nii.gz -nthreads 4 -mask $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_brain_mask.nii.gz -fslgrad $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.bvec $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.bval

	   # Calculate the diffusion tensor to extract md and fa 
	   $SING dwi2tensor $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.nii.gz -mask $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_brain_mask.nii.gz -fslgrad $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.bvec $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.bval $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_tensor.mif

	   # Extract md and fa 
	   $SING tensor2metric $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_tensor.mif -mask $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_brain_mask.nii.gz -adc $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_md.nii.gz -fa $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_fa.nii.gz
	
EOF
	   TMPID=$(qsub dwi2response.job -l nodes=1:ppn=4 -d. -j oe -o $BIDS_DWImrtrix/$parm/$ses/logs/ -N "mrtrix_dwi2response_${parm}_${ses}")
	   BARRIER1=$BARRIER1":"$TMPID
	   mv dwi2response.job $BIDS_DWImrtrix/$parm/$ses/jobs/
   done
done
echo $BARRIER1

## NEEDS TO INCLUDE ALL SUBJECTS, CANNOT BE DONE IN PARALLEL

cat preamble - >average_response.job <<EOF
# To ensure the response function is representative of your study population, a group average response function must be computed (cp. http://community.mrtrix.org/t/response-function-for-group-analysis/1077)
$SING average_response $BIDS_DWImrtrix/sub-*/ses-*/dwi/response_wm.txt $BIDS_DWImrtrix/group_average_response_wm.txt
$SING average_response $BIDS_DWImrtrix/sub-*/ses-*/dwi/response_gm.txt $BIDS_DWImrtrix/group_average_response_gm.txt
$SING average_response $BIDS_DWImrtrix/sub-*/ses-*/dwi/response_csf.txt $BIDS_DWImrtrix/group_average_response_csf.txt
EOF
BARRIER2=$(qsub average_response.job -d. -j oe -o $BIDS_DWImrtrix/logs/ -N "mrtrix_averesp" -W depend=afterok$BARRIER1)
mv average_response.job $BIDS_DWImrtrix/jobs/
echo $BARRIER2

# Two participants (AKTIV2124B AKTIV4223B) have incomplete data for timepoint A but they should still be included, that is why they are explicitly mentioned
for parm in sub-* ; do

	cat preamble >tmp2.job 

	# we only want intra-subject template generation for participants with multiple timepoints so we pick them based on whether they have a second time point. 
	if [ ls $parm -1 | wc -l > 1 ]; then
	
	   mkdir -p $BIDS_DWImrtrix/$parm/template/fod_input
	   mkdir -p $BIDS_DWImrtrix/$parm/template/mask_input

	   for ses_fp in $parm/ses-* ; do

   	   ses=$(echo $ses_fp | cut -d"/" -f2);

	      cat >>tmp2.job <<EOF

		   # upsample DW images to increase anatomical contrast and improve downstream spatial normalisation and statistics
		   $SING mrresize $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.nii.gz -vox 1.3 -nthreads 4 $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_preproc_upsampled.nii.gz
		   # upsample the mask image (we use the one created via bet and checked already!!)
		   $SING mrresize $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_brain_mask.nii.gz -vox 1.3 -interp nearest $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_upsampled.mif

		   # Calculate fod's (CSD) 
		   $SING dwi2fod msmt_csd $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_preproc_upsampled.nii.gz $BIDS_DWImrtrix/group_average_response_wm.txt $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_wmfod.mif $BIDS_DWImrtrix/group_average_response_gm.txt $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_gm.mif $BIDS_DWImrtrix/group_average_response_csf.txt $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_csf.mif -mask $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_upsampled.mif -fslgrad $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.bvec $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.bval

		   # Intensity normalisation to correct for global intensity differences between subjects
		   $SING mtnormalise $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_wmfod.mif $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_wmfod_norm.mif $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_gm.mif $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_gm_norm.mif $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_csf.mif $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_csf_norm.mif -mask $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_upsampled.mif                                                                                                                                                                                                                                                                     

		   # symbolic link FOD images (and masks) from one subject into a single input folder
		   ln -sr $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_wmfod_norm.mif $BIDS_DWImrtrix/$parm/template/fod_input/${parm}_${ses}.mif  
         ln -sr $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_preproc_upsampled.nii.gz $BIDS_DWImrtrix/$parm/template/mask_input/${parm}_${ses}.mif

EOF
	   done

	   cat >>tmp2.job <<EOF

	   # build the intra-subject template 
	   $SING population_template $BIDS_DWImrtrix/$parm/template/fod_input -mask_dir $BIDS_DWImrtrix/$parm/template/mask_input $BIDS_DWImrtrix/$parm/template/${parm}_wmfod_template.mif -voxel_size 1.3 -type rigid -nthreads 4 
EOF

	   for ses_fp in $parm/ses-* ; do

         ses=$(echo $ses_fp | cut -d"/" -f2);

		   cat >>tmp2.job <<EOF

		   # Register the FOD image from all time points to the FOD intra-template image
		   $SING mrregister $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_wmfod_norm.mif -mask1 $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_upsampled.mif $BIDS_DWImrtrix/$parm/template/${parm}_wmfod_template.mif -type rigid -rigid $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}2intra_warp.mif

		   # compute the mask intersection across time points to perform analyses in voxels that contain data from all subjects
		   $SING mrtransform $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_upsampled.mif -linear $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}2intra_warp.mif -interp nearest $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_in_intratemplate_space.mif -template $BIDS_DWImrtrix/$parm/template/${parm}_wmfod_template.mif 

EOF
	   done

	   cat >>tmp2.job <<EOF
	   $SING mrmath $BIDS_DWImrtrix/$parm/ses-*/${parm}_ses-*_mask_in_intratemplate_space.mif min $BIDS_DWImrtrix/$parm/template/${parm}_mask_intersection.mif
EOF

	# for those subjects with only one timepoint (A) we still calculate the FODs
	elif [[ ls $parm -1 | wc -l = 1 ]]; then
      #for that one session
      for ses_fp in $parm/ses-* ; do

         ses=$(echo $ses_fp | cut -d"/" -f2);

         cat >>tmp2.job <<EOF

         # upsample DW images to increase anatomical contrast and improve downstream spatial normalisation and statistics
         $SING mrresize $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.nii.gz -vox 1.3 -nthreads 4 $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_preproc_upsampled.nii.gz
         # upsample the mask image (we use the one created via bet and checked already!!)
         $SING mrresize $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_brain_mask.nii.gz -vox 1.3 -interp nearest $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_upsampled.mif

         # Calculate fod's (CSD) 
         $SING dwi2fod msmt_csd $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_preproc_upsampled.nii.gz $BIDS_DWImrtrix/group_average_response_wm.txt $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_wmfod.mif $BIDS_DWImrtrix/group_average_response_gm.txt $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_gm.mif $BIDS_DWImrtrix/group_average_response_csf.txt $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_csf.mif -mask $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_upsampled.mif -fslgrad $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.bvec $BIDS_DWIpreproc/${parm}/$ses/dwi/${parm}_${ses}_preproc.bval

         # Intensity normalisation to correct for global intensity differences between subjects
         $SING mtnormalise $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_wmfod.mif $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_wmfod_norm.mif $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_gm.mif $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_gm_norm.mif $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_csf.mif $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_csf_norm.mif -mask $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_upsampled.mif                                                                                                                                                                                                                                                                     
EOF
      done
	else echo "Session number not defined!"
   fi
	TMPID=$(qsub tmp2.job -d. -j oe -o $BIDS_DWImrtrix/$parm/$ses/logs/ -l mem=10gb,nodes=1:ppn=4 -N "mrtrix_intratempl_${parm}" -W depend=afterok:$BARRIER2)
	BARRIER3=$BARRIER3":"$TMPID
   mv tmp2.job $BIDS_DWImrtrix/$parm/$ses/jobs/
done
echo $BARRIER3


# CANNOT BE RUN IN PARALLEL
cat preamble - >template.job <<EOF
# Generate a study-specific unbiased FOD template
mkdir -p $BIDS_DWImrtrix/template/fod_input
mkdir -p $BIDS_DWImrtrix/template/mask_input
# 
# # according to documentation 30-40 subjects should suffice for the template. Here we randomly pick 10 subjects from each group (the intra-subject template)
# # and symbolic link all FOD images (and masks) into a single input folder
$SING foreach `ls -d sub-AKTIV1????/template | sort -R | tail -10 | tr '\n' ' '`: ln -sr PRE/*_wmfod_template.mif $BIDS_DWImrtrix/template/fod_input/PRE.mif ";" ln -sr PRE/*_mask_intersection.mif $BIDS_DWImrtrix/template/mask_input/PRE.mif
$SING foreach `ls -d sub-AKTIV2????/template | sort -R | tail -10 | tr '\n' ' '`: ln -sr PRE/*_wmfod_template.mif $BIDS_DWImrtrix/template/fod_input/PRE.mif ";" ln -sr PRE/*_mask_intersection.mif $BIDS_DWImrtrix/template/mask_input/PRE.mif
$SING foreach `ls -d sub-AKTIV3????/template | sort -R | tail -10 | tr '\n' ' '`: ln -sr PRE/*_wmfod_template.mif $BIDS_DWImrtrix/template/fod_input/PRE.mif ";" ln -sr PRE/*_mask_intersection.mif $BIDS_DWImrtrix/template/mask_input/PRE.mif
$SING foreach `ls -d sub-AKTIV4????/template | sort -R | tail -10 | tr '\n' ' '`: ln -sr PRE/*_wmfod_template.mif $BIDS_DWImrtrix/template/fod_input/PRE.mif ";" ln -sr PRE/*_mask_intersection.mif $BIDS_DWImrtrix/template/mask_input/PRE.mif

# build the inter-subject template
$SING population_template $BIDS_DWImrtrix/template/fod_input -mask_dir $BIDS_DWImrtrix/template/mask_input $BIDS_DWImrtrix/template/wmfod_template.mif -voxel_size 1.3 -nthreads 16
EOF
BARRIER4=$(qsub template.job -d. -j oe -o $BIDS_DWImrtrix/logs/ -l mem=50gb,walltime=75:0:0,nodes=1:ppn=16 -N "mrtrix_template" -W depend=afterok$BARRIER3)
mv template.job $BIDS_DWImrtrix/jobs/
echo $BARRIER4

# CAN RUN IN PARALLEL
for parm in sub-* ; do

   # for those subjects with multiple timepoints (only in those cases the template directory exists)
   if [[ -d "$BIDS_DWImrtrix/$parm/template" ]]; then

      cat preamble - >FOD2template.job <<EOF

      # Register the FOD intra-subject template image from all subjects to the FOD group template image
      $SING mrregister $BIDS_DWImrtrix/$parm/template/${parm}_wmfod_template.mif -mask1 $BIDS_DWImrtrix/$parm/template/${parm}_mask_intersection.mif $BIDS_DWImrtrix/template/wmfod_template.mif -nthreads 4 -nl_warp $BIDS_DWImrtrix/$parm/template/${parm}2template_warp.mif $BIDS_DWImrtrix/$parm/template/template2${parm}_warp.mif

      # Register the intra-subject mask intersection from all subjects to the FOD group template image
      $SING mrtransform $BIDS_DWImrtrix/$parm/template/${parm}_mask_intersection.mif -warp $BIDS_DWImrtrix/$parm/template/${parm}2template_warp.mif -interp nearest -datatype bit -nthreads 4 $BIDS_DWImrtrix/$parm/template/${parm}_dwimask_in_template_space.mif
EOF

      for ses_fp in $parm/ses-* ; do

         ses=$(echo $ses_fp | cut -d"/" -f2);

         cat >>FOD2template.job <<EOF

         # combine intra & inter-subject warps
         $SING transformcompose $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}2intra_warp.mif $BIDS_DWImrtrix/${parm}/template/${parm}2template_warp.mif $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}_combined_warp.mif

         # warp FOD images into template space without FOD reorientation
         $SING mrtransform $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_wmfod_norm.mif -warp $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}_combined_warp.mif -noreorientation $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}_fod_in_template_space.mif
	   
         # warp the mask to the FOD group template image
         $SING mrtransform $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_upsampled.mif -warp $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}_combined_warp.mif -interp nearest -datatype bit -nthreads 4 $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}_dwimask_in_template_space.mif
EOF
      done
   
   # for those subjects with only one timepoint we register that timepoint directly to the group template
   elif [[ ls $parm -1 | wc -l = 1 ]]; then
      
      cat preamble - >FOD2template.job<<EOF

      # Register the FOD image from subjects with only timepoint A to the FOD group template image
      $SING mrregister $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_wmfod_norm.mif -mask1$BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_upsampled.mif $BIDS_DWImrtrix/template/wmfod_template.mif -nthreads 4 -nl_warp $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}2template_warp.mif $BIDS_DWImrtrix/${parm}/${ses}/dwi/template2${parm}_warp.mif

      # Register the mask from subjects with only timepoint A to the FOD group template image
      $SING mrtransform $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_mask_upsampled.mif -warp $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}2template_warp.mif -interp nearest -datatype bit -nthreads 4 $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}_dwimask_in_template_space.mif

      # warp the FOD image from subjects with only timepoint A to the FOD group template space without FOD reorientation
      $SING mrtransform $BIDS_DWImrtrix/$parm/$ses/dwi/${parm}_${ses}_wmfod_norm.mif -warp $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}2template_warp.mif -noreorientation $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}_fod_in_template_space.mif
EOF
   else echo "Session number not defined!"
   fi

   TMPID=$(qsub FOD2template.job -l mem=50gb,nodes=1:ppn=4 -d. -j oe -o $BIDS_DWImrtrix/$parm/$ses/logs/ -N "mrtrix_FOD2template_${parm}" -W depend=afterok:$BARRIER4)
   BARRIER5=$BARRIER5":"$TMPID
   mv FOD2template.job $BIDS_DWImrtrix/$parm/$ses/jobs/

done
echo $BARRIER5

# CANNOT BE RUN IN PARALLEL
cat preamble - >template_mask.job <<EOF
# compute the mask intersection to perform analyses in voxels that contain data from all subjects
$SING mrmath $BIDS_DWImrtrix/sub-*/ses-*/dwi/sub-*_dwimask_in_template_space.mif min $BIDS_DWImrtrix/template/template_mask.mif -datatype bit

# identify all voxels having some white matter by thresholding the DC term
# ***** NOT DONE IN THE UPDATED VERSION, THEY USE THE TEMPLATE_MASK FROM NOW ON INSTEAD OF THE VOXEL MASK
$SING mrconvert $BIDS_DWImrtrix/template/wmfod_template.mif -coord 3 0 $BIDS_DWImrtrix/template/dc_term.mif
$SING mrthreshold $BIDS_DWImrtrix/template/dc_term.mif $BIDS_DWImrtrix/template/voxel_mask.mif

# OLD VERSION with voxel_mask: segment all fixels from each FOD in the template image --> CHECK SIZE OF IMAGE, NO MORE THAN 500.000 fixels (mrinfo -size template/fixel_mask/directions.mif)
# $SING fod2fixel -mask $BIDS_DWImrtrix/template/voxel_mask.mif -fmls_peak_value 0.06 -nthreads 4 $BIDS_DWImrtrix/template/wmfod_template.mif $BIDS_DWImrtrix/template/fixel_mask
# UPDATED OCT19 to template_mask: 
$SING fod2fixel -mask $BIDS_DWImrtrix/template/template_mask.mif -fmls_peak_value 0.06 -nthreads 4 $BIDS_DWImrtrix/template/wmfod_template.mif $BIDS_DWImrtrix/template/fixel_mask

EOF
BARRIER7=$(qsub template_mask.job -d. -j oe -o $BIDS_DWImrtrix/logs/ -N "mrtrix_template_mask" -W depend=afterok$BARRIER5)
mv template_mask.job $BIDS_DWImrtrix/jobs/
echo $BARRIER7


mkdir -p $BIDS_DWImrtrix/template/log_fc
mkdir -p $BIDS_DWImrtrix/template/fdc

for parm in sub-* ; do

   for ses_fp in $parm/ses-* ; do

      ses=$(echo $ses_fp | cut -d"/" -f2);

   	cat preamble - >subject2template.job <<EOF

	   # OLD VERSION with voxel_mask: segment each FOD lobe to identify the number and orientation of fixels in each voxel and the apparent fibre density
	   # $SING fod2fixel $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}_fod_in_template_space.mif -mask $BIDS_DWImrtrix/template/voxel_mask.mif $BIDS_DWImrtrix/${parm}/${ses}/dwi/fixel_in_template_space_NOT_REORIENTED -afd ${parm}_${ses}_fd.mif
	   # UPDATED OCT19 to template_mask: 
	   # segment each FOD lobe to identify the number and orientation of fixels in each voxel and the apparent fibre density
	   $SING fod2fixel $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}_fod_in_template_space.mif -mask $BIDS_DWImrtrix/template/template_mask.mif $BIDS_DWImrtrix/${parm}/${ses}/dwi/fixel_in_template_space_NOT_REORIENTED -afd ${parm}_${ses}_fd.mif
EOF

      if [ -d "$BIDS_DWImrtrix/$parm/template" ]; then
    
         cat >>subject2template.job <<EOF

	      # reorient the direction of all fixels based on the Jacobian matrix
	      $SING fixelreorient $BIDS_DWImrtrix/${parm}/${ses}/dwi/fixel_in_template_space_NOT_REORIENTED $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}_combined_warp.mif $BIDS_DWImrtrix/${parm}/${ses}/dwi/fixel_in_template_space
EOF

      elif [[ ls $parm -1 | wc -l = 1 ]]; then
   
         cat >>subject2template.job <<EOF

	      # reorient the direction of all fixels based on the Jacobian matrix
	      $SING fixelreorient $BIDS_DWImrtrix/${parm}/${ses}/dwi/fixel_in_template_space_NOT_REORIENTED $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}2template_warp.mif $BIDS_DWImrtrix/${parm}/${ses}/dwi/fixel_in_template_space
EOF
      fi
    
      cat >>subject2template.job <<EOF

	   # folders can be safely removed
	    -rf $BIDS_DWImrtrix/${parm}/${ses}/dwi/fixel_in_template_space_NOT_REORIENTED

	   # Assign subject fixels to template fixels
	   $SING fixelcorrespondence $BIDS_DWImrtrix/${parm}/${ses}/dwi/fixel_in_template_space/${parm}_${ses}_fd.mif $BIDS_DWImrtrix/template/fixel_mask $BIDS_DWImrtrix/template/fd ${parm}_${ses}.mif
EOF

      if [ -d "$BIDS_DWImrtrix/$parm/template" ]; then
    
         cat >>subject2template.job <<EOF

	      # compute fixel-based metric related to morphological differences in fibre cross-section
	      $SING warp2metric $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}_${ses}_combined_warp.mif -fc $BIDS_DWImrtrix/template/fixel_mask $BIDS_DWImrtrix/template/fc ${parm}_${ses}.mif
EOF

      elif [[ ls $parm -1 | wc -l = 1 ]]; then
 
   
         cat >>subject2template.job <<EOF

	      # compute fixel-based metric related to morphological differences in fibre cross-section
	      $SING warp2metric $BIDS_DWImrtrix/${parm}/${ses}/dwi/${parm}2template_warp.mif -fc $BIDS_DWImrtrix/template/fixel_mask $BIDS_DWImrtrix/template/fc ${parm}_${ses}.mif
EOF

      fi 

      cat >>subject2template.job <<EOF

	   # compute log(FC) for group statistical analysis of FC (recommended) 
	   ## SHOULD NOT BE REPEATED FOR EVERY SUBJECT!!!!
	   cp -n $BIDS_DWImrtrix/template/fc/index.mif  $BIDS_DWImrtrix/template/log_fc
	   cp -n $BIDS_DWImrtrix/template/fc/directions.mif $BIDS_DWImrtrix/template/log_fc
	   $SING mrcalc $BIDS_DWImrtrix/template/fc/${parm}_${ses}.mif -log $BIDS_DWImrtrix/template/log_fc/${parm}_${ses}.mif

	   # compute fibre density and fibre cross-section combined to account for changes to both within-voxel fibre density and macroscopic atrophy
	   ## SHOULD NOT BE REPEATED FOR EVERY SUBJECT!!!!
	   cp -n $BIDS_DWImrtrix/template/fc/index.mif $BIDS_DWImrtrix/template/fdc
	   cp -n $BIDS_DWImrtrix/template/fc/directions.mif $BIDS_DWImrtrix/template/fdc
	   $SING mrcalc $BIDS_DWImrtrix/template/fd/${parm}_${ses}.mif $BIDS_DWImrtrix/template/fc/${parm}_${ses}.mif -mult $BIDS_DWImrtrix/template/fdc/${parm}_${ses}.mif
EOF
	   TMPID=$(qsub subject2template.job -l mem=20gb -d. -j oe -o $BIDS_DWImrtrix/$parm/$ses/logs/ -N "mrtrix_subj2template_${parm}_${ses}" -W depend=afterok:$BARRIER7)
	   BARRIER8=$BARRIER8":"$TMPID
      mv subject2template.job ${BIDS_DWImrtrix}/${parm}/${ses}/jobs/
   done
done
echo $BARRIER8


## remaining steps from here on are executed from the template directory
cat preamble - >tractogram.job <<EOF
# generate a whole-brain tractogram from the FOD template
cd $BIDS_DWImrtrix/template
# $SING tckgen -angle 22.5 -maxlen 250 -minlen 10 -power 1.0 wmfod_template.mif -seed_image voxel_mask.mif -mask voxel_mask.mif -select 20000000 tracks_20_million.tck -nthreads 16
# *******CHANGE IN THE NEWEST MRtrix VERSION TO template_mask and set cutoff option
$SING tckgen -angle 22.5 -maxlen 250 -minlen 10 -power 1.0 wmfod_template.mif -seed_image template_mask.mif -mask template_mask.mif -select 20000000 -cutoff 0.06 tracks_20_million.tck -nthreads 16

# for display pruposes create a subset of the tracks that can be inspected
$SING tckedit tracks_20_million.tck -number 200k smallerTracks_200k.tck

# reduce tractography biases in the whole-brain tractogram
$SING tcksift tracks_20_million.tck wmfod_template.mif tracks_2_million_sift.tck -term_number 2000000 -nthreads 16

# for display pruposes create a subset of the tracks that can be inspected
$SING tckedit tracks_2_million_sift.tck -number 200k smallerSIFT_200k.tck

# to sample from predefined ROIs, we want to be able to transform MNI based atlas regions into template/subject space  
$SING mrconvert wmfod_template.mif wmfod_template.nii.gz

# perform statistical analysis using connectivity-based fixel enhancement **** NOT YET SUITABLE FOR LONGITUDINAL DATA
# ****** 128GB of RAM is a typical memory requirement
# $SING fixelcfestats fd files.txt design_matrix.txt contrast_matrix.txt tracks_2_million_sift.tck stats_fd
# $SING fixelcfestats log_fc files.txt design_matrix.txt contrast_matrix.txt tracks_2_million_sift.tck stats_log_fc
# $SING fixelcfestats fdc files.txt design_matrix.txt contrast_matrix.txt tracks_2_million_sift.tck stats_fdc
# files.txt is a text file containing the filename of each file (i.e. not the full path) to be analysed inside the input fixel directory, each filename on a separate line. The line ordering should correspond to the lines in the file design_matrix.txt.
EOF
qsub tractogram.job -d. -j oe -o $HOME/logs/ -l mem=128gb,walltime=50:00:00,nodes=1:ppn=16 -N "mrtrix_tractogram" -W depend=afterok$BARRIER8
mv tractogram.job $BIDS_DWImrtrix/jobs/