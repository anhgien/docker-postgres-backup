#!/bin/sh

if [ "${POSTGRES_ENV_POSTGRES_PASSWORD}" == "**Random**" ]; then
        unset POSTGRES_ENV_POSTGRES_PASSWORD
fi

RESTIC_PASSWORD=${RESTIC_PASSWORD:-$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c16)}
POSTGRES_HOST=${POSTGRES_PORT_5432_TCP_ADDR:-${POSTGRES_HOST}}
POSTGRES_HOST=${POSTGRES_PORT_1_5432_TCP_ADDR:-${POSTGRES_HOST}}
POSTGRES_PORT=${POSTGRES_PORT_5432_TCP_PORT:-${POSTGRES_PORT}}
POSTGRES_PORT=${POSTGRES_PORT_1_3306_TCP_PORT:-${POSTGRES_PORT}}
POSTGRES_USER=${POSTGRES_USER:-${POSTGRES_ENV_POSTGRES_USER}}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-${POSTGRES_ENV_POSTGRES_PASSWORD}}

[ -z "${POSTGRES_HOST}" ] && { echo "=> POSTGRES_HOST cannot be empty" && exit 1; }
[ -z "${POSTGRES_PORT}" ] && { echo "=> POSTGRES_PORT cannot be empty" && exit 1; }
[ -z "${POSTGRES_USER}" ] && { echo "=> POSTGRES_USER cannot be empty" && exit 1; }
[ -z "${POSTGRES_PASSWORD}" ] && { echo "=> POSTGRES_PASSWORD cannot be empty" && exit 1; }
[ -z "${POSTGRES_DB}" ] && { echo "=> POSTGRES_DB cannot be empty" && exit 1; }

export PGPASSWORD="${POSTGRES_PASSWORD}"

BACKUP_CMD="pg_dump -h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -U ${POSTGRES_USER} -F c -b -v -f /backup/\${BACKUP_NAME} ${EXTRA_OPTS} ${POSTGRES_DB}"

echo "=> Creating backup script"
rm -f /backup.sh
cat <<EOF >> /backup.sh
#!/bin/sh
MAX_BACKUPS=${MAX_BACKUPS}

BACKUP_NAME=\$(date +\%Y.\%m.\%d.\%H\%M\%S).backup

export PGPASSWORD="${POSTGRES_PASSWORD}"

export MINIO_HOST=${MINIO_HOST}
if [ -n "\${MINIO_HOST}" ]; then
	export AWS_ACCESS_KEY_ID=${MINIO_ACCESS_KEY}
	export AWS_SECRET_ACCESS_KEY=${MINIO_SECRET_KEY}
	export RESTIC_PASSWORD=${RESTIC_PASSWORD}
	export RESTIC_REPOSITORY=s3:${MINIO_HOST_URL}/${MINIO_BUCKET}restic
fi

echo "=> Backup started: \${BACKUP_NAME}"
if ${BACKUP_CMD} ;then
    echo "   Backup succeeded"
    ${BACKUP_RESTIC_CMD}
else
    echo "   Backup failed"
    rm -rf /backup/\${BACKUP_NAME}
fi

if [ -n "\${MAX_BACKUPS}" ]; then
    while [ \$(ls /backup -N1 | wc -l) -gt \${MAX_BACKUPS} ];
    do
        BACKUP_TO_BE_DELETED=\$(ls /backup -N1 | sort | head -n 1)
        echo "   Backup \${BACKUP_TO_BE_DELETED} is deleted"
        rm -rf /backup/\${BACKUP_TO_BE_DELETED}
    done
fi
echo "=> Backup done"
EOF
chmod +x /backup.sh
ls .
echo "=> Creating restore script"
rm -f /restore.sh
cat <<EOF >> /restore.sh
#!/bin/sh
export PGPASSWORD="${POSTGRES_PASSWORD}"

echo "=> Restore database from \$1"
if pg_restore -h ${POSTGRES_HOST} -p ${POSTGRES_PORT} -d ${POSTGRES_DB} -U ${POSTGRES_USER} -v \$1 ;then
    echo "   Restore succeeded"
else
    echo "   Restore failed"
fi
echo "=> Done"
EOF
chmod +x /restore.sh

touch /postgres_backup.log
tail -F /postgres_backup.log &

if [ -n "${INIT_BACKUP}" ]; then
    echo "=> Create a backup on the startup"
    /backup.sh
elif [ -n "${INIT_RESTORE_LATEST}" ]; then
    echo "=> Restore latest backup"
    until nc -z $POSTGRES_HOST $POSTGRES_PORT
    do
        echo "waiting database container..."
        sleep 1
    done
    ls -d -1 /backup/* | tail -1 | xargs /restore.sh
fi

echo "${CRON_TIME} sh -c /backup.sh >> /postgres_backup.log 2>&1" > /etc/crontabs/contab.conf
echo "=> Running cron job"
exec crond -l 2 -f