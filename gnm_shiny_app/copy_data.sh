#!/bin/bash
#
# copy data files to app directory to include in bundle that will be send to shiny server
#
cp ../output/ChroniclItaly_stats_per_doc.csv "www/place_names.csv"
cp ../data/output_20191622_041444_geocoding_edit.csv "www/geo_data.csv"
