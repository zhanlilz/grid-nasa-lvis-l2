#!/usr/bin/env bash

export OGR_SQLITE_CACHE=1024

vectorize_lvis_l2 () {
    my_txt=${1}
    out_vector=${2}
    if [[ ${#} -gt 2 ]]; then
        my_csvt=${3}
    fi
    echo "${out_vector} <- ${my_txt}"

    SRS='GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.01745329251994328,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]]'

    LVIS2_VECTOR_DIR=$(dirname ${out_vector})
    tmp_csv=$(mktemp -p ${LVIS2_VECTOR_DIR} --suffix=".csv")
    head_str="$(head -n 13 ${my_txt} | tail -n 1)"
    head_str="${head_str#'# '}"
    head_str="$(echo ${head_str} | sed 's/ /,/g')"
    echo ${head_str} > ${tmp_csv}
    tail -n +14 ${my_txt} | tr -s '[:space:]' | awk '{$4 = $4 - 360; $7 = $7 - 360; print}' | sed 's/ /,/g' >> ${tmp_csv}
    NF=$(echo ${head_str} | awk -F',' '{ print NF }')

    tmp_csvt=${tmp_csv/%".csv"/".csvt"}
    if [[ -r ${my_csvt} ]]; then
        cat ${my_csvt} > ${tmp_csvt}
    else
        echo "No column types given, default to Real for every column."
        csvt_str=""
        for ((i=0; i<${NF}; i++)); do
            csvt_str="${csvt_str},\"Real\""
        done
        csvt_str=${csvt_str:1}
        echo ${csvt_str} > ${tmp_csvt}
    fi
    
    echo ogr2ogr -overwrite -f "SQLite" \
        -dsco SPATIALITE=YES -lco SPATIAL_INDEX=YES \
        -nln "$(basename ${out_vector} '.sqlite')" \
        -oo X_POSSIBLE_NAMES="GLON" -oo Y_POSSIBLE_NAMES="GLAT" \
        -a_srs "${SRS}" \
        ${out_vector} ${tmp_csv} 
    ogr2ogr -overwrite -f "SQLite" \
        -dsco SPATIALITE=YES -lco SPATIAL_INDEX=YES \
        -nln "$(basename ${out_vector} '.sqlite')" \
        -oo X_POSSIBLE_NAMES="GLON" -oo Y_POSSIBLE_NAMES="GLAT" \
        -a_srs "${SRS}" \
        ${out_vector} ${tmp_csv} 
    rm -f ${tmp_csv} ${tmp_csvt}
}
export -f vectorize_lvis_l2

read -d '' USAGE <<EOF

vectorize_lvis_l2.sh LVIS_L2_TXT LVIS_L2_VECTOR [COLUMN_TYPES]

LVIS_L2_TXT: an ASCII file of LVIS L2 data. See https://nsidc.org/data/ABLVIS2.

LVIS_L2_VECTOR: output vector file (SQLite format) of LVIS L2 data. 

COLUMN_TYPES, optional: a single line file that lists types of each column of the input LVIS L2 ASCII file, delimited by ",", data types can be simply Real/Integer/String. See https://giswiki.hsr.ch/GeoCSV#CSVT_file_format_specification for more details.

EOF

if [[ ${#} -eq 3 ]]; then
    vectorize_lvis_l2 ${1} ${2} ${3}
elif [[ ${#} -eq 2 ]]; then
    vectorize_lvis_l2 ${1} ${2}
else
    echo "${USAGE}"
fi
