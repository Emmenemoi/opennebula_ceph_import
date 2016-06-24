#!/bin/sh

BRIDGE_HOST=""
SOURCE_IMAGE=""
DEST_IMAGE=""
CEPH_ID="admin"
LIVE=NO
LIVE_INTERVAL=10 # 10 sec min downtime
VERBOSE=YES
ONE_USER="oneadmin"

TARGET_NAME=""
TARGET_DATASTORE="0"

CONFIG=""
FORCE_FORMAT=""
MAX_SYNC=10

for i in "$@"
do
case $i in
    -c=*|--config=*)
    CONFIG="${i#*=}"
    shift # past argument=value
    ;;
    -b=*|--bridge=*)
    BRIDGE_HOST="${i#*=}"
    shift # past argument=value
    ;;
    -u=*|--one-user=*)
    ONE_USER="${i#*=}"
    shift # past argument=value
    ;;
    -s=*|--src=*)
    SOURCE_IMAGE="${i#*=}"
    shift # past argument=value
    ;;
    -d=*|--dest=*)
    DEST_IMAGE="${i#*=}"
    shift # past argument=value
    ;;
    --datastore=*)
    TARGET_DATASTORE="${i#*=}"
    shift # past argument=value
    ;;
    --name=*)
    TARGET_NAME="${i#*=}"
    shift # past argument=value
    ;;
    -i=*|--id=*)
    CEPH_ID="${i#*=}"
    shift # past argument=value
    ;;
    -t=*|--time-sync=*)
    LIVE_INTERVAL="${i#*=}"
    shift # past argument=value
    ;;
    -l|--live)
    LIVE=YES
    shift # past argument with no value
    ;;
    -2)
    FORCE_FORMAT="--image-format 2"
    shift # past argument with no value
    ;;
    -v|--verbose)
    VERBOSE=YES
    shift # past argument with no value
    ;;
    *)
            # unknown option
    ;;
esac
done

if [[ $CONFIG ]]; then
	echo "Use values from config at ${CONFIG}"
	source "$CONFIG"
fi

#if [[ "$VERBOSE" == "YES" ]]; then
	echo "ONE USER           = ${ONE_USER}"
	echo "BRIDGE HOST        = ${BRIDGE_HOST}"
	echo "SOURCE IMAGE       = ${SOURCE_IMAGE}"
	echo "DESTINATION IMAGE  = ${DEST_IMAGE}"
	echo "CEPHX ID           = ${CEPH_ID}"
	echo "LIVE SYNC          = ${LIVE}"
	echo "TARGET NAME        = ${TARGET_NAME}"
	echo "TARGET DATASTORE ID= ${TARGET_DATASTORE}"

	if [[ "$LIVE" == "YES" ]]; then
		echo "LIVE INTERVAL      = ${LIVE_INTERVAL}"
	fi
#fi


if [[ -n $1 ]]; then
    echo "Last line of file specified as non-opt/last argument:"
    tail -1 $1
fi

read -n1 -r -p "Start ? (y/n)" key
if [ ! "$key" == 'y' ]; then
	exit
fi

SSH_PREFIX="sudo -u ${ONE_USER} ssh ${BRIDGE_HOST} "

cmd () {
	if [[ "$VERBOSE" == "YES" ]]; then
		printf "$1 \n" 1>&2
	fi
	$1
}

timestamp () {
  date +"%s"
}

SYNC_ID=0
SYNC_PREFIX="one-sync-"
init_sync () {
	# fetch last sync id
	INITIAL_ID=$(cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap ls ${SOURCE_IMAGE} | grep -oP '(?<=${SYNC_PREFIX})\d+' | sort | head -n 1")
	if [[ $INITIAL_ID ]]; then
		SYNC_ID=$INITIAL_ID
		printf "Starting from last sync at $SYNC_ID\n"
	else
		cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
		cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  export ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID} - | rbd --id ${CEPH_ID}  import ${FORCE_FORMAT} - ${DEST_IMAGE}"
		cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${DEST_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
	fi
}

diff_sync () {
	NEXT=$(expr $SYNC_ID + 1)
	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${SOURCE_IMAGE}@${SYNC_PREFIX}${NEXT}"
	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  export-diff --from-snap ${SYNC_PREFIX}${SYNC_ID} ${SOURCE_IMAGE}@${SYNC_PREFIX}${NEXT} - | rbd --id ${CEPH_ID}  import-diff - ${DEST_IMAGE}"
	#cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${DEST_IMAGE}@${SYNC_PREFIX}${NEXT}"

	# clean older snaps
	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap rm ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap rm ${DEST_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"

	SYNC_ID=$NEXT
}

SIZE=$(cmd "${SSH_PREFIX} rbd --id ${CEPH_ID} info ${SOURCE_IMAGE} | grep 'size' | cut -d ' ' -f2")

printf "Initial sync of ${SOURCE_IMAGE} ($SIZE MB)\n"

init_sync

LAST_SYNC=$(expr $(timestamp) - $LIVE_INTERVAL - 10)
while 	[ $(expr $(timestamp) - $LAST_SYNC) -gt "$LIVE_INTERVAL" ] && 
		[ "$MAX_SYNC" -gt "0" ]; do
	LAST_SYNC=$(timestamp)
	MAX_SYNC=$(expr $MAX_SYNC - 1)
	diff_sync
done

echo "Last sync took less than $LIVE_INTERVAL sec.\nIt is time to stop the I/O (VM) to do the last sync and be able to start the VM using the imported image.\n"
read -n1 -r -p "I/O have been stopped? (y)" key
while [ ! "$key" == 'y' ]; do
	sleep 5;
	read -n1 -r -p "I/O have been stopped? (y)" key
done

diff_sync

printf "Add image in Opennebula\n"
cmd "sudo -u ${ONE_USER} oneimage create --name ${TARGET_NAME} --source ${DEST_IMAGE} --size $SIZE -d ${TARGET_DATASTORE} --persistent"

printf "Clean source snaps\n"
for SNAP in $(cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap ls ${SOURCE_IMAGE} | grep -oP '${SYNC_PREFIX}\d+' | sort")
do
	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap rm ${SOURCE_IMAGE}@$SNAP"
done

printf "Clean dest snaps\n"
for SNAP in $(cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap ls ${DEST_IMAGE} | grep -oP '${SYNC_PREFIX}\d+' | sort")
do
	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap rm ${DEST_IMAGE}@$SNAP"
done



