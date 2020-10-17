#!/usr/bin/env bash

export OGR_SQLITE_CACHE=1024

read -d '' USAGE <<EOF
raster_to_polygon_grids INPUT_GRID_RASTER OUTPUT_GRID_POLYGON_VECTOR NODATAVALUE

INPUT_GRID_RASTER: input raster from which polygon grids are created. Only non
no-data pixels will be exported to grid polygons.

OUTPUT_GRID_POLYGON_VECTOR: output polygon grids in SQLite file. Each polygon
is a pixel with valid values, that is, not no-data values. 

NODATAVALUE: optional, a no-data value to filter out no-data pixels rather than
using the default no-data value of the input raster file. The default no-data
value of the raster is either defined in the raster or data type specific in
case not defined by the raster.
EOF

build_py_get_default_ndv () {
# one argument: gdal_type_name
cat <<EOF
import sys
import numpy as np
from osgeo import gdal_array, gdalconst

def getDefaultNoDataValue(dtype):
    dtype = np.dtype(dtype)
    try:
        ndv = np.iinfo(dtype).max
    except ValueError:
        ndv = np.finfo(dtype).max
    return ndv

gdal_type_code = eval("gdalconst.GDT_{0:s}".format(sys.argv[1]))
numpy_type = np.dtype(gdal_array.GDALTypeCodeToNumericTypeCode(gdal_type_code))
print(getDefaultNoDataValue(numpy_type))
EOF
}

raster_to_polygon_grids () {
	if [[ ${#} -eq 3 ]]; then
		local ndv=${3}
	fi
	local grid_raster=${1}
	local polygon_grid_vector=${2}
	local out_dir=$(dirname ${polygon_grid_vector})
	local my_tmpdir=${out_dir}

	local IMG_RES=$(gdalinfo -json ${grid_raster} | jq -r .geoTransform[1])
	if [[ -z ${ndv} ]]; then
		ndv=$(gdalinfo -json ${grid_raster} | jq -r .bands[0].noDataValue)
	fi
	if [[ -z ${ndv} ]]; then
		type_name=$(gdalinfo -json ${grid_raster} | jq -r .bands[0].type)
		ndv=$(build_py_get_default_ndv | python - ${type_name})
	fi

	# Polygonize the pixels into individual grids covered by laser shots
	# 1. created a CSV file using gridded ASCII XYZ format
	local covered_xyz=${grid_raster/%".tif"/".csv"}
	local tmp_xyz=$(mktemp -p ${my_tmpdir} --suffix ".xyz")
	gdal_translate -of XYZ -co COLUMN_SEPARATOR="," ${grid_raster} ${tmp_xyz}
	# 2. Filter out grid cells (lines in XYZ file) that has no-data values
	echo "easting,northing,covered" > ${covered_xyz}
	grep --invert-match ",${ndv}$" ${tmp_xyz} >> ${covered_xyz}
	# 3. Add lat and lon to the CSV file
    local SRS="$(gdalinfo -json ${grid_raster} | jq -r .coordinateSystem.wkt)"
	local tmp_covered_wgs=$(mktemp -p ${my_tmpdir} --suffix ".txt")
	read -r -d '' awk_script <<- 'EOF'
	{
		# skip header
		if ( NR > 1 ) {
			printf ("%f %f\n", $1, $2);
		}
	}
	EOF
	echo "lon,lat" > ${tmp_covered_wgs}
	awk -F"," "${awk_script}" ${covered_xyz} | gdaltransform -s_srs "${SRS}" -t_srs "EPSG:4326" -output_xy | tr -s "[:blank:]" "," >> ${tmp_covered_wgs}
	# 4. Create a CSV that has a column that contains polygon geometry
	# definitions in WKT.
	local tmp_grid_xyz=$(mktemp -p ${my_tmpdir} --suffix ".csv")
	local covered_grid_xyz=${covered_xyz/%".csv"/"_grids.csv"}

	# local tmp_awkfile=$(mktemp -p ${my_tmpdir} --suffix ".awk")

	local offset_dist=$(echo "${IMG_RES}*0.5" | bc -l)
	read -r -d '' awk_script <<- EOF
	{
		# skip header
		if ( NR > 1 ) {
			printf ("\"POLYGON ((%f %f, %f %f, %f %f, %f %f, %f %f))\",%f,%f,%d,%d\n", \
				\$1-${offset_dist}, \$2-${offset_dist}, \
				\$1-${offset_dist}, \$2+${offset_dist}, \
				\$1+${offset_dist}, \$2+${offset_dist}, \
				\$1+${offset_dist}, \$2-${offset_dist}, \
				\$1-${offset_dist}, \$2-${offset_dist}, \
				\$1, \$2, \$3, NR-1);
		}
		else {
			printf ("%s,%s,%s,%s,%s\n", "geom", "easting", "northing", \$3, "seq_id");
		}
	}
	EOF
	awk -F"," "${awk_script}" ${covered_xyz} > ${tmp_grid_xyz}
	paste -d "," ${tmp_grid_xyz} ${tmp_covered_wgs} > ${covered_grid_xyz}
	local covered_grid_csvt=${covered_grid_xyz/%".csv"/".csvt"}
	echo '"WKT","Real","Real","Integer","Integer","Real","Real"' > ${covered_grid_csvt}
    # 5. Create a polygon vector (sqlite) of covered grid cells from the CSV file
    local layer_name=$(basename ${polygon_grid_vector} '.sqlite')
    layer_name=${layer_name,,}
	ogr2ogr -f "SQLite" -dsco SPATIALITE=YES -lco SPATIAL_INDEX=YES \
        -overwrite -a_srs "${SRS}" \
        -nln ${layer_name} \
        -oo GEOM_POSSIBLE_NAMES="geom" -oo HEADERS=YES -oo KEEP_GEOM_COLUMNS=NO \
        ${polygon_grid_vector} ${covered_grid_xyz}
 
	rm -f ${tmp_covered_wgs} ${tmp_grid_xyz}
	rm -f ${tmp_xyz} ${covered_xyz} ${covered_grid_xyz} ${covered_grid_csvt}
}
export -f raster_to_polygon_grids

if [[ ${#} -eq 2 ]]; then
	raster_to_polygon_grids ${1} ${2}
elif [[ ${#} -eq 3 ]]; then
	raster_to_polygon_grids ${1} ${2} ${3}
else
	echo "${USAGE}"
fi
