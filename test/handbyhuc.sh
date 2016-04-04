#!/bin/bash
#PBS -N huc12hand
#PBS -e /gpfs_scratch/nfie/huc12/stderr
#PBS -o /gpfs_scratch/nfie/huc12/stdout
#PBS -l nodes=10:ppn=20,walltime=32:00:00
#PBS -M yanliu@ncsa.illinois.edu
#PBS -m be

## handbyhuc.sh: create Height Above Nearest Drainage raster by HUC code.
## Author: Yan Y. Liu <yanliu.illinois.edu>
## This is a script to demonstrate all the steps needed to create HAND.

# env setup
module purge
module load mpich gdal2-stack GCC/5.1.0-binutils-2.25
exe=`readlink -f $0`
sdir=`dirname $exe` 
source $sdir/handbyhuc.env

# config
hucid="$1"
[ -z "$hucid" ] && hucid='12090205'
huclen=${#hucid}
n="$2" # name of outputs
[ -z "$n" ] && n='travis'
np="$3"
[ -z "$np" ] && np=20
wdir=/gpfs_scratch/nfie/${n}
cdir=`pwd`
mkdir -p $wdir
cd $wdir

echo "=1=: create watershed boundary shp from WBD"
echo -e "\tThis step queries WBD to get the boundary shp of study watershed."
echo "=1CMD=: ogr2ogr ${n}-wbd.shp $dswbd WBDHU${huclen} -where \"HUC${huclen}='12090205'\""
Tstart
[ ! -f "${n}-wbd.shp" ] && \
ogr2ogr ${n}-wbd.shp $dswbd WBDHU${huclen} -where "HUC${huclen}='${hucid}'" \
&& [ $? -ne 0 ] && echo "ERROR creating watershed boundary shp." && exit 1
Tcount wbd


echo "=2=: create DEM from NED 10m"
echo -e "\tThis step clips the DEM of the study watershed from the NED 10m VRT."
echo -e "\tThe output is hucid.tif of the original projection (geo)."
echo "=2CMD= gdalwarp -cutline ${n}-wbd.shp -cl ${n}-wbd -crop_to_cutline -of "GTiff" -overwrite -co "COMPRESS=LZW" -co "BIGTIFF=YES" $dsdem ${n}.tif "

Tstart
[ ! -f "${n}.tif" ] && \
gdalwarp -cutline ${n}-wbd.shp -cl ${n}-wbd -crop_to_cutline -of "GTiff" -overwrite -co "COMPRESS=LZW" -co "BIGTIFF=YES" $dsdem ${n}.tif \
&& [ $? -ne 0 ] && echo "ERROR clipping study area DEM." && exit 1
Tcount dem

echo "=3=: create flowline shp from NHDPlus"
echo "=3CMD= ogr2ogr ${n}-flows.shp $dsnhdplus Flowline -where \"REACHCODE like '${hucid}%'\""
Tstart
[ ! -f "${n}-flows.shp" ] && \
ogr2ogr ${n}-flows.shp $dsnhdplus Flowline -where "REACHCODE like '${hucid}%'" \
&& [ $? -ne 0 ] && echo "ERROR creating flowline shp." && exit 1
Tcount flowline

echo "=4=: find inlets from flowline shp"
#find_inlets=$sdir/../src/find_inlets/build/find_inlets 
find_inlets=/projects/nfie/hand/inlet-finder/build/find_inlets
echo "=4CMD= $find_inlets -flow ${n}-flows.shp -dangle ${n}-inlets0.shp "
Tstart
[ ! -f "${n}-inlets0.shp" ] && \
$find_inlets -flow ${n}-flows.shp -dangle ${n}-inlets0.shp \
&& [ $? -ne 0 ] && echo "ERROR creating inlet shp." && exit 1
Tcount dangle

echo "=5=: rasterize inlet points"
Tstart
[ ! -f "${n}-weights.tif" ] && \
ogr2ogr -t_srs $dsepsg ${n}-inlets.shp ${n}-inlets0.shp && \
read fsizeDEM colsDEM rowsDEM nodataDEM minDEM maxDEM meanDEM sdDEM xmin ymin xmax ymax cellsize_resx cellsize_resy<<<$(python $sdir/getRasterInfo.py ${n}.tif) && \
echo "=5CMD= gdal_rasterize  -ot Int16 -of GTiff -burn 1 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax ${n}-inlets.shp ${n}-weights.tif" && \
gdal_rasterize  -ot Int16 -of GTiff -burn 1 -tr $cellsize_resx $cellsize_resy -te $xmin $ymin $xmax $ymax ${n}-inlets.shp ${n}-weights.tif \
&& [ $? -ne 0 ] && echo "ERROR rasterizing inlet shp to weight grid." && exit 1
Tcount weights

cd $cdir