#!/usr/bin/env bash

read -d '' USAGE <<EOF
grids_cut_shots GRID_VECTOR SHOT_VECTOR OUT_VECTOR

GRID_VECTOR: a vector file of polygon grids that will cut or technically
intersect with polygons of laser shots that are usually modeled as circles.

SHOT_VECTOR: a vector file of laser shots, usually modeled as circles.

OUT_VECTOR: output vector file of the intersection, that is from grids cutting
shots.

Note: All the vector files are preferentially in SQLite format to significantly
improve processing speed. Using shapefile results in really slow processing.
EOF

# Increase SQLite page cache size to speed up
# Default cache size is 2000 pages, about 2MB? Mem, too small and too slow
# http://www.gaia-gis.it/gaia-sins/spatialite-cookbook-5/cookbook_topics.05.html#topic_System_level_performace_hints
# Furthermore, using spatial index on ESRI Shapefile format does NOT speed up
# queries and operations. Better always explicitly create spatial index on a
# SQLite file.
export OGR_SQLITE_CACHE=1024

grids_cut_shots () {
# This function uses Spatialite of SQLite to do intersection
	if [[ ${#} -ne 3 ]]; then
		echo "Usage:"
		echo "grids_cut_shots GRID_VECTOR SHOT_VECTOR OUT_VECTOR"
		return 1
	fi

	local grid_vector=${1}
	local shot_vector=${2}
	local intersect_vector=${3}

	local out_dir=$(dirname ${intersect_vector})
	local my_tmpdir=$(mktemp -d -p ${out_dir})
	local out_layer_name=$(basename ${intersect_vector} | rev | cut -d '.' -f2- | rev)

	# Intersection of circles and grids
	# 1. Create a VRT of two vector layers
	local merged_vector="$(mktemp -u -p ${my_tmpdir} --suffix .sqlite)"
	echo ogrmerge.py -f SQLite -overwrite_ds -o ${merged_vector} ${shot_vector} ${grid_vector} -nln "{LAYER_NAME}" -dsco SPATIALITE=YES -lco SPATIAL_INDEX=YES
	ogrmerge.py -f SQLite -overwrite_ds -o ${merged_vector} ${shot_vector} ${grid_vector} -nln "{LAYER_NAME}" -dsco SPATIALITE=YES -lco SPATIAL_INDEX=YES
	# 2. Use Spatilite (geospatial extension of SQLite) to generate intersection of covered grids and laser shot circles
	local grid_layer=$(basename ${grid_vector} | rev | cut -d '.' -f2- | rev)
	local shot_layer=$(basename ${shot_vector} | rev | cut -d '.' -f2- | rev)
	local grid_cols=($(fio info ${grid_vector} | jq .schema.properties | head -n -1 | tail -n +2 | awk -F ":" '{ printf("grd.%s\n", $1); }' | tr -d "\"" | tr -d [:blank:]))
	local shot_cols=($(fio info ${shot_vector} | jq .schema.properties | head -n -1 | tail -n +2 | awk -F ":" '{ printf("buf.%s\n", $1); }' | tr -d "\"" | tr -d [:blank:]))
	local grid_cols_str="$(echo ${grid_cols[@]} | tr -s [:blank:] ',')"
	local shot_cols_str="$(echo ${shot_cols[@]} | tr -s [:blank:] ',')"

	read -r -d '' SQL_STR <<- EOF
	SELECT 
		ST_Intersection(grd.geometry, buf.geometry) AS geometry, ${grid_cols_str}, ${shot_cols_str} 
	FROM ${grid_layer} AS grd, ${shot_layer} AS buf 
	WHERE buf.ROWID IN ( 
		SELECT ROWID 
		FROM SpatialIndex 
		WHERE f_table_name = '${shot_layer}' AND search_frame = grd.geometry 
	) AND ST_Intersects(grd.geometry, buf.geometry) = 1
	EOF

	local tmp_vector="$(mktemp -u -p ${my_tmpdir} --suffix .sqlite)"
	echo ogr2ogr -gt 1000000 -f "SQLite" -overwrite -sql "${SQL_STR}" \
		-dialect "SQLITE" ${tmp_vector} ${merged_vector} \
		-dsco SPATIALITE=YES -lco SPATIAL_INDEX=YES \
		-nln ${out_layer_name} \
		-nlt POLYGON
	ogr2ogr -gt 1000000 -f "SQLite" -overwrite -sql "${SQL_STR}" \
		-dialect "SQLITE" ${tmp_vector} ${merged_vector} \
		-dsco SPATIALITE=YES -lco SPATIAL_INDEX=YES \
		-nln ${out_layer_name} \
		-nlt POLYGON

	# Calculate distance between laser shot center and pixel center
	local SRID=$(fio info --crs ${shot_vector} | cut -d ':' -f2)
	read -r -d '' SQL_STR <<- EOF
	SELECT 
		*, 
		ST_Area(geometry) AS ac_by_shot, 
		ST_Distance(MakePoint(geasting, gnorthing, ${SRID}), MakePoint(easting, northing, ${SRID})) AS dist_shot2pixel 
	FROM ${out_layer_name} 
	EOF
	echo ogr2ogr -overwrite -gt 1000000 -f "SQLite" -dialect "SQLITE" \
		-sql "${SQL_STR}" ${intersect_vector} ${tmp_vector} \
		-dsco SPATIALITE=YES -lco SPATIAL_INDEX=YES \
		-nln ${out_layer_name} \
		-nlt POLYGON
	ogr2ogr -overwrite -gt 1000000 -f "SQLite" -dialect "SQLITE" \
		-sql "${SQL_STR}" ${intersect_vector} ${tmp_vector} \
		-dsco SPATIALITE=YES -lco SPATIAL_INDEX=YES \
		-nln ${out_layer_name} \
		-nlt POLYGON

	rm -rf ${my_tmpdir}
}
export -f grids_cut_shots

if [[ ${#} -eq 3 ]]; then
	grids_cut_shots ${1} ${2} ${3}
else
	echo "${USAGE}"
fi
