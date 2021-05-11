#!/bin/env bash
# Create symlink for structural, fieldmaps and dwi data

if [ $# != 4 ]; then
    echo "usage: $0 <BIDS_DIR> <BIDS_DIR_TMP> <sub-id> <ses-nr>"
    exit 1
else
    BIDS_DIR=$1
    BIDS_DIR_TMP=$2
    sub=$3
    ses=$4
fi

# Create a bids_dir_tmp dir if it does not exists.
if [ ! -e ${BIDS_DIR_TMP} ]; then
    mkdir -p ${BIDS_DIR_TMP}
fi

# Copy a dataset_description.json file to tmp bids if it does not exist.
if [ ! -e ${BIDS_DIR_TMP}/dataset_description.json ]; then
    cp ${BIDS_DIR}/dataset_description.json ${BIDS_DIR_TMP}/.
fi

# [1] Make new bids dir with symlinks to data
if [ ! -e ${BIDS_DIR_TMP}/${sub}${ses/-/} ]; then
    echo -n "> 1. Create directory ${BIDS_DIR_TMP}/${sub}${ses/-/} and symlinks to files... "
    mkdir -p ${BIDS_DIR_TMP}/${sub}${ses/-/}

    # data types
    for file_path in $(ls ${BIDS_DIR}/${sub}/${ses}/anat/* ${BIDS_DIR}/${sub}/${ses}/fmap/* ${BIDS_DIR}/${sub}/${ses}/dwi/* 2> /dev/null)
    do
        file=$(basename $file_path)
        directory=$(echo $file_path | awk -F"/" '{print $(NF-1)}')

        if [ ! -e ${BIDS_DIR_TMP}/${sub}${ses/-/}/${directory} ]; then
            mkdir ${BIDS_DIR_TMP}/${sub}${ses/-/}/${directory}
        fi

        ending=${file/${sub}_/}
        ending=${ending/${ses}_/}
        
        #echo ${sub}${ses/-/}/${directory}/${sub}${ses/-/}_${ending}

        # For fieldmaps we need to change the intendentFor in the json file for the new bids hierarchy
        if [ ${directory} == "fmap" ] && [ ${ending#*.} == "json" ]; then
            new_path=${BIDS_DIR_TMP}/${sub}${ses/-/}/${directory}/${sub}${ses/-/}_${ending}
            cp ${file_path} ${new_path}

            sed -i "s;${ses}/;;g" ${new_path}
            sed -i "s;${sub}_${ses};${sub}${ses/-/};g" ${new_path}

        else
            ln -s ${file_path} ${BIDS_DIR_TMP}/${sub}${ses/-/}/${directory}/${sub}${ses/-/}_${ending}
        fi
    done
    echo "OK"
fi