#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# 
# job submission command:
#   bsub -N -M 20000 -W 9000 -n 1 -J "tbss_launch" ./wrapper.tbss.sh

# Load modules
module load fsl/6.0.4
module load anaconda3/1.0.0

# Export FSL python to linker library
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${FSLDIR}/fslpython/envs/fslpython/lib

# Set directory variables
# scripts_dir=$(dirname $(realpath ${0}))
scripts_dir=/scratch/brac4g/dwi_analysis/code/tbss_proc
data_dir=$(realpath ../../data)
out_dir=$(realpath ../..)

_ddir=$(realpath ../designs/all_designs)
par_dirs=( $(cd ${_ddir}; ls ) )

# design_dirs=( $(ls -d $(realpath ${}/*)) )

for par_dir in ${par_dirs[@]}; do
  
  design_dirs=( $(ls -d ${_ddir}/${par_dir}/*) )

  for design_dir in ${design_dirs[@]}; do

    # Define output parent directory
    design=$(basename ${design_dir})
    tbss_out_dir=${out_dir}/TBSS/${par_dir}/${design}

    echo "Processing Design: ${par_dir} | ${design}"

    if [[ ! -f ${tbss_out_dir} ]]; then
      mkdir -p ${tbss_out_dir}
    fi

    # Define subject array
    mapfile -t subs < ${design_dir}/grp.design.include.txt

    # Create subject list
    if [[ ! -f ${tbss_out_dir}/subs.list.txt ]]; then
      for sub in ${subs[@]}; do
        echo "Processing subject: ${par_dir} | ${design} | ${sub}"
        fa_data=$(realpath ${data_dir}/${sub}/dwi_run-01/Tensor/${sub}_ses-001_run-01_FA.nii.gz)
        if [[ -f ${fa_data} ]]; then
          echo ${fa_data} >> ${tbss_out_dir}/subs.list.txt
        else
          echo "${par_dir} | ${design} | ${sub} does not exist"
        fi
      done
    fi

    # Define T design matrix and contrast
    design_mat=${design_dir}/grp.design.mat
    design_con=${design_dir}/grp.design.con

    # Perform TBSS analysis
    bsub -R "span[hosts=1]" -N -M 35000 -W 15000 -n 1 -J tbss_${par_dir}_${design} \
    ${scripts_dir}/tbss.sh \
    --tbss-dir ${tbss_out_dir}/tbss \
    --sub-list ${tbss_out_dir}/subs.list.txt \
    --design ${design_mat} \
    --contrast ${design_con} \
    --template ${FSLDIR}/data/standard/FMRIB58_FA_1mm.nii.gz \
    --fa-threshold 0.20 \
    --perm 5000 \
    --check-design \
    --non-FA-tbss
  done
done
