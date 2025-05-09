#!/bin/bash

set -euo pipefail
usage() {
    echo -e "Usage: ${0} upstream-pax|pax|upstream-t5x|t5x|maxtext WORKFLOW_IDS..."
    exit 1
}

[ "$#" -ge "2" ] || usage

TYPE=$1
if [[ "$TYPE" == "upstream-t5x" ]]; then
    CONFIGS=(
        "1G1N"
        "1G2N"
        "1P1G"
        "1P2G"
        "1P4G"
        "1P8G"
        "2G1N"
        "2G2N"
        "4G1N"
        "4G2N"
        "8G1N"
        "8G2N"
        "1P1G_fmha"
        "1P2G_fmha"
        "2G2N_fmha"
        "8G2N_fmha"
    )
    OUTPUT_DIR=T5X_MGMN/upstream
elif [[ "$TYPE" == "rosetta-t5x" ]]; then
    CONFIGS=(
        "1N1G-te-1"
        "1N8G-te-1"
        "1P1G_te-0"
        "1P1G_te-1"
        "1P8G_te-1"
        "2N2G_te-0"
        "2N8G-te-1"
        "VIT1G1N"
        "VIT1G2N"
        "VIT1P8G"
        "VIT8G1N"
        "VIT8G2N"
    )
    OUTPUT_DIR=T5X_MGMN/rosetta
elif [[ "$TYPE" == "upstream-maxtext" ]]; then
    CONFIGS=(
	"1DP2FSDP4TP1PP_single_process"
	"2DP2FSDP2TP1PP"
    )
    OUTPUT_DIR=MAXTEXT/upstream
else
    usage
fi
ALL_WF_RUNS=(${@:2})

# call download artifacts from this  script's dir
UTIL_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
bash ${UTIL_DIR}/download_artifacts.sh ${ALL_WF_RUNS[@]}

URLS=()
for WORKFLOW_RUN in ${ALL_WF_RUNS[@]}; do
  for CFG in ${CONFIGS[@]}; do
    CFG=$TYPE-$WORKFLOW_RUN-$CFG
    ARTS=$(find . -mindepth 1 -maxdepth 2 -type d -name $CFG)
    if (( $(echo ${ARTS} | wc -l) != 1 )); then
      echo "Expected one artifact to have a '$CFG' dir under '$PWD', but found ${ARTS}"
      exit 1
    fi
  done
  URLS+=("\"https://api.github.com/repos/NVIDIA/JAX-Toolbox/actions/runs/${WORKFLOW_RUN}/artifacts\"")
done

for CFG in ${CONFIGS[@]}; do
  # Average metrics data for this config
  run_dir_paths=""
  for run_id in ${ALL_WF_RUNS[@]}; do
    run_dir_paths+=" $run_id/${TYPE}-metrics-test-log"
  done

  python3 ${UTIL_DIR}/average_baselines.py --config ${CFG} --run_dirs $run_dir_paths --output_dir $OUTPUT_DIR
  
  # Append date and workflow sources
  cat <<< "$(jq -r '. += {"run_urls":['$(IFS=, ; echo "${URLS[*]}")'], "date":"'$(date +%Y-%m-%d)'"}' "$OUTPUT_DIR/${CFG}.json")" > $OUTPUT_DIR/${CFG}.json
done

cat <<EOF
========
Finished
========

Make sure that $OUTPUT_DIR reflects all the baselines you wish to evaluate against (and remove the ones that are no longer in use).

Afterwards, check $OUTPUT_DIR into version control.
EOF
