#!/usr/bin/env python

# A simple script to estimate Canopy Cover (CC) from the LVIS L2B data in ASCII
# format. Write the estimated CC into an additional column of the L2B ASCII
# file.
# python est_cc_from_lvis2.py input_lvis2b.txt output_with_cc.txt
# 
# Zhan Li, zhan.li@canada.ca
# Created: Thu Dec  5 16:37:21 PST 2019

import sys
import os

import numpy as np

def main():
    # Threshold to separate canopy and below-canopy parts, unit, meter, same as
    # the RH columns in LVIS2B data. This value is from Paul Montesano at GSFC,
    # NASA. 
    rh_thresh = 1.37 

    if len(sys.argv) != 3:
        msg_str = "Wrong number of arguments to run this script!\n"
        msg_str += "Usage: \n"
        msg_str += "python {0:s} input_lvis2b.txt output_with_cc.txt".format(os.path.basename(sys.argv[0]))
        raise RuntimeError(msg_str)

    in_file = sys.argv[1]
    out_file = sys.argv[2]

    rh_pct = [10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, \
              90, 95, 96, 97, 98, 99, 100]
    rh_pct = np.asarray(rh_pct)
    in_arr = np.genfromtxt(in_file, comments="#", usecols=list(range(9, 32)))
    flag_arr = in_arr>rh_thresh
    tmp_arr = np.where(flag_arr, np.cumsum(flag_arr, axis=1), len(rh_pct)+1)
    icol = np.argmin(tmp_arr, axis=1)
    icol[np.sum(flag_arr, axis=1)==0] = len(rh_pct) - 1
    cc_arr = 100 - rh_pct[icol]
    
    # Write output
    print("Write output ASCII file ...")
    with open(in_file) as in_fobj, open(out_file, "w") as out_fobj:
        i = 0
        for line in in_fobj:
            if line[0]=="#":
                if line.strip("\n")=="# LFID SHOTNUMBER TIME GLON GLAT ZG TLON TLAT ZT RH10 RH15 RH20 RH25 RH30 RH35 RH40 RH45 RH50 RH55 RH60 RH65 RH70 RH75 RH80 RH85 RH90 RH95 RH96 RH97 RH98 RH99 RH100 AZIMUTH INCIDENTANGLE RANGE COMPLEXITY CHANNEL_ZT CHANNEL_ZG CHANNEL_RH":
                    out_fobj.write("{0:s}\tCC_PERCENT\n".format(line.strip("\n")))
                else:
                    out_fobj.write(line)
            else:
                out_fobj.write("{0:s}\t{1:.0f}\n".format(line.strip("\n"), cc_arr[i]))
                i += 1

if __name__ == "__main__":
    main()
