#!/bin/sh

lastLogfile="/var/log/backup-last.log"
lastMailLogfile="/var/log/mail-last.log"
lastMicrosoftTeamsLogfile="/var/log/microsoft-teams-last.log"

copyErrorLog() {
  cp ${lastLogfile} /var/log/backup-error-last.log
}

logLast() {
  echo "$1" >> ${lastLogfile}
}

if [ -f "/hooks/pre-backup.sh" ]; then
    echo "Starting pre-backup script ..."
    /hooks/pre-backup.sh
else
    echo "Pre-backup script not found ..."
fi

if [ -n "$RESTIC_PRE_BACKUP" ]; then
    echo "Starting pre-backup command ..."
    eval "$RESTIC_PRE_BACKUP"
    echo "Done"
else
    echo "Pre-backup command not found ..."
fi

start=`date +%s`
rm -f ${lastLogfile} ${lastMailLogfile}
echo "Starting Backup at $(date +"%Y-%m-%d %H:%M:%S")"
echo "Starting Backup at $(date)" >> ${lastLogfile}
logLast "BACKUP_CRON: ${BACKUP_CRON}"
logLast "RESTIC_TAG: ${RESTIC_TAG}"
logLast "RESTIC_FORGET_ARGS: ${RESTIC_FORGET_ARGS}"
logLast "RESTIC_JOB_ARGS: ${RESTIC_JOB_ARGS}"
logLast "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"
logLast "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}"

if [ -n "${RESTIC_STREAM}" ]; then
    if [ -z "${RESTIC_STREAM_CMD}" ] || [ -z "${RESTIC_STREAM_FILENAME}" ] || [ -z "${RESTIC_TAG}" ]; then
        echo "RESTIC_STREAM_CMD, RESTIC_STREAM_FILENAME and RESTIC_TAG variables has to be set when running in RESTIC_STREAM mode!"
        exit 1
    fi
    # stream backup into repository
    eval "$RESTIC_STREAM_CMD | restic backup --stdin --stdin-filename $RESTIC_STREAM_FILENAME --tag=$RESTIC_TAG >> $lastLogfile 2>&1"
else
    # consider backup is present on the /data mount point
    restic backup /data ${RESTIC_JOB_ARGS} --tag=${RESTIC_TAG?"Missing environment variable RESTIC_TAG"} >> ${lastLogfile} 2>&1
fi

# Do not save full backup log to logfile but to backup-last.log
backupRC=$?
logLast "Finished backup at $(date)"
if [[ $backupRC == 0 ]]; then
    echo "Backup Successful"
else
    echo "Backup Failed with Status ${backupRC}"
    restic unlock
    copyErrorLog
fi

if [[ $backupRC == 0 ]] && [ -n "${RESTIC_FORGET_ARGS}" ]; then
    echo "Forget about old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}"
    restic forget ${RESTIC_FORGET_ARGS} >> ${lastLogfile} 2>&1
    rc=$?
    logLast "Finished forget at $(date)"
    if [[ $rc == 0 ]]; then
        echo "Forget Successful"
    else
        echo "Forget Failed with Status ${rc}"
        restic unlock
        copyErrorLog
    fi
fi

end=`date +%s`
echo "Finished Backup at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds"

if [ -n "${TEAMS_WEBHOOK_URL}" ]; then
    teamsTitle="Restic Last Backup Log"
    teamsMessage=$( cat ${lastLogfile} | sed 's/"/\"/g' | sed "s/'/\'/g" | sed ':a;N;$!ba;s/\n/\n\n/g' )
    teamsReqBody="{\"title\": \"${teamsTitle}\", \"text\": \"${teamsMessage}\" }"
    sh -c "curl -H 'Content-Type: application/json' -d '${teamsReqBody}' '${TEAMS_WEBHOOK_URL}' > ${lastMicrosoftTeamsLogfile} 2>&1"
    if [ $? == 0 ]; then
        echo "Microsoft Teams notification successfully sent."
    else
        echo "Sending Microsoft Teams notification FAILED. Check ${lastMicrosoftTeamsLogfile} for further information."
    fi
fi

if [ -n "${MAILX_ARGS}" ]; then
    sh -c "mail -v -S sendwait ${MAILX_ARGS} < ${lastLogfile} > ${lastMailLogfile} 2>&1"
    if [ $? == 0 ]; then
        echo "Mail notification successfully sent."
    else
        echo "Sending mail notification FAILED. Check ${lastMailLogfile} for further information."
    fi
fi

if [ -f "/hooks/post-backup.sh" ]; then
    echo "Starting post-backup script ..."
    /hooks/post-backup.sh $backupRC
else
    echo "Post-backup script not found ..."
fi

if [ -n "$RESTIC_POST_BACKUP" ]; then
    echo "Starting post-backup command ..."
    eval "$RESTIC_POST_BACKUP"
    echo "Done"
else
    echo "Post-backup command not found ..."
fi
