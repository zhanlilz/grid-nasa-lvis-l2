#!/usr/bin/env python
#
# Grid LVIS L2 product into a designated raster grid.
#
# Zhan Li, zhan.li@canada.ca
# Created: Fri Jan  3 14:59:59 PST 2020

import argparse
import os
import subprocess
import tempfile
import shutil
import warnings
import sys

from osgeo import gdalconst, ogr, gdal_array, gdal, osr

import numpy as np

import affine

def getCmdArgs():
    desc_str = """
Grid LVIS L2 product into a designated raster grid.
    """
    p = argparse.ArgumentParser(description=desc_str)

    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("-r", "--resolution", dest="img_res", type=float, default=None, metavar="IMG_RES", help="Output raster resolution, in unit of the given projected spatial reference system, see the options --out_srs and -t/--template.")
    g.add_argument("-t", "--template", dest="t_raster", default=None, metavar="TEMPLATE_RASTER", help="A template raster file upon which the rasterization is based. The output raster will have the same resolution as the template and pixels are aligned with the template raster.")
    
    p.add_argument("--out_srs", dest="out_srs", default=None, required=False, metavar="OUT_SRS_DEF", help="A PROJECTED (NOT geographic such as WGS84) spatial reference system for the gridded output. OUT_SRS_DEF can be a full WKT definition (hard to escape properly), or a well known definition (i.e. EPSG:42101) or a file with a WKT definition. If a template raster is given, the spatial reference system of the template raster will be used and this option is ignored.")

    p.add_argument("--shot_diameter", dest="shot_diameter", default=20, required=False, metavar="LASER_SHOT_DIAMETER_ON_GROUND", help="Diameter of LVIS laser shots on the groud, in unit of the chosen projected spatial reference system. Default: 20.")
    p.add_argument("--column_type", dest="col_types", default=None, required=False, metavar="LVIS_COLTYPES", help="A single-line file that lists types of each column of the input LVIS L2 ASCII file, delimited by \",\", data types can be simply Real/Integer/String. See https://giswiki.hsr.ch/GeoCSV#CSVT_file_format_specification for more details. Default: every column as Real.")
    p.add_argument("--column2grid", dest="col2grid", nargs="+", default=None, required=True, metavar="COLUMNS_TO_BE_GRIDDED", help="Which columns' values are to be gridded and output to the SQLite file.")
    
    p.add_argument("lvis_l2txt", default=None, metavar="LVIS_L2_TXT", help="LVIS L2 in ASCII format. See https://nsidc.org/data/ABLVIS2.")
    p.add_argument("lvis_l2grd", default=None, metavar="GRIDDED_LVIS_L2", help="Output gridded LVIS L2 as point vectors in SQLite format with each point being the center of a grid cell.")

    p.add_argument("--dir_intermediate", dest="dir_inter", default=None, required=False, metavar="DIR_FOR_INTERMEDIATES", help="Directory to store intermediate files that are produced by the gridding process. Default: the directory of the output SQLite file.")
    p.add_argument("--keep_intermediate", dest="keep_inter", action="store_true", help="If set, keep intermediate files that are produced by the gridding process. Default, delete intermediate files.")

    cmdargs = p.parse_args()
    if cmdargs.img_res is not None and cmdargs.out_srs is None:
        raise RuntimeError("When designating grid resolution rather than using template raster, you must provide the option --out_srs.")
    return cmdargs

def main(cmdargs):
    cmd_dir = os.path.dirname(sys.argv[0])
    
    img_res = cmdargs.img_res
    t_raster = cmdargs.t_raster
    out_srs = cmdargs.out_srs
    shot_diameter = cmdargs.shot_diameter
    col_types = cmdargs.col_types
    col2grid = cmdargs.col2grid
    lvis_l2txt = cmdargs.lvis_l2txt
    lvis_l2grd = cmdargs.lvis_l2grd
    dir_inter = cmdargs.dir_inter
    keep_inter = cmdargs.keep_inter

    if t_raster is not None:
        t_ds = gdal.Open(t_raster, gdalconst.GA_ReadOnly)
        t_gt = t_ds.GetGeoTransform()
        img_res = np.fabs(t_gt[1])
        if out_srs is not None:
            warnings.warn("The option --out_srs will be ignored because the template raster is given and its spatial reference system will be used.")
        out_srs = t_ds.GetProjectionRef()
        t_ds = None

    lvis_name = os.path.basename(lvis_l2txt)
    lvis_name = ".".join(lvis_name.split(".")[0:-1])
    if dir_inter is None:
        dir_inter = os.path.dirname(lvis_l2grd)

    inter_files = {}
    # Convert LVIS L2 ASCII to point shapefile in its native geographic coordinate system WGS84.
    lvis_l2_point = os.path.join(dir_inter, "{0:s}_points.shp".format(lvis_name))
    cmd = ['bash', os.path.join(cmd_dir, 'vectorize_lvis_l2.sh'), 
            lvis_l2txt, lvis_l2_point]
    if col_types is not None:
        cmd += [col_types]
    print("\n"+" ".join(cmd)+"\n")
    subprocess.run(cmd)
    inter_files[lvis_l2_point] = "vector"

    # Reproject point shapefile to a projected spaital reference system.
    lvis_l2_point_prj = os.path.join(dir_inter, "{0:s}_points_proj.shp".format(lvis_name))
    tmp_dir = tempfile.mkdtemp(dir=dir_inter)
    tmp_shp = os.path.join(tmp_dir, "tmp.shp")
    cmd = ['ogr2ogr', '-overwrite', '-f', 'ESRI Shapefile', '-t_srs', out_srs, tmp_shp, lvis_l2_point]
    subprocess.run(cmd)
    sql_str="SELECT *, ST_X(geometry) as geasting, ST_Y(geometry) as gnorthing FROM tmp"
    cmd = ['ogr2ogr', '-overwrite', '-f', 'ESRI Shapefile', '-dialect', 'SQLite', '-sql', sql_str, lvis_l2_point_prj, tmp_shp]
    print("\n"+" ".join(cmd)+"\n")
    subprocess.run(cmd)
    shutil.rmtree(tmp_dir)
    inter_files[lvis_l2_point_prj] = "vector"

    # Create a polygon vector to describe laser shots as circles.
    lvis_l2_shot_circle = os.path.join(dir_inter, "{0:s}_shot_circles.shp".format(lvis_name))
    sql_str="SELECT ST_Buffer(geometry, {0:f}), * FROM {1:s}".format(shot_diameter*0.5, "{0:s}_points_proj".format(lvis_name))
    cmd = ['ogr2ogr', '-overwrite', '-sql', sql_str, '-dialect', 'SQLITE', lvis_l2_shot_circle, lvis_l2_point_prj]
    print("\n"+" ".join(cmd)+"\n")
    subprocess.run(cmd)
    inter_files[lvis_l2_shot_circle] = "vector"

    # Rasterize shot circles to identify grid cells covered by laser shots.
    lvis_l2_shot_cover_tif = os.path.join(dir_inter, "{0:s}_shot_cover.tif".format(lvis_name))
    cmd = ['python', os.path.join(cmd_dir, 'rasterize_vector.py'), 
            '--at', '--burn', '1', 
            '-l', "{0:s}_shot_circles".format(lvis_name), '-f', 'GTiff', 
            '--ot', 'Byte', '--init', '0', '--nodata', '0']
    if t_raster is not None:
        cmd += ['-t', t_raster]
    elif img_res is not None:
        cmd += ['-r', str(img_res)]
    cmd += [lvis_l2_shot_circle, lvis_l2_shot_cover_tif]
    print("\n"+" ".join(cmd)+"\n")
    subprocess.run(cmd)
    inter_files[lvis_l2_shot_cover_tif] = "raster"
   
    # Create a polygon vector of grid cells covered by laser shots
    lvis_l2_shot_cover_shp = os.path.join(dir_inter, "{0:s}_shot_cover.shp".format(lvis_name))
    cmd = ['bash', os.path.join(cmd_dir, 'raster_to_polygon_grids.sh'), 
            lvis_l2_shot_cover_tif, lvis_l2_shot_cover_shp]
    print("\n"+" ".join(cmd)+"\n")
    subprocess.run(cmd)
    inter_files[lvis_l2_shot_cover_shp] = "vector"

    # Intersect shot circles with grid cells, that is, cut shot circles into
    # segments using grid cells.
    lvis_l2_shot_seg = os.path.join(dir_inter, "{0:s}_shot_segments.sqlite".format(lvis_name))
    cmd = ['bash', os.path.join(cmd_dir, 'grids_cut_shots.sh'), 
            lvis_l2_shot_cover_shp, lvis_l2_shot_circle, lvis_l2_shot_seg]
    print("\n"+" ".join(cmd)+"\n")
    subprocess.run(cmd)
    inter_files[lvis_l2_shot_seg] = "vector"

    # Aggregate/group shot segments to produce point vector of grids, with each
    # point being a grid cell.
    cmd = ['bash', os.path.join(cmd_dir, 'shot_seg_to_point_grids.sh'), 
            lvis_l2_shot_seg, lvis_l2grd, 
            str(img_res)]
    cmd += col2grid
    print("\n"+" ".join(cmd)+"\n")
    subprocess.run(cmd)

    if not keep_inter:
        for fname, ftype in inter_files.items():
            if ftype == "vector":
                cmd = ['fio', 'rm', '--yes', fname]
                subprocess.run(cmd)
            elif ftype == "raster":
                cmd = ['gdalmanage', 'delete', fname]
                subprocess.run(cmd)
            elif ftype == "regular":
                os.path.remove(fname)

if __name__ == "__main__":
    cmdargs = getCmdArgs()
    main(cmdargs)
