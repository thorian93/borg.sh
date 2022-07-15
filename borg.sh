#!/bin/bash
#
# Written by: Robin Gierse - info@thorian93.de - on 20220715
#
# Purpose: Initialize, run and prune borg backups.
# 
#
# Version: 0.1 on 20220715
#
# Usage:
# ./borg.sh -m full -a mysql

while getopts ":m:a:" opt; do
  case $opt in
    m)
      BORG_MODE="$OPTARG" >&2
      ;;
    a)
      BORG_ADDONS="$OPTARG" >&2
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

# Variables:
BORG_SSH_USER="${BORG_SSH_USER}"
BORG_SSH_HOST="${BORG_SSH_HOST}"
BORG_REPO_PATH="${BORG_REPO_PATH}"
BORG_ENCRYPTION='keyfile-blake2'  # repokey-blake2, none, keyfile, repokey
BORG_COMPRESSION='lzma'  # lz4, none, zstd, zlib, lzma, auto
BORG_KEEP_DAILY='7'
BORG_KEEP_WEEKLY='4'
BORG_KEEP_MONTHLY='3'
BORG_SOURCES='
/
'
BORG_DBS_USER="${BORG_DBS_USER-backup}"
BORG_DBS_PASS="${BORG_DBS_PASS}"
BORG_DBS='mysql'
BORG_DBS_DEST='/private-backup'
export BORG_REPO=${BORG_SSH_USER}@${BORG_SSH_HOST}:${BORG_REPO_PATH}
export BORG_PASSPHRASE="${BORG_PASSPHRASE}"

# Functions:

_log_line() {
    printf "\n%s %s\n\n" "$( date )" "$*" >&2;
}

_print_config() {
    echo "SSH User: ${BORG_SSH_USER}"
    echo "SSH Host: ${BORG_SSH_HOST}"
    echo "Repo Path: ${BORG_REPO_PATH}"
    echo "Encryption: ${BORG_ENCRYPTION}"
    echo "Full Repo: ${BORG_REPO}"
    echo "Passphrase: ${BORG_PASSPHRASE}"
    echo "Compression: ${BORG_COMPRESSION}"
}

_setup_systemd() {
    echo "TBD"
}

_backup_mysql() {
    for db in ${BORG_DBS}
    do
        mysqldump --single-transaction -h localhost -u "${BORG_DBS_USER}" -p"${BORG_DBS_PASS}" $db > ${BORG_DBS_DEST}/$db.sql
    done
}

_borg_init() {
    borg init \
    --encryption=${BORG_ENCRYPTION} \
    "${BORG_REPO}"
    init_exit=$?
    if [ ! $init_exit -eq 0 ]
    then
        if [ $init_exit -eq 2 ]
        then
            _log_line 'Repository already initialized. Splendid.'
        else
            _log_line "An error occured: $init_exit" ; exit $init_exit
        fi
    fi
}

_borg_backup() {
    _log_line "Starting Backup."
    borg create \
    --filter AME \
    --list --stats --show-rc \
    --compression ${BORG_COMPRESSION} --exclude-caches \
    ::'{hostname}-{now}' \
        ${BORG_SOURCES} \
        --exclude /dev \
        --exclude /proc \
        --exclude /sys \
        --verbose
    backup_exit=$?    
}

_borg_prune() {
    _log_line "Pruning Repository."
    borg prune \
    --list \
    --prefix '{hostname}-' \
    --show-rc \
    --keep-daily ${BORG_KEEP_DAILY} \
    --keep-weekly ${BORG_KEEP_WEEKLY} \
    --keep-monthly ${BORG_KEEP_MONTHLY} 2>&1
    prune_exit=$?
}

_exit() {
    global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
    if [ ${global_exit} -eq 1 ];
    then
        info "Backup and/or Prune finished with a warning"
    fi
    if [ ${global_exit} -gt 1 ];
    then
        info "Backup and/or Prune finished with an error"
    fi
    exit ${global_exit} 
}

# Main:
case $BORG_MODE in
    config)
        _print_config
    ;;
    init)
        _borg_init
    ;;
    backup)
        _borg_backup
    ;;
    prune)
        _borg_prune
    ;;
    full)
        _borg_init
        for addon in $BORG_ADDONS
        do
            case $addon in
                mysql)
                    _backup_mysql
                ;;
            esac
        done
        _borg_backup
        _borg_prune
    ;;
esac
_exit
