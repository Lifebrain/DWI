#!/bin/env python3
# Purpose: Output "slm" option for eddy params. Either none or linear.
# 
# High quality data with 60 directions or more, and full sphere data,
# should have slm=none, while other data should have slm=linear.

import numpy as np
import sys
import os.path as op
import glob

# Parse input parameters
if len(sys.argv) != 4:
    print("Usage:",sys.argv[0],"<BIDS_DIR>","<sub-id>","<ses-id>")
    exit(1)
else:
    BIDS_DIR = sys.argv[1]
    sub = sys.argv[2]
    ses = sys.argv[3]

def read_file(filename):
    data = []
    with open(filename, 'r') as File:
        for line in File:
            data.append(line.split())
    return data

bvec_files=glob.glob(op.join(BIDS_DIR,sub,ses,"dwi",sub+"_"+ses+"*_dwi.bvec"))
bval_files=glob.glob(op.join(BIDS_DIR,sub,ses,"dwi",sub+"_"+ses+"*_dwi.bval"))

high_quality = False

for i in range(0,len(bvec_files)):
    bvec_data = read_file(bvec_files[i])
    bval_data = read_file(bval_files[i])

    bvec_data_1 = np.array(bvec_data[0]).astype(float)
    bvec_data_2 = np.array(bvec_data[1]).astype(float)
    bvec_data_3 = np.array(bvec_data[2]).astype(float)

    bval_data = np.array(bval_data[0]).astype(float)
    directions = len(bval_data[bval_data>100])

    test_1 = max(bvec_data_1)-min(bvec_data_1)
    test_2 = max(bvec_data_2)-min(bvec_data_2)
    test_3 = max(bvec_data_3)-min(bvec_data_3)
    #print(directions,test_1,test_2)
    if directions >= 60 and test_1 > 1.85 and test_2 > 1.85 and test_3 > 1.85:
        high_quality = True

if high_quality:
    print("none")
else:
    print("linear")

