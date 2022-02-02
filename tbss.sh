#!/usr/bin/env bash
# -*- coding: utf-8 -*-

#
# Define Usage(s) & (Miscellaneous) Function(s)
#==============================================================================

# Usage
Usage() {
  cat << USAGE

  Usage: $(basename ${0}) [options] --tbss-dir <DIRECTORY> --sub-list <LIST.txt> --design <DESIGN.mat> --contrast <DESIGN.con>

Required Arguments

  -tbss, --tbss-dir          Output TBSS directory to store results
  -sub, --sub-list          Subject list with absolute path to each subject's FA image
  -des, --design            FSL-style T-test design matrix
  -con, --contrast          FSL-style T-test design contrast

Optional Arguments

  -template, --template     Standard space FA Template to be used in the analysis [default: FMRIB58_FA_1mm.nii.gz]
  -fa, --fa-threshold       FA-threshold for skeletonization (0.15 recommneded in the case of neonates) [default: 0.20]
  --perm                    Number of permutations to be performed [default: 5000]
  --check-design            Checks the input design matrix and the subject list to ensure that the same number of 
                              subjects appear in the T-test design matrix
  --non-FA-tbss             Perform non-FA TBSS for AD, RD, and MD

----------------------------------------

-h,-help,--help             Prints usage and exits.

NOTE:
  * The '--non-FA-tbss' requires that the AD, RD, and MD files should already be computed and be named similarly to 
      the input FA files.

$(basename ${0}) v0.0.1

----------------------------------------

  Usage: $(basename ${0}) [options] --tbss-dir <DIRECTORY> --sub-list <LIST.txt> --design <DESIGN.mat> --contrast <DESIGN.con>

USAGE
  exit 1
}

#
# Define Logging Function(s)
#==============================================================================

# Echoes status updates to the command line
echo_color(){
  msg='\033[0;'"${@}"'\033[0m'
  # echo -e ${msg} >> ${stdOut} 2>> ${stdErr}
  echo -e ${msg} 
}
echo_red(){
  echo_color '31m'"${@}"
}
echo_green(){
  echo_color '32m'"${@}"
}
echo_blue(){
  echo_color '36m'"${@}"
}

exit_error(){
  echo_red "${@}"
  exit 1
}

# log function 
run()
{
  echo "${@}"
  "${@}" >>${log} 2>>${err}
  if [ ! ${?} -eq 0 ]; then
    echo "failed: see log files ${log} ${err} for details"
    exit 1
  fi
  echo "-----------------------"
}

#
# Parse options
#==============================================================================

# Define defaults
n_perm=5000
fa_threshold=0.2
template=${FSLDIR}/data/standard/FMRIB58_FA_1mm.nii.gz
check_design=false
non_FA=false

# Parse options
while [[ ${#} -gt 0 ]]; do
  case "${1}" in
    -tbss|--tbss-dir) shift; tbss_dir=${1} ;;
    -template|--template) shift; template=${1} ;;
    -sub|--sub-list) shift; subject_list=${1} ;;
    -des|--design) shift; design=${1} ;;
    -con|--contrast) shift; contrast=${1} ;;
    -fa|--fa-threshold) shift; fa_threshold=${1} ;;
    --perm) shift; n_perm=${1} ;;
    --check-design) check_design=true ;;
    --non-FA-tbss) non_FA=true ;;
    -h|-help|--help) Usage; ;;
    -*) echo_red "$(basename ${0}): Unrecognized option ${1}" >&2; Usage; ;;
    *) break ;;
  esac
  shift
done

#
# Check options
#==============================================================================

# Check Required arguments
if [[ -z ${tbss_dir} ]]; then
  echo_red "'--tbss-dir' argument required."
  run echo "'--tbss-dir' argument required."
  exit 1
fi

if [[ -z ${subject_list} ]] || [[ ! -f ${subject_list} ]]; then
  echo_red "'--sub-list' option was not specified or the file does not exist."
  run echo "'--sub-list' option was not specified or the file does not exist."
  exit 1
else
  subject_list=$(realpath ${subject_list})
fi

if [[ -z ${design} ]] || [[ ! -f ${design} ]]; then
  echo_red "'--design' option was not specified or the file does not exist."
  run echo "'--design' option was not specified or the file does not exist."
  exit 1
else
  design=$(realpath ${design})
fi

if [[ -z ${contrast} ]] || [[ ! -f ${contrast} ]]; then
  echo_red "'--contrast' option was not specified or the file does not exist."
  run echo "'--contrast' option was not specified or the file does not exist."
  exit 1
else
  contrast=$(realpath ${contrast})
fi

# Check Optional arguments
if [[ -z ${template} ]] || [[ ! -f ${template} ]]; then
  echo_red "'--template' option was not specified or the file does not exist."
  run echo "'--template' option was not specified or the file does not exist."
  exit 1
else
  template=$(realpath ${template})
fi

# Check integer options
if [[ ! -z ${n_perm} ]]; then
  if ! [[ "${n_perm}" =~ ^[0-9]+$ ]]; then
    echo_red "'--perm' argument requires integers only [1 - 9999999]"
    run echo "'--perm' argument requires integers only [1 - 9999999]"
    exit 1
  fi
fi

# Check float options
if [[ ! -z ${fa_threshold} ]]; then
  if ! [[ "${fa_threshold}" =~ ^[+-]?[0-9]+\.?[0-9]*$ ]]; then
    echo_red "'--fa-threshold' argument requires floats [0.0 - 9999999.0]"
    run echo "'--fa-threshold' argument requires floats [0.0 - 9999999.0]"
    exit 1
  fi
fi

#
# Copy data to output TBSS directory
#==============================================================================

# NOTE: design matrix must be organized in the same manner in which
# subjects are shown in a directory. 

# Create subject array
mapfile -t subs < ${subject_list}

# Check if the number of subjects' data is equal to the number of subjects 
# in the design
mapfile -t design_num < ${design}

if [[ ${check_design} = "true" ]]; then
  if [[ ${#subs[@]} != $((${#design_num[@]} - 3)) ]]; then
    echo_red "ERROR: Design matrix does not contain the correct number of subjects"
    exit 1
  fi
fi

# Organize TBSS directory
if [[ ! -d ${tbss_dir} ]]; then
  mkdir -p ${tbss_dir}
fi

tbss_dir=$(realpath ${tbss_dir})

if [[ ! -d ${tbss_dir}/FA ]]; then
  for sub in ${subs[@]}; do
    data_path=$(dirname ${sub})
    data_file=$(echo $(basename $(remove_ext ${sub})) | sed "s@_FA@@g")
    imcp ${data_path}/${data_file}_FA ${tbss_dir}/${data_file} &
  done
else
  echo "Subject FA data already present."
fi

wait

# Re-init subject array
subs=( $(cd ${tbss_dir}; ls $(pwd)/*.nii* 1> /dev/null 2>&1 | sort) )

#
# Perform TBSS Analysis
#==============================================================================

cd ${tbss_dir}

if [[ ! -d ${tbss_dir}/stats ]]; then 
  # TBSS (Stage 1: Image Erosion and End Slice Zeroing)
  tbss_1_preproc *.nii*

  # TBSS (Stage 2: Non-linear Registration to target FA Template)
  tbss_2_reg -t ${template}

  # TBSS (Stage 3: Applies Non-linear Registration to all subjects)
  tbss_3_postreg -S

  # TBSS (Stage 4: Pre-stats - Thresholding)
  cd ${tbss_dir}/stats

  # Thresholds the mean FA skeleton at at some arbitratry threshold 
  # prior to voxel-wise statistics (0.2 as default)
  tbss_4_prestats ${fa_threshold}
else 
  echo "TBSS processing steps already completed."
fi

cd ${tbss_dir}/stats
stats_dir=$(pwd)

cp ${design} design.mat
cp ${contrast} design.con

# TBSS (Stage 5: Stats - Permutation testing)
if [[ ! -f ${tbss_dir}/stats/tbss_FA_tfce_p_tstat1.nii.gz ]]; then
  bsub -n 1 -R "span[hosts=1]" -N -M 15000 -W 30000 -J FA_rdm -K \
  -o ${tbss_dir}/FA/00_tbss_FA_randomise.log \
  -e ${tbss_dir}/FA/00_tbss_FA_randomise.log \
  randomise -i all_FA_skeletonised -o tbss_FA -m mean_FA_skeleton_mask -d design.mat -t design.con -n ${n_perm} --T2 --uncorrp &
else
  echo "TBSS statistical analysis for FA measures have already been completed."
fi

fa_rdm_job_id=${!}

# # Fill significant areas
# wait ${fa_rdm_job_id}
# 
# stats_imgs=( $(ls *tbss_FA_tfce_corrp_tstat*.nii*) )
# 
# for stats_img in ${stats_imgs[@]}; do
#   tbss_fill ${stats_img} 0.95 mean_FA $(remove_ext ${stats_img})_filled
# done

#
# Perform non-FA TBSS Analyses
#==============================================================================

if [[ ${non_FA} = "true" ]]; then
  # TBSS (non-FA measures)
  measures=( AD MD RD )

  for measure in ${measures[@]}; do
    cd ${tbss_dir}
    if [[ ! -d ${tbss_dir}/${measure} ]]; then
      mkdir -p ${tbss_dir}/${measure}
    fi

    # Re-init subject array
    mapfile -t subs < ${subject_list}

    # Copy data for each measure
    if ! ls ${tbss_dir}/${measure}/*.nii* 1> /dev/null 2>&1; then
      for sub in ${subs[@]}; do
        data_path=$(dirname ${sub})
        data_file=$(echo $(basename $(remove_ext ${sub})) | sed "s@_FA@@g")
        imcp $(ls ${data_path}/${data_file}*${measure}*) ${tbss_dir}/${measure}/${data_file} &
        cp_img_id=${!}
      done
    else 
      echo "Subject ${measure} data already present."
    fi

    wait ${cp_img_id}

    # TBSS Stats for measure
    if [[ ! -f ${stats_dir}/all_${measure}_skeletonised.nii.gz ]]; then
      tbss_non_FA ${measure}
    else 
      echo "Skeletonised ${measure} has already been created."
    fi

    cd ${stats_dir}

    if [[ ! -f ${tbss_dir}/stats/tbss_${measure}_tfce_p_tstat1.nii.gz ]]; then
      bsub -n 1 -R "span[hosts=1]" -N -M 15000 -W 30000 -J ${measure}_rdm -K \
      -o ${tbss_dir}/${measure}/00_tbss_${measure}_randomise.log \
      -e ${tbss_dir}/${measure}/00_tbss_${measure}_randomise.log \
      randomise -i all_${measure}_skeletonised -o tbss_${measure} -m mean_FA_skeleton_mask -d design.mat -t design.con -n ${n_perm} --T2 --uncorrp &
    else
      echo "TBSS statistical analysis for ${measure} measures have already been completed."
    fi

    # stats_imgs=( $(ls *tbss_${measure}_tfce_corrp_tstat*.nii*) )
    # for stats_img in ${stats_imgs[@]}; do
    #   tbss_fill ${stats_img} 0.95 mean_FA $(remove_ext ${stats_img})_filled
    # done
  done
fi

#
# Complete TBSS FA analysis (Post-stats)
#==============================================================================

# Fill significant areas for FA images
wait ${fa_rdm_job_id}

cd ${stats_dir}
stats_imgs=( $(ls *tbss_FA_tfce_corrp_tstat*.nii* 1> /dev/null 2>&1) )

if ! ls *tbss_FA_tfce_corrp_tstat*fill*.nii* 1> /dev/null 2>&1; then
  for stats_img in ${stats_imgs[@]}; do
    echo "Processing: ${stats_img}"
    tbss_fill ${stats_img} 0.95 mean_FA $(remove_ext ${stats_img})_filled
  done
fi

#
# Complete TBSS non-aFA analyses (Post-stats)
#==============================================================================

wait

# Fill significant areas for non-FA images
if [[ ${non_FA} = "true" ]]; then
  # TBSS (non-FA measures)
  measures=( AD MD RD )
  cd ${stats_dir}

  for measure in ${measures[@]}; do

    stats_imgs=( $(ls *tbss_${measure}_tfce_corrp_tstat*.nii* 1> /dev/null 2>&1) )

    if ! ls *tbss_${measure}_tfce_corrp_tstat*fill*.nii* 1> /dev/null 2>&1; then
      for stats_img in ${stats_imgs[@]}; do
        echo "Processing: ${stats_img}"
        tbss_fill ${stats_img} 0.95 mean_FA $(remove_ext ${stats_img})_filled
      done
    fi
  done
fi

echo "TBSS analysis completed."
