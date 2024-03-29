#!/bin/bash

# Backup solution based on https://kevq.uk/how-to-backup-nextcloud/
# Argument passing based on https://www.redhat.com/sysadmin/arguments-options-bash-scripts

CurrentDateTime=$(date +"%Y-%m-%d_%H-%M-%S")
DataSourceDir=""
BackupParentDir=""
LogsDir=""
RemoveBackupsOlderThan="14"

IsVerbose=false
KeepBackups=false

PrintUsage()
{
    echo ""
    echo "Flags:"
    echo "  -h  shows this help message"
    echo "  -v  enables verbose mode"
    echo "  -k  indicates to compress and copy current backups before overwriting them"
    echo ""
    echo "Parameters:"
    echo "  -s  <file path> specifies nextcloud data source directory"
    echo "  -d  <file path> specifies destination directory for backup"
    echo "  -r  <days>      remove old backups & exports older than a specified number of days (default is 14, -1 to skip removal)"
    echo ""
}

RunBackup()
{
    SECONDS=0
    dataDir="${BackupParentDir}data/"
    databaseDir="${BackupParentDir}database/"
    oldBackupsDir="${BackupParentDir}old/"
    metadataFile="${BackupParentDir}backup_metadata"

    # Creating directories if needed
    if [ ! -d "$dataDir" ]; then
        mkdir "$dataDir"
    fi
    if [ ! -d "$databaseDir" ]; then
        mkdir "$databaseDir"
    fi
    if [ ! -d "$oldBackupsDir" ]; then
        mkdir "$oldBackupsDir"
    fi

    echo ""
    echo "Starting nextcloud backup..."

    if [ "$KeepBackups" = true ]; then
        # Compressing old backup, if data exists
        echo ""
        echo "--Compressing old backup...--"
        if [ -z "$(ls -A $dataDir)" ]; then
            echo "--Skipping compression of old backup because $dataDir is empty--";
        else
            start="$SECONDS"
            oldDate=$(grep -oP  "(?<=^date: ).*$" "$metadataFile")
            #echo "$oldDate"
            tar -zcf "${oldBackupsDir}${oldDate}.tar.gz" "$dataDir" "${databaseDir}db_export_${oldDate}.tar.gz" "${LogsDir}${oldDate}.log"

            duration=$((SECONDS - start))
            echo "--Old backup compressed and moved to $oldBackupsDir in $((duration / 60)) minutes and $((duration % 60)) seconds--"
        fi
    fi

    # Creating new metadata file
    echo "date: $CurrentDateTime" > "${BackupParentDir}backup_metadata"

    # Backup data
    echo ""
    echo "--Starting data backup...--"
    start=$SECONDS
    nextcloud.occ maintenance:mode --on
    rsync -Aavx "$DataSourceDir" "$dataDir"
    nextcloud.occ maintenance:mode --off
    duration=$((SECONDS - start))
    echo "--Data backup finished in $((duration / 60)) minutes and $((duration % 60)) seconds--"

    # Export apps, database, config
    echo ""
    echo "--Starting export of apps, database, and config...--"
    start=$SECONDS
    nextcloud.export -abc

    # Compress export
    echo ""
    echo "--Compressing export...--"
    tar -zcf "${databaseDir}db_export_${CurrentDateTime}.tar.gz" /var/snap/nextcloud/common/backups/*
    duration=$((SECONDS - start))
    echo "--Exported compressed apps, database, and config to $databaseDir in $((duration / 60)) minutes and $((duration % 60)) seconds--"

    # Remove uncompressed export
    echo ""
    echo "--Removing uncompressed exports...--"
    start=$SECONDS
    rm -rf /var/snap/nextcloud/common/backups/*
    duration=$((SECONDS - start))
    echo "--Finished removing uncompressed exports in $((duration / 60)) minutes and $((duration % 60)) seconds"

    echo ""
    if [ "$RemoveBackupsOlderThan" -ne "-1" ]; then
        # Remove old backups older than RemoveBackupsOlderThan days
        echo "--Removing backups, logs, & database exports older than $RemoveBackupsOlderThan days...--"
        start=$SECONDS
        eval "find $oldBackupsDir -mtime +$RemoveBackupsOlderThan -type f -delete"
        eval "find $databaseDir -mtime +$RemoveBackupsOlderThan -type f -delete"
        eval "find $LogsDir -mtime +$RemoveBackupsOlderThan -type f -delete"
        duration=$((SECONDS - start))
        echo "--Old backups, logs, & database exports removed in $((duration / 60)) minutes and $((duration % 60)) seconds--"
    else
        echo "--Skipped removing old backups--"
    fi

    duration=$SECONDS
    echo ""
    echo "--Nextcloud backup completed successfully in $((duration / 60)) minutes and $((duration % 60)) seconds--"
}


############################################      Main      ############################################

# Parameter selection
while getopts ":hvks:d:r:" option; do
    case $option in
        h) # Display help
            PrintUsage
            exit 0;;
        v) # Enable verbose mode
            IsVerbose=true;;
        k) # Indicates we should compress & copy old backups before overriding them
            KeepBackups=true;;
        s) # Source directory
            DataSourceDir="$OPTARG";;
        d) # Destination directory
            BackupParentDir="$OPTARG";;
        r) # Days before old backups are deleted
            RemoveBackupsOlderThan="$OPTARG";;
        \?) # Invalid option
            echo ""
            echo "Error: Invalid option."
            echo "Try usingse '-h' for more information."
            echo ""
            exit 1;;
    esac
done

# Check if user is sudo or root
if [ "$(whoami)" != root ]; then
    echo "Nextcloud backup requires you to be root or using sudo."
    exit 1;
fi

# Parameter validation
intRegex='^[+-]?[0-9]+$';
if [[ ! -d "$DataSourceDir" || ! "$DataSourceDir" == */ ]]; then
    echo "Error: Provide a valid source directory. (Be sure to include a slash at the end)"
    exit 1;
elif [[ "$BackupParentDir" = "" || ! "$BackupParentDir" == */ ]]; then
    echo "Error: Provide a valid destination directory. (Be sure to include a slash at the end)"
    exit 1;
elif [[ ! $RemoveBackupsOlderThan =~ $intRegex ]]; then
    echo "Error: Value for -r is not a number"
    exit 1;
fi

LogsDir="${BackupParentDir}logs/"

# Creating necessary directories if needed
if [ ! -d "$BackupParentDir" ]; then
    mkdir "$BackupParentDir"
fi
if [ ! -d "$LogsDir" ]; then
    mkdir "$LogsDir"
fi

# Printing to log file and or stdout
if [ "$IsVerbose" = true ]; then
    RunBackup | tee "${LogsDir}${CurrentDateTime}.log"
else
    RunBackup > "${LogsDir}${CurrentDateTime}.log"
fi
