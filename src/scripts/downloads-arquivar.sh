#!/bin/sh 
set -e         
DOWNLOAD_DIR=~/Downloads
NOW=$(date +%Y%m%d%Hh%Mm%Ss)
ARQUIVE_DIR=$DOWNLOAD_DIR/arquivado
LOG_FILE=$ARQUIVE_DIR/log.txt
mkdir -p $ARQUIVE_DIR
cd $ARQUIVE_DIR
mkdir -p zip-tar
mkdir -p docs-pdfs-ppts
mkdir -p xml-logs-txt
mkdir -p imgs
mkdir -p exes
mkdir -p emails
mkdir -p mp3
mkdir -p sqls
mkdir -p jars
mkdir -p codigo
mkdir -p videos
echo $NOW >> $LOG_FILE
#ZIP
mv -v $DOWNLOAD_DIR/*.zip  zip-tar | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.tar  zip-tar | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.rar  zip-tar | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.gz  zip-tar | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.bz2  zip-tar | tee -a $LOG_FILE
#LOGS
mv -v $DOWNLOAD_DIR/*.txt  xml-logs-txt | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.log  xml-logs-txt | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.xml  xml-logs-txt | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.yaml  xml-logs-txt | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.html  xml-logs-txt | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.gpx  xml-logs-txt | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.kmz  xml-logs-txt | tee -a $LOG_FILE
#IMGS
mv -v $DOWNLOAD_DIR/*.png  imgs | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.jpg  imgs | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.jpeg  imgs | tee -a $LOG_FILE
#EXE
mv -v $DOWNLOAD_DIR/*.exe  exes | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.EXE  exes | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.msi  exes | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.MSI  exes | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.dmg  exes | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.ovpn  exes | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.tgz  exes | tee -a $LOG_FILE
#EMAILS
mv -v $DOWNLOAD_DIR/*.msg  emails | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.eml  emails | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.EML  emails | tee -a $LOG_FILE
#SQL
mv -v $DOWNLOAD_DIR/*.sql  sqls | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.3gp  videos | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.mp4  videos | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.mp3  mp3 | tee -a $LOG_FILE
#JARS
mv -v $DOWNLOAD_DIR/*.jar  codigo | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.js  codigo | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.ts  codigo | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.jnlp  codigo | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.jspa  codigo | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.py  codigo | tee -a $LOG_FILE
#DOCS
#mv -v $DOWNLOAD_DIR/*.doc  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.docx  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.doc  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.pdf  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.PDF  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.pptx  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.xlsx  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.xsd  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.chm  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.xls  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.csv  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.json  docs-pdfs-ppts | tee -a $LOG_FILE
mv -v $DOWNLOAD_DIR/*.md  docs-pdfs-ppts | tee -a $LOG_FILE
#Remove empty dirs
find . -type d -empty -exec rmdir {} \;

ls $DOWNLOAD_DIR