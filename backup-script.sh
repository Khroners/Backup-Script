#!/bin/bash



# Variables
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date "+%Y.%m.%d-%H.%M.%S")
WORKFOLDER="/apps/backups"
BACKUPFOLDER="backup-$DATE"
KDRIVE="yes" # Do you want send backups to kDrive ?
SWISS_BACKUP="yes" # Do you want send backups to Swiss-Backup ?
ZABBIX="yes" # Have you a Zabbix server ? Check Zabbix Config
DISCORD="yes" # Do you want Discord Notifications ? Check Discord Config 
DOCKER="yes" # Have you Docker on this server ?
FOLDERS="/home /apps /var/lib/docker " #Folders to backup (ex : /var/lib/docker /apps)
EXCLUDE_FOLDERS="$WORKFOLDER /home/debian /apps/data /var/lib/docker/image /var/lib/docker/overlay2"
EXCLUDE_EXTENSIONS=".mkv .tmp"
RETENTION_DAYS=30 # Number of days until object is deleted
SEGMENT_SIZE="256M"



# kDrive Config
kd_user="" # Your Infomaniak's mail
kd_pass="" # App's password : https://manager.infomaniak.com/v3/profile/application-password
kd_folder="" # Exemple : "Mickael Asseline/BACKUPS-SERVERS"


# Swiss Backup Config
sb_type="swift"
sb_user=""
sb_key=""
sb_auth="https://swiss-backup02.infomaniak.com/identity/v3"
sb_domain="default"
sb_tenant=""
sb_tenant_domain="default"
sb_region="RegionOne"
sb_storage_url=""
sb_auth_version=""



# Zabbix Config
ZABBIX_SENDER="/usr/bin/zabbix_sender"
ZABBIX_HOST="NURION" # Name of your host
ZABBIX_SRV="" # IP of your Zabbix server or proxy
ZABBIX_DATA="/var/log/backupscript/zabbix/zabbix_$TIMESTAMP.log"


# Discord Config
DISCORD_WEBHOOK=""

# ------------------------------------------------------------------------------------------------------ #


if [[ $1 =~ "--dry-run" ]]; then
    HOUR=$(date +%Y-%m-%d_%H:%M:%S)
    DRY='echo ['$(date +%Y-%m-%d_%H:%M:%S)']---BackupScript---🚧---DRY RUN : [ '
    DRY2=' ]'
    DRY_RUN="yes"
else
    DRY=""
    DRY2=""
    DRY_RUN="no"
fi
FOLDER_TOTAL_SIZE=0
FREE_SPACE_H=$(df -h $WORKFOLDER | awk 'FNR==2{print $4}')
FREE_SPACE=$(df $WORKFOLDER | awk 'FNR==2{print $4}')
DELETE_AFTER=$(( $RETENTION_DAYS * 24 * 60 * 60 ))

# Installation of requirements
function Install-Requirements {
    apt install -y mariadb-client pv curl zabbix-sender
    curl https://rclone.org/install.sh | sudo bash
    "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ✅  All requirements is installed."
    echo ""
    printf '=%.0s' {1..100}
    echo ""
}



# Create rclone config kDrive
function Create-Rclone-Config-kDrive {
    RCLONE_CHECK_KDRIVE=$(rclone config show | grep kDrive)
    if [ -n "$RCLONE_CHECK_KDRIVE" ]; then
        echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🌀   kDrive config already exist."
    else
        echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🌀   Create kDrive config for rclone."
        $DRY rclone config create kDrive webdav url "https://connect.drive.infomaniak.com/$kd_folder" vendor other user "$kd_user" $DRY2    
        $DRY rclone config  password kDrive pass "$kd_pass" $DRY2
        if [[ $DRY_RUN == "yes" ]]; then
            $DRY Create Rclone config for kDrive $DRY2
        else
            RCLONE_CHECK_KDRIVE=$(rclone config show | grep kDrive)
            if [ -n "$RCLONE_CHECK_KDRIVE" ]; then
                echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ✅   kDrive config created for rclone."
            else
                echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ❌   ERROR : kDrive config didn't created, please check that !"
                exit
            fi
        fi
    fi
    echo ""
    printf '=%.0s' {1..100}
    echo ""
}

# Create rclone config Swiss-Backup
function Create-Rclone-Config-Swiss-Backup {
    RCLONE_CHECK_SWISS_BACKUP=$(rclone config show | grep Swiss-Backup)
    if [ -n "$RCLONE_CHECK_SWISS_BACKUP" ]; then
        echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🌀   Swiss-Backup config already exist."
    else
        echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🌀   Create Swiss-Backup config for rclone."
        $DRY rclone config create Swiss-Backup swift user "$sb_user" key "$sb_key" auth "$sb_auth" domain "$sb_domain" tenant "$sb_tenant" tenant_domain "$sb_tenant_domain" region "$sb_region" $DRY2
        if [[ $DRY_RUN == "yes" ]]; then
            $DRY Create Rclone config for Swiss-Backup $DRY2
        else
            RCLONE_CHECK_SWISS_BACKUP=$(rclone config show | grep Swiss-Backup)
            if [ -n "$RCLONE_CHECK_SWISS_BACKUP" ]; then
                echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ✅   Swiss-Backup config created for rclone."
            else
                echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ❌   ERROR : Swiss-Backup config didn't created, please check that !"
                exit
            fi
        fi
    fi
    echo ""
    printf '=%.0s' {1..100}
    echo ""
}



# Create archives of folders
function Backup-Folders {
    FOLDERS_BACKUP_ERRORS=0
    FOLDERS_COUNT=0
    echo ""
    cd $WORKFOLDER
    $DRY /bin/mkdir $BACKUPFOLDER $DRY2
    if [ -n "$EXCLUDE_FOLDERS" ]; then
        ARG_EXCLUDE_FOLDER=""
        for FOLDEREX in $EXCLUDE_FOLDERS; do
            ARG_EXCLUDE_FOLDER=$(echo $ARG_EXCLUDE_FOLDER "--exclude="$FOLDEREX"" )
        done
    fi

    if [ -n "$EXCLUDE_EXTENSIONS" ]; then
        ARG_EXCLUDE_EXTENSIONS=""
        for EXTENSION in $EXCLUDE_EXTENSIONS; do
            ARG_EXCLUDE_EXTENSIONS=$(echo $ARG_EXCLUDE_EXTENSIONS "--exclude="*$EXTENSION"" )
        done
    fi

    for FOLDER in $FOLDERS; do
        echo ""

        echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🌀   Calculate the size of folder $FOLDER, please wait ..."
        FOLDER_SIZE_H=$(du -hs $FOLDER $ARG_EXCLUDE_FOLDER $ARG_EXCLUDE_EXTENSIONS | awk '{print $1}')
        FOLDER_SIZE=$(du -s $FOLDER $ARG_EXCLUDE_FOLDER $ARG_EXCLUDE_EXTENSIONS | awk '{print $1}')
        FOLDER_TOTAL_SIZE=$(echo "$FOLDER_TOTAL_SIZE + $FOLDER_SIZE" | bc)
        FOLDER_NAME=$(basename $FOLDER)
        echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🌀   Backup of $FOLDER ($FOLDER_SIZE_H) started."
        if [[ $DRY_RUN == "yes" ]]; then
                $DRY "Backup $FOLDER (with $ARG_EXCLUDE_FOLDER and $ARG_EXCLUDE_FOLDER) to $BACKUPFOLDER/$FOLDER_NAME-$DATE.tar.gz" $DRY2
            else
                /bin/tar -c $ARG_EXCLUDE_FOLDER $ARG_EXCLUDE_EXTENSIONS ${FOLDER} -P | pv -s $(du -sb ${FOLDER} | awk '{print $1}') | gzip > $BACKUPFOLDER/$FOLDER_NAME-$DATE.tar.gz
                status=$?
                if test $status -eq 0; then
                    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ✅   Backup of $FOLDER completed."
                    ((FOLDERS_COUNT++))
                else
                    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ❌   ERROR : A problem was encountered during the backup of $FOLDER."
                    ((FOLDERS_BACKUP_ERRORS++))
                fi
                FOLDER_SIZE_AFTER_H=$(du -hs $BACKUPFOLDER/$FOLDER_NAME-$DATE.tar.gz | awk '{print $1}')
                echo "                                            🔹 [ $FOLDER_NAME ] - $FOLDER : $FOLDER_SIZE_H ($FOLDER_SIZE_AFTER_H)" >> folders.txt
            fi
        
        FOLDER_LIST=$(echo "$FOLDER_LIST $FOLDER")
    done
    echo ""
    printf '=%.0s' {1..100}
    echo ""
}



# Create dump of databases Dockers
function Backup-Database {
    DB_BACKUP_ERRORS=0
    DB_COUNT=0
    echo ""
    cd $WORKFOLDER
    $DRY /bin/mkdir -p $BACKUPFOLDER/databases $DRY2
    CONTAINER_DB=$(docker ps | grep -E 'mariadb|mysql|postgres|-db' | awk '{print $NF}')
    for CONTAINER_NAME in $CONTAINER_DB; do
        echo ""
        echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🌀   Backup database of $CONTAINER_NAME started."
        DB_VERSION=$(docker ps | grep -w $CONTAINER_NAME | awk '{print $2}')

        if [[ $DB_VERSION == *"mariadb"* ]] || [[ $DB_VERSION == *"mysql"* ]]; then
            DB_USER=$(docker exec $CONTAINER_NAME bash -c 'echo "$MYSQL_USER"')
            DB_PASSWORD=$(docker exec $CONTAINER_NAME bash -c 'echo "$MYSQL_PASSWORD"')
            SQLFILE="$BACKUPFOLDER/databases/$CONTAINER_NAME-mysql-$DATE.sql"
            if [[ $DRY_RUN == "yes" ]]; then
                $DRY Execute dump of database in $CONTAINER_NAME $DRY2
            else
                docker exec -e MYSQL_PWD=$DB_PASSWORD $CONTAINER_NAME /usr/bin/mysqldump -u $DB_USER --no-tablespaces --all-databases > $SQLFILE
                status=$?
                if test $status -eq 0; then
                    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ✅   Backup database of $CONTAINER_NAME completed."
                    ((DB_COUNT++))
                else
                    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ❌   ERROR : A problem was encountered during the backup database of $CONTAINER_NAME."
                    ((DB_BACKUP_ERRORS++))
                fi
                echo "                                            🔹 [ $CONTAINER_NAME ] - $CONTAINER_NAME-mysql-$DATE.sql : $DB_SIZE_AFTER_H" >> databases.txt
            fi
            
        elif [[ $DB_VERSION == *"postgres"* ]]; then
            DB_USER=$(docker exec $CONTAINER_NAME bash -c 'echo "$POSTGRES_USER"')
            DB_PASSWORD=$(docker exec $CONTAINER_NAME bash -c 'echo "$POSTGRES_PASSWORD"')
            SQLFILE="$BACKUPFOLDER/databases/$CONTAINER_NAME-postgres-$DATE.sql"
            if [[ $DRY_RUN == "yes" ]]; then
                $DRY Execute dump of database in $CONTAINER_NAME $DRY2
            else
                docker exec -t $CONTAINER_NAME pg_dumpall -c -U $DB_USER > $SQLFILE
                status=$?
                if test $status -eq 0; then
                    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ✅   Backup database of $CONTAINER_NAME completed."
                    ((DB_COUNT++))
                else
                    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ❌   ERROR : A problem was encountered during the backup database of $CONTAINER_NAME."
                    ((DB_BACKUP_ERRORS++))
                fi
                DB_SIZE_AFTER_H=$(du -hs $SQLFILE | awk '{print $1}')
                echo "                                            🔹 [ $CONTAINER_NAME ] - $CONTAINER_NAME-postgres-$DATE.sql : $DB_SIZE_AFTER_H" >> databases.txt
            fi
        else
            echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ❌   ERROR : Can't get credentials of $CONTAINER_NAME."
            ((DB_BACKUP_ERRORS++))
        fi

        SIZE=1000
        if [[ DRY_RUN == "no" ]] && [ "$(du -sb $SQLFILE | awk '{ print $1 }')" -le $SIZE ]; then
            echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ⚠️   WARNING : Backup file of $CONTAINER_NAME is smaller than 1Mo."
            ((DB_BACKUP_ERRORS++))
        fi
            
        DB_LIST=$(echo "$DB_LIST $CONTAINER_NAME")


    done
    echo ""
    printf '=%.0s' {1..100}
    echo ""
}

# Informations
function Dry-informations {
    FOLDER_TOTAL_SIZE_H=$(echo $FOLDER_TOTAL_SIZE | awk '{$1=$1/(1024^2); print $1,"GB";}')
    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🔷   FREE SPACE : $FREE_SPACE_H"
    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🔷   BACKUP FOLDERS SIZE : ~ $FOLDER_TOTAL_SIZE_H"
    echo ""
    printf '=%.0s' {1..100}
    echo ""
}

function Run-informations {
    DB_TOTAL_SIZE_H=$(du -hs $BACKUPFOLDER/databases/ | awk '{print $1}')
    DB_TOTAL_SIZE=$(du -s $BACKUPFOLDER/databases/ | awk '{print $1}')
    FOLDER_TOTAL_SIZE_H=$(echo $FOLDER_TOTAL_SIZE | awk '{$1=$1/(1024^2); print $1,"GB";}')
    FOLDER_TOTAL_SIZE_COMPRESSED=$(du -s $BACKUPFOLDER | awk '{print $1}')
    FOLDER_TOTAL_SIZE_COMPRESSED_H=$(du -hs $BACKUPFOLDER | awk '{print $1}')
    FREE_SPACE_AFTER_H=$(df -h $WORKFOLDER | awk 'FNR==2{print $4}')
    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🔷   FREE SPACE BEFORE : $FREE_SPACE_H"
    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🔷   BACKUP FOLDERS SIZE (after compression) : ~ $FOLDER_TOTAL_SIZE_H ($FOLDER_TOTAL_SIZE_COMPRESSED_H)"
    echo "$(<folders.txt)" 
    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   🔷   BACKUP DATABASE SIZE : ~ $DB_TOTAL_SIZE_H"
    echo "$(<databases.txt)" 
    rm folders.txt databases.txt
    echo ""
    printf '=%.0s' {1..100}
    echo ""
}

# Send to Swiss Backup
function Send-to-Swiss-Backup {
    SWISSBACKUP_STATUS=0
    rclone mkdir Swiss-Backup:$BACKUPFOLDER
    rclone -P copy --header-upload "X-Delete-After: $DELETE_AFTER" $WORKFOLDER/$BACKUPFOLDER Swiss-Backup:$BACKUPFOLDER
    status=$?
    if test $status -eq 0; then
        BACKUP_STATUS=$(echo "$BACKUP_STATUS 🟢 Swiss-Backup")
        echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ✅   Backup are uploaded to Swiss-Backup."
    else
        BACKUP_STATUS=$(echo "$BACKUP_STATUS 🔴 Swiss-Backup")
        echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ❌   ERROR : A problem was encountered during the upload to Swiss-Backup."
        ((SWISSBACKUP_STATUS++))
    fi

    echo ""
    printf '=%.0s' {1..100}
    echo ""
}

# Send to kDrive
function Send-to-kDrive {
    KDRIVE_STATUS=0
    rclone -P copy $WORKFOLDER/$BACKUPFOLDER kDrive:$BACKUPFOLDER
    status=$?
    if test $status -eq 0; then
        BACKUP_STATUS=$(echo "$BACKUP_STATUS 🟢 kDrive")
        echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ✅   Backup are uploaded to kDrive."
    else
        BACKUP_STATUS=$(echo "$BACKUP_STATUS 🔴 kDrive")
        echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ❌   ERROR : A problem was encountered during the upload to kDrive."
        ((KDRIVE_STATUS++))
    fi
    echo ""
    printf '=%.0s' {1..100}
    echo ""
}

# Send to Zabbix
function Send-To-Zabbix {
    echo "\"$ZABBIX_HOST"\" key.date-last-backup $DATE >> $ZABBIX_DATA
    echo "\"$ZABBIX_HOST"\" key.backup-size $FOLDER_TOTAL_SIZE >> $ZABBIX_DATA
    echo "\"$ZABBIX_HOST"\" key.backup-size-compressed $FOLDER_TOTAL_SIZE_COMPRESSED >> $ZABBIX_DATA
    echo "\"$ZABBIX_HOST"\" key.backup-time $RUN_TIME >> $ZABBIX_DATA
    echo "\"$ZABBIX_HOST"\" key.folder-backup-errors $FOLDERS_BACKUP_ERRORS >> $ZABBIX_DATA
    echo "\"$ZABBIX_HOST"\" key.folder-backup-count $FOLDERS_COUNT >> $ZABBIX_DATA
    echo "\"$ZABBIX_HOST"\" key.folder-backup-list $FOLDER_LIST >> $ZABBIX_DATA
    echo "\"$ZABBIX_HOST"\" key.db-backup-errors $DB_BACKUP_ERRORS >> $ZABBIX_DATA
    echo "\"$ZABBIX_HOST"\" key.db-backup-count $DB_COUNT >> $ZABBIX_DATA
    echo "\"$ZABBIX_HOST"\" key.db-backup-list $DB_LIST >> $ZABBIX_DATA
    echo "\"$ZABBIX_HOST"\" key.send-swissbackup-status $SWISSBACKUP_STATUS >> $ZABBIX_DATA
    echo "\"$ZABBIX_HOST"\" key.send-kdrive-status $KDRIVE_STATUS >> $ZABBIX_DATA

    
    if [[ $DRY_RUN == "yes" ]]; then
        $DRY Send data to Zabbix server (Host : $ZABBIX_HOST - Server : $ZABBIX_SRV) $DRY2
    else
        zabbix_sender -z $ZABBIX_SRV -i $ZABBIX_DATA2
        status=$?
        if test $status -eq 0; then
            echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ✅   Data sended to Zabbix."
        else
            echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ❌   ERROR : A problem was encountered during the send data to Zabbix."
        fi
    fi
}

# Discord Notifications
function Send-Discord-Notifications {
    ./discord.sh --webhook-url=$DISCORD_WEBHOOK --username "BACKUP-NURION" --text "Backup of $DATE" --title "Folders and databases have been successfully backed up !" --description "**Folders ($FOLDER_TOTAL_SIZE_H) :\n** $FOLDER_LIST\n**Databases ($DB_TOTAL_SIZE_H) :\n** $DB_LIST\n**Time :** $RUN_TIME_H" --color 0x4BF646 --footer "$BACKUP_STATUS" --footer-icon "https://send.papamica.fr/f.php?h=0QpaiREO&p=1"
    echo "[$(date +%Y-%m-%d_%H:%M:%S)]   BackupScript   ✅   Notification are sended to Discord"
    echo ""
    printf '=%.0s' {1..100}
    echo ""
}



# List backups



# Cleanup

# Execution
START_TIME="date +%s"
if [[ $KDRIVE == "yes" ]]; then
    Create-Rclone-Config-kDrive
fi
if [[ $SWISS_BACKUP == "yes" ]]; then
    Create-Rclone-Config-Swiss-Backup
fi

Backup-Folders

if [[ $DOCKER == "yes" ]]; then
    Backup-Database
fi

if [[ $DRY_RUN == "yes" ]]; then
    Dry-informations
else
    Run-informations
    if [[ $KDRIVE == "yes" ]]; then
        Send-to-kDrive
    fi
    if [[ $SWISS_BACKUP == "yes" ]]; then
        Send-to-Swiss-Backup
    fi
fi
END_TIME="date +%s"
RUN_TIME=$((END_TIME-START_TIME))
RUN_TIME_H=$(eval "echo $(date -ud "@$RUN_TIME" +'$((%s/3600/24)) days %H hours %M minutes %S seconds')")
if [[ $DISCORD == "yes" ]]; then
    Send-Discord-Notifications
fi
if [[ $ZABBIX == "yes" ]]; then
    Send-To-Zabbix
fi

rm -rf $WORKFOLDER/$BACKUPFOLDER