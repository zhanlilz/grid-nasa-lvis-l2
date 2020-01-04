#!/usr/bin/env python
#
# Rasterize vector files into raster files based on gdal_rasterize but with
# some special treatment/improvements of the rasterization, including, 
# (1) when rasterizing points on regular grids, points will be placed in the
# center of rasterized pixels. 
# (2) when given a template raster, the input vector will be rasterized into a
# grid that is aligned with the given template raster.

# Zhan Li, zhan.li@canada.ca
# Created: Thu Jan  2 14:19:44 PST 2020

import argparse
import subprocess

from osgeo import gdalconst, ogr, gdal_array, gdal, osr

import numpy as np

import affine

def getCmdArgs():
    desc_str = """
Rasterize vector files into raster files based on gdal_rasterize but with
some special treatment/improvements of the rasterization, including, 
(1) when rasterizing points on regular grids, points will be placed in the
center of rasterized pixels. 
(2) when given a template raster, the input vector will be rasterized into a
grid that is aligned with the given template raster.
    """
    p = argparse.ArgumentParser(description=desc_str)

    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("-r", "--resolution", dest="img_res", type=float, default=None, metavar="IMG_RES", help="Output raster resolution, in unit of input vector file")
    g.add_argument("-t", "--template", dest="t_raster", default=None, metavar="TEMPLATE_RASTER", help="A template raster file upon which the rasterization is based. The output raster will have the same resolution as the template and pixels are aligned with the template raster.")

    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("-a", "--attribute", dest="attr_name", default=None, metavar="ATTR_NAME", help="Identifies an attribute field on the features to be used for a burn-in value.")
    g.add_argument("-b", "--burn", dest="burn_val", type=float, default=None, metavar="BURN_VALUE", help="A fixed value to burn into a band for all objects.")

    p.add_argument("-f", "--format", dest="out_format", default="GTiff", required=False, metavar="RASTER_FORMAT", help="Output raster format. Possible format names can be found from GDAL website at https://gdal.org/drivers/raster/index.html. Default: GTiff.")
    p.add_argument("-l", "--layer", dest="layer_name", default=None, required=False, metavar="LAYER_NAME", help="Name of the layer in the input vector file to be rasterized. Default: the first layer of the input vector file will be rasterized.")
    p.add_argument("--nodata", dest="ndv", type=float, default=None, required=False, metavar="NODATA_VALUE", help="Assign a specified nodata value to output bands. Default: output date type specific. ")
    p.add_argument("--init", dest="initv", type=float, default=0, required=False, metavar="INIT_VALUE", help="Pre-initialize the output raster with these values. However, it is not marked as the nodata value in the output file. Default: 0.")
    p.add_argument("--ot", dest="out_type", default="Float64", required=False, metavar="OUTPUT_TYPE", help="Force the output bands to be of the indicated data type. Choices: Byte/Int16/UInt16/UInt32/Int32/Float32/Float64/CInt16/CInt32/CFloat32/CFloat64. Default: Float64.")
    p.add_argument("--at", dest="all_touch", action="store_true", help="Enables the ALL_TOUCHED rasterization option so that all pixels touched by lines or polygons will be updated, not just those on the line render path, or whose center point is within the polygon. Defaults to disabled for normal rendering rules.")

    p.add_argument("in_vector", default=None, metavar="INPUT_VECTOR_FILE", help="Input vector file from which a layer will be rasterized.")
    p.add_argument("out_raster", default=None, metavar="OUTPUT_RASTER_FILE", help="Output raster file.")

    cmdargs = p.parse_args()
    return cmdargs

def main(cmdargs):
    img_res = cmdargs.img_res
    t_raster = cmdargs.t_raster
    attr_name = cmdargs.attr_name
    burn_val = cmdargs.burn_val
    out_format = cmdargs.out_format
    layer_name = cmdargs.layer_name
    ndv = cmdargs.ndv
    initv = cmdargs.initv
    out_type = cmdargs.out_type
    all_touch = cmdargs.all_touch
    in_vector = cmdargs.in_vector
    out_raster  = cmdargs.out_raster

    options = []

    in_ds = ogr.Open(in_vector, gdalconst.GA_ReadOnly)
    if layer_name is None:
        in_layer = in_ds.GetLayer(0)
        layer_name = in_layer.GetName()
    else:
        in_layer = in_ds.GetLayerByName(layer_name)
    options += ['-l', layer_name]
    if ndv is not None:
        options += ['-a_nodata', str(ndv)]
    if initv is not None:
        options += ['-init', str(initv)]
    options += ['-ot', out_type]
    if attr_name is not None:
        options += ['-a', attr_name]
    elif burn_val is not None:
        options += ['-burn', str(burn_val)]

    if all_touch:
        options += ['-at']

    # Get the extent of the input layer of the input vector file.
    in_extent = in_layer.GetExtent(force=True)
    in_geomtype = in_layer.GetGeomType()
    if img_res is not None:
        options += ['-tr', str(img_res), str(img_res)]
        if in_geomtype == ogr.wkbPoint or \
           in_geomtype == ogr.wkbPoint25D or \
           in_geomtype == ogr.wkbPointM or \
           in_geomtype == ogr.wkbPointZM or \
           in_geomtype == ogr.wkbMultiPoint or \
           in_geomtype == ogr.wkbMultiPoint25D or \
           in_geomtype == ogr.wkbMultiPointM or \
           in_geomtype == ogr.wkbMultiPointZM:
            options += ['-te', 
                        str(in_extent[0]-0.5*img_res), 
                        str(in_extent[2]-0.5*img_res), 
                        str(in_extent[1]+0.5*img_res), 
                        str(in_extent[3]+0.5*img_res)]
    elif t_raster is not None:
        t_ds = gdal.Open(t_raster, gdalconst.GA_ReadOnly)
        t_gt = t_ds.GetGeoTransform()
        fwd_img2geo = affine.Affine.from_gdal(*t_gt)
        inv_geo2img = ~fwd_img2geo

        vector_srs = in_layer.GetSpatialRef()
        raster_srs = osr.SpatialReference()
        raster_srs.ImportFromWkt(t_ds.GetProjectionRef())
        coord_trans_v2r = osr.CoordinateTransformation(vector_srs, raster_srs)
        ll_geo= coord_trans_v2r.TransformPoint(in_extent[0], in_extent[2])[0:2]
        ur_geo = coord_trans_v2r.TransformPoint(in_extent[1], in_extent[3])[0:2]
        ll_img = inv_geo2img * ll_geo
        ur_img = inv_geo2img * ur_geo
        ll_img = (np.floor(ll_img[0]), np.ceil(ll_img[1]))
        ur_img = (np.ceil(ur_img[0]), np.floor(ur_img[1]))
        ll_geo = fwd_img2geo * ll_img
        ur_geo = fwd_img2geo * ur_img

        options += ['-te', 
                    str(ll_geo[0]), str(ll_geo[1]), 
                    str(ur_geo[0]), str(ur_geo[1])]
        options += ['-tr', str(np.fabs(t_gt[1])), str(np.fabs(t_gt[5]))]

    cmd = ['gdal_rasterize'] + options + [in_vector, out_raster]
    print(" ".join(cmd))
    subprocess.run(cmd)

if __name__ == "__main__":
    cmdargs = getCmdArgs()
    main(cmdargs)
