# grid-nasa-lvis-l2
**Grid laser-shot-based LVIS L2 data from NASA into raster data**

Contact: Zhan Li, zhanli AT gfz-potsdam dot de, zhanli1986 AT gmail dot com

This is part of the work by Zhan Li at Pacific Forestry Centre of Canadian
Forest Service. 

## Overview
NASA’s Land, Vegetation, and Ice Sensor (aka the Laser Vegetation Imaging
Sensor or LVIS) is a full-waveform airborne lidar sensor [[1]](#1). The large
footprints of LVIS laser shots approximate circles with diameters at tens of
meters. These laser shots are geolocated and their return waveforms are
processed into the LVIS L2 data products by NASA [[2]](#2). For example data,
check one of the LVIS L2 products from the Arctic-Boreal Vulnerability
Experiment (ABoVE) Airborne Campaign [[3]](#3). 

This repo of scripts grid the shot-based LVIS L2 data into raster data, given a
raster grid of user-defined resolution and spatial reference system. Gridded
products allow easier synergetic uses of LVIS data with other remote sensing
products, particularly terrestrial remote sensing data from medium resolution
satellites such as Landsat and Sentinel-2.

The gridding procedure in this repo uses weighted average of LVIS L2 variable
values from all the shots covering a grid cell. The weight of each shot is the
area of this shot covering a grid cell.

## Installation
__NOTE: the program is tested only on Linux system.__

The required dependencies of this repository are listed in the file
`environment.yml`. Two recommended ways to install these dependencies. 

### Install dependencies via [`conda` program](https://docs.conda.io/projects/conda/en/latest/index.html)
1. [Install `conda`](https://docs.conda.io/projects/conda/en/latest/commands/install.html)

2. [Create a conda environment](https://docs.conda.io/projects/conda/en/latest/user-guide/tasks/manage-environments.html#creating-an-environment-from-an-environment-yml-file)
   using the file `environment.yml` in the repository. 

### Unpack dependencies from a pre-zipped file
The dependencies are pre-packaged into a zipped file by [`conda-pack`
program](https://conda.github.io/conda-pack/). This zipped file, called
*conda-env-rasterio.tar.gz*, comes with [__*a
release*__](https://github.com/zhanlilz/grid-nasa-lvis-l2/releases) that you
may download from [this repository on github](https://github.com/zhanlilz/grid-nasa-lvis-l2). 

To install the dependencies for using scripts in this repo, 

1. Unzip *conda-env-rasterio.tar.gz* into a directory you may name *your_dir*
```
$ tar -C your_dir -xzf conda-env-rasterio.tar.gz
```

2. Run the following command to set up environment variables
```
$ source your_dir/bin/activate
$ conda-unpack
```

3. Now you are ready to use the scripts.

## Quickstart
Use the main script `grid_lvis_l2.py` to do all the steps in one go that
convert an ASCII file of LVIS L2 data into a point vector (preferentially in
SQLite format) where each point represents the center of a grid cell that is
covered partially or fully by one or more LVIS laser shots. Each point is
attached with user-selected LVIS L2 variables to be gridded. Each point is also
attached with some ancillary fields that help determine the goodness of
coverage of a grid cell by laser shots, such as shot coverage percentage,
distance from grid cell centers to covering shot centers, etc.

To see help for this main script

``` 
$ python grid_lvis_l2.py -h 
```

From a point vector of grid cell centers, you can generate a raster file of any
field you like using the script `rasterize_vector.py`. This script rasterizes
vector files into raster files based on `gdal_rasterize` but with some special
treatment/improvements of the rasterization, including, 

1. when rasterizing points on regular grids, points will be placed in the
   center of rasterized pixels.

2. when given a template raster, the input vector will be rasterized into a
   grid that is aligned with the given template raster.

To see help for this script
```
$ python rasterize_vector.py -h
```

## Examples
* **Grid an LVIS L2 product in ASCII format into a 20-m grid in UTM Zone 9
  projection. The ASCII file *LVIS2_ABoVE2017_0630_R1803_069010.TXT* is
downloaded from [[3]](#3).**

```
$ python grid_lvis_l2.py -r 20 \
	--out_srs 'PROJCS["UTM Zone 9, Northern Hemisphere",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]],PROJECTION["Transverse_Mercator"],PARAMETER["latitude_of_origin",0],PARAMETER["central_meridian",-129],PARAMETER["scale_factor",0.9996],PARAMETER["false_easting",500000],PARAMETER["false_northing",0],UNIT["Meter",1]]' \
	--column_type lvis_l2_column_types.csvt \
	--column2grid rh10 rh99 -- \
	LVIS2_ABoVE2017_0630_R1803_069010.TXT LVIS2_ABoVE2017_0630_R1803_069010_grid_points.sqlite
```

The file *lvis_l2_column_types.csvt* lists the data types of each column of input ASCII file *LVIS2_ABoVE2017_0630_R1803_069010.TXT*. An example of the file content of *lvis_l2_column_types.csvt* is as follows, 

> "Integer","Integer","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Real","Integer","Integer","Integer"

See [[4]](#4) for more details on this .csvt file type to define data types of columns in ASCII files.

* **Grid an LVIS L2 product in ASCII format into a raster grid that aligns with
  a given template raster in the same spatial reference system. Meanwhlie,
after the gridding process, it will keep intermediate files that are generated
by gridding.** 


```
$ python grid_lvis_l2.py --keep_intermediate \
	-t template_raster.tif \
	--column_type lvis_l2_column_types.csvt \
	--column2grid rh10 rh98 rh99 rh100 complexity -- \
	LVIS2_ABoVE2017_0629_R1803_092329_with_cc.TXT LVIS2_ABoVE2017_0629_R1803_092329_grid_points.sqlite
```

* **Generate a raster of rh10 variable from the point vector of grid cell
  centers, at 20-m resolution in GeoTiff format.**

```
$ python rasterize_vector.py -r 20 -a rh10_wt_avg -f GTiff --nodata -9999 --init -9999 \
	--ot Float32 \
	LVIS2_ABoVE2017_0630_R1803_069010_grid_points.sqlite LVIS2_ABoVE2017_0630_R1803_069010_grid_points_rh10_wt_avg.tif
```

* **Convert a sqlite file of point vectors of grid cells to a CSV file for
easy inspection.**

```
$ ogr2ogr -f CSV -lco GEOMETRY=AS_XY \
	LVIS2_ABoVE2017_0629_R1803_057198_grid_points.csv LVIS2_ABoVE2017_0629_R1803_057198_grid_points.sqlite
```

## References
<a id="1">[1]</a> Blair, J.B., Rabine, D.L., Hofton, M.A., 1999. The Laser Vegetation Imaging Sensor: a medium-altitude, digitisation-only, airborne laser altimeter for mapping vegetation and topography. ISPRS J. Photogramm. Remote Sens. 54, 115–122. https://doi.org/10.1016/S0924-2716(99)00002-7

<a id="2">[2]</a> https://lvis.gsfc.nasa.gov/Data/DataStructure.html

<a id="3">[3]</a> https://nsidc.org/data/ABLVIS2

<a id="4">[4]</a> https://giswiki.hsr.ch/GeoCSV#CSVT_file_format_specification
