#!/bin/sh

# Synology synoindexd service only works with FTP, SMB, AFP
# this program index all files that synoindexd left
# you can select extensions, modified time, user and paths
# for the searching and treatment
#
# Usage: update-synoindex.sh  --> first for create config file
#        change values of config/update-synoindex-conf.txt
#        update-synoindex.sh
#
# ---------------------------------------------------------------------
# Copyright (C) 2015-01-16  CPVprogrammer
#                           https://github.com/CPVprogrammer
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>
#
# v1.00 first release
# v1.01 corrected an issue with path when parents path not found in DB
# v1.02 corrected a bug with path and filenames and added a log file
# v1.03 corrected a bug with postgresql roles in query


#---------------------------------------------
#function to set the environment
#---------------------------------------------
set_environment(){
    ALL_EXT="ASF AVI DIVX FLV IMG ISO M1V M2P M2T M2TS M2V M4V MKV MOV MP4 MPEG4 MPE MPG MPG4 MTS QT RM TP TRP TS VOB WMV XVID"

    CONFIG_DIR=$(dirname $0)"/config"
    
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir "$CONFIG_DIR"
    fi

	SCRIPT_NAME=${0##*/}
	SCRIPT_NAME=${SCRIPT_NAME%.*}
	CONFIG_FILE=$SCRIPT_NAME"-conf.txt"

	FICH_CONF="$CONFIG_DIR/$CONFIG_FILE"

    if [[ ! -f "$FICH_CONF" ]]; then
        #insert into file default values
        echo "#extensions
$ALL_EXT
#Modified time --> none or \"command find time\" --> 24 hours example = \"-mtime 0\" ----> 1 hour = \"-mmin -60\"
none
#user: none, root, transmission, ftp, etc.
none
#directory for log/filename --> none or path or path/filename
none
#directories to treat --> 0 recursive, 1 no recursive
1 /volume1
1 /volume1
1 /volume1" > "$FICH_CONF"
        exit
    fi

    #flag for read extensions, time for find and user for find from file FICH_CONF
    READ_EXT=0
    READ_TIME=0
    READ_USER=0
	READ_LOG=0
}


#---------------------------------------------
#function to log the execution of the script
#---------------------------------------------
log_this(){
	if [ "$LOG_FILE" == "none" ]; then
		echo $*
	else
		echo $* | tee -a $LOG_FILE
	fi
}


#---------------------------------------------
#function to extract the extension of a path
#---------------------------------------------
extension(){
    FICH_EXT=${FICH_MEDIA##*.}
    
    #convert to uppercase the extension
    FICH_EXT=$(echo $FICH_EXT | tr 'a-z' 'A-Z')
}


#---------------------------------------------
#function to check it is a treatable extension
#---------------------------------------------
check_extension(){
    if echo "$ALL_EXT" | grep -q "$FICH_EXT"; then
        TREATABLE=1
    else
        TREATABLE=0
    fi
    
    return "$TREATABLE"
}


#---------------------------------------------
#function to check if directory is in the DB
#---------------------------------------------
search_directory_DB(){
    PATH_MEDIA=${FICH_MEDIA%/*}
    PATH_MEDIA_DB=$(echo $PATH_MEDIA | tr 'A-Z' 'a-z')
    
    #replace "'" with "\'"
    PATH_MEDIA_SQL=${PATH_MEDIA_DB//"'"/"\'"}
	TOTAL=0
	FIRST=1
	CREATE_DIR=0
	
	while : ; do
		TOTAL=`/usr/syno/pgsql/bin/psql mediaserver postgres -tA -c "select count(1) from directory where lower(path) like '%$PATH_MEDIA_SQL%'"`

		if [ "$TOTAL" = 0 ]; then
			if [ "$FIRST" = 1 ]; then
				FIRST=0
			else
				PATH_MEDIA_DB=${PATH_MEDIA_DB%/*}
			fi
			CREATE_DIR=1
		fi

		PATH_MEDIA_SQL=${PATH_MEDIA_SQL%/*}
		if [ -z $PATH_MEDIA_SQL ]; then
			break
		fi		
	done

    return "$CREATE_DIR"
}


#---------------------------------------------
#function to check if file is in the DB
#---------------------------------------------
search_file_DB(){
    FICH_MEDIA_DB=$(echo $FICH_MEDIA | tr 'A-Z' 'a-z')

    #replace "'" with "\'"
    FICH_MEDIA_SQL=${FICH_MEDIA_DB//"'"/"\'"}

    TOTAL=`/usr/syno/pgsql/bin/psql mediaserver postgres -tA -c "select count(1) from video where lower(path) like '%$FICH_MEDIA_SQL%'"`

    return "$TOTAL"
}


#---------------------------------------------
#function to add directory to DB
#---------------------------------------------
add_directory_DB(){
    synoindex -A "$PATH_MEDIA"
	log_this "added directory: $PATH_MEDIA to DB"
}


#---------------------------------------------
#function to add file to DB
#---------------------------------------------
add_file_DB(){
    synoindex -a "$FICH_MEDIA"
	log_this "added file: $FICH_MEDIA to DB"
}


#---------------------------------------------
#function to treat directories
#---------------------------------------------
treat_directories(){
	CREATE_FILE=1
	
    search_directory_DB
	SEARCH_RETVAL=$?
    
    if [ "$SEARCH_RETVAL" == 1 ]; then
        add_directory_DB
		CREATE_FILE=0
    fi
	
	return $CREATE_FILE
}


#---------------------------------------------
#function to treat files
#---------------------------------------------
treat_files(){
    extension
    check_extension
    
    EXT_RETVAL=$?
    if [ "$EXT_RETVAL" == 1 ]; then
        search_file_DB
        SEARCH_RETVAL=$?
        
        if [ "$SEARCH_RETVAL" == 0 ]; then
            treat_directories
			
			EXT_RETVAL=$?

			if [ "$EXT_RETVAL" == 1 ]; then
				add_file_DB
			fi
        fi
    fi
}


#---------------------------------------------
#function for the main program
#---------------------------------------------
treatment(){
    #read file FICH_CONF
    while read LINE || [ -n "$LINE" ]; do

        #skip comment and blank lines
        case "$LINE" in \#*) continue ;; esac
        [ -z "$LINE" ] && continue
        
        #read the extensions from file
        if [[ "$READ_EXT" -eq 0 ]]; then
            
            ALL_EXT=$LINE
            
            #convert to uppercase
            ALL_EXT=$(echo $ALL_EXT | tr 'a-z' 'A-Z')
            
            READ_EXT=1
            continue
        fi

        #read the update time from file
        if [[ "$READ_TIME" -eq 0 ]]; then
            LINE=$(echo $LINE | tr 'A-Z' 'a-z')
            
            if [ "$LINE" == "none" ]; then
                TIME_UPD=""
            else
                TIME_UPD="$LINE"
            fi
            
            READ_TIME=1
            continue
        fi

        #read the user from file
        if [[ "$READ_USER" -eq 0 ]]; then
            LINE=$(echo $LINE | tr 'A-Z' 'a-z')
            
            if [ "$LINE" == "none" ]; then
                USER_OWN=""
            else
                USER_OWN="-user $LINE"
            fi
            
            READ_USER=1
            continue
        fi

        #read the log path file
        if [[ "$READ_LOG" -eq 0 ]]; then
            LINE=$(echo $LINE | tr 'A-Z' 'a-z')

            if [ "$LINE" == "none" ]; then
                LOG_FILE="none"

            else
				#delete last / if exist
				#LOG_FILE="${LOG_FILE%/}"
				
				#get directory name
				DIRECTORY="${LINE%/*}"
				
				if [ -d "$DIRECTORY" ]; then

					if [ "${LINE%/}" == "$DIRECTORY" ]; then
						LOG_FILE="${LINE%/}/$SCRIPT_NAME.log"

						if [ ! -f "$LOG_FILE" ]; then
							> $LOG_FILE
							echo "This is the logfile for the script: $SCRIPT_NAME" > $LOG_FILE
						fi

					else
						LOG_FILE=$LINE
						
						if [ ! -f "$LINE" ]; then
							> $LOG_FILE
							echo "This is the logfile for the script: $SCRIPT_NAME" > $LOG_FILE						
						fi
					fi
					
				fi
			fi

			log_this "program executed at: " `date +"%Y-%m-%d %H:%M:%S`

            READ_LOG=1
            continue
        fi

        #read the paths from file
        RECURSIVE=$(echo $LINE | awk -F" " '{print $1}')
        PATH_FILE=$(echo $LINE | awk -F" " '{print $2}')
        
        #delete last / if exist
        PATH_FILE="${PATH_FILE%/}"

        if [[ "$RECURSIVE" -eq 0 ]]; then
            #recursive find
            RECURSIVE=""
        else
            #no recursive find
            RECURSIVE="-maxdepth $RECURSIVE"
        fi
        
        PARAMETERS="$PATH_FILE $RECURSIVE $TIME_UPD -type f $USER_OWN"

        find $PARAMETERS |
        while read FICH_MEDIA
        do
            treat_files
        done

    done < $FICH_CONF
}


#---------------------------------------------
#main
#---------------------------------------------
set_environment
treatment
