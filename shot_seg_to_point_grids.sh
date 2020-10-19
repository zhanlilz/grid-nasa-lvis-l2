#!/usr/bin/env bash

read -d '' USAGE <<EOF
shot_seg_to_point_grids.sh VECTOR_OF_SHOT_SEG OUT_VECTOR_OF_POINT_GRIDS GRID_RES FIELD2AGG FIELD2AGG ... FIELD2AGG

VECTOR_OF_SHOT_SEG: polygon vector file of segmented LVIS laser shots. Segments
are from a raster grid intersecting/cutting laser shots.

OUT_VECTOR_OF_POINT_GRIDS: output point vector file by aggregating/grouping
shot segments that fall into the same grid cells. Each point in the output
vector is the center of a grid cell.

GRID_RES: spatial resolution of grid cells, in the unit of input vector file of
shot segments.

FIELD2AGG: optional, one or multiple fields in the VECTOR_OF_SHOT_SEG file to
aggregate and ouput to OUT_VECTOR_OF_POINT_GRIDS. 

Note: All the vector files are preferentially in SQLite format to significantly
improve processing speed. Using ESRI Shapefile results in really slow
processing.
EOF

# Increase SQLite page cache size to speed up
# Default cache size is 2000 pages, about 2MB? Mem, too small and too slow
# http://www.gaia-gis.it/gaia-sins/spatialite-cookbook-5/cookbook_topics.05.html#topic_System_level_performace_hints
# Furthermore, using spatial index on ESRI Shapefile format does NOT speed up
# queries and operations. Better always explicitly create spatial index on a
# SQLite file.
export OGR_SQLITE_CACHE=1024

shot_seg_to_point_grids () {
    local shotseg_vector=${1}
    local gridded_vector=${2}
    local IMG_RES=${3}
    local fields=(${@:4})

    local shotseg_layer=$(basename ${shotseg_vector} | rev | cut -d '.' -f2- | rev)
    
    if [[ -r ${gridded_vector} ]]; then
        rm -rf ${gridded_vector}*
    fi

    local COL4GROUP="seq_id"
    local COL4WT="ac_by_shot"
    local COLS2COPY=(easting northing covered seq_id lon lat)
    local COLS2STATS=(glon glat zg tlon tlat zt azimuth incidentangle range \
        geasting gnorthing ac_by_shot dist_shot2pixel ${fields[@]})
    local select_str4copy=""
    for ((k=0; k<${#COLS2COPY[@]}; k++)) {
        select_str4copy="${select_str4copy}AVG(${COLS2COPY[$k]}) AS ${COLS2COPY[$k]}, "
    }
    select_str4copy=${select_str4copy/%", "}
    local select_str4stats=""
    for ((k=0; k<${#COLS2STATS[@]}; k++)) {
        select_str4stats="${select_str4stats}AVG(${COLS2STATS[$k]}) AS ${COLS2STATS[$k]}_avg, "
        select_str4stats="${select_str4stats}MIN(${COLS2STATS[$k]}) AS ${COLS2STATS[$k]}_min, "
        select_str4stats="${select_str4stats}MAX(${COLS2STATS[$k]}) AS ${COLS2STATS[$k]}_max, "
        select_str4stats="${select_str4stats}SUM(${COLS2STATS[$k]}*${COL4WT})/SUM(${COL4WT}) AS ${COLS2STATS[$k]}_wt_avg, "
    }
    select_str4stats=${select_str4stats/%", "}
    
    local SRID=$(ogrinfo ${shotseg_vector} -dialect "sqlite" \
        -sql "SELECT SRID(geometry) FROM ${shotseg_layer} LIMIT 1" \
        | grep "SRID(geometry) (Integer) = " | cut -d "=" -f2 \
        | tr -d [:blank:])

    read -r -d '' SQL_STR <<- EOF
    SELECT 
        MakePoint(AVG(easting), AVG(northing), ${SRID}) AS geometry, 
        COUNT(${COL4GROUP}) AS shot_count,
        ST_Area(ST_Union(geometry))/(${IMG_RES}*${IMG_RES}) AS sc_percent, 
        ${select_str4copy}, 
        ${select_str4stats} 
    FROM ${shotseg_layer} 
    GROUP BY ${COL4GROUP}
EOF
    out_layer_name=$(basename ${gridded_vector} | rev | cut -d '.' -f2- | rev)
    echo ogr2ogr -overwrite -gt 1000000 -f "SQLite" -dialect "SQLITE" \
        -sql "${SQL_STR}" ${gridded_vector} ${shotseg_vector} \
        -dsco SPATIALITE=YES -lco SPATIAL_INDEX=YES \
        -lco GEOMETRY_NAME=geometry \
        -nln ${out_layer_name} \
        -nlt POINT
    ogr2ogr -overwrite -gt 1000000 -f "SQLite" -dialect "SQLITE" \
        -sql "${SQL_STR}" ${gridded_vector} ${shotseg_vector} \
        -dsco SPATIALITE=YES -lco SPATIAL_INDEX=YES \
        -nln ${out_layer_name} \
        -nlt POINT
}
export -f shot_seg_to_point_grids

if [[ ${#} -ge 3 ]]; then
    shot_seg_to_point_grids ${@}
else
    echo "${USAGE}"
fi
