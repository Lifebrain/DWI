#!/bin/python3
# Purpose: Extract the slice order for the multiband acquisition
import json
import sys
import os
import glob

# Parse input parameters
if len(sys.argv) != 5:
    print("Usage:",sys.argv[0],"<BIDS_DIR>","<sub-id>","<ses-nr>","<output_name>")
    exit(1)
else:
    BIDS_MAIN_DIR = sys.argv[1]
    sub = sys.argv[2]
    ses = sys.argv[3]
    output_file = sys.argv[4]

# Extract slice timings and output to a text file with each row
# corresponding to one multiband group, and print to file.

dwi_path = os.path.join(BIDS_MAIN_DIR,sub,ses,"dwi")
filename = glob.glob(dwi_path + "/*_dwi.json")[0]

with open(filename, 'r') as oFile:
    dwi_json = json.load(oFile)

slice_timing = dwi_json["SliceTiming"]

multiband_groups = {}

for slice_time in slice_timing:
    i = 0
    if slice_time in multiband_groups:
        continue
    indeces = []
    for slice_time2 in slice_timing:
        if slice_time == slice_time2:
            indeces.append(i)
        i=i+1
    multiband_groups[slice_time] = indeces

with open(output_file, 'w') as oFile:
    for slice_time in sorted(multiband_groups):
        print(" ".join(map(str,multiband_groups[slice_time])), file=oFile)