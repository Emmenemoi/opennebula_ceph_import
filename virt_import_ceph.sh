#!/bin/bash

# For opennebula: use oneadmin as SSH_USER


BRIDGE_HOST=""
SOURCE_IMAGE=""
DEST_IMAGE=""
CEPH_ID="admin"
LIVE=NO
IMPORT_TOOL="rbd" # could be rbd, rsync, dd
SOURCE_TYPE="rbd" # could be rbd, local
LIVE_INTERVAL=10 # 10 sec min downtime
VERBOSE=YES
SSH_USER="root"
FSFREEZE_HOST=""
FSFREEZE_HOST_KEY="~/.ssh/id_rsa"

TARGET_SR_UUID=""
TARGET_VDI_UUID=$(cat /proc/sys/kernel/random/uuid) # default: new

XS_SR_PREFIX="RBD_XenStorage-"
XS_VDI_PREFIX="VHD-"

TARGET_NAME=""
TARGET_DATASTORE="0"

CONFIG=""
FORCE_FORMAT=""
OBJECT_SIZE=2097152 #in bytes, better for GTP 2048 boundaries alignments
OBJECT_SIZE_OPT="--object-size ${OBJECT_SIZE}"
MAX_SYNC=10 # max number of diff syncs
RBD_MODE="rbd-nbd" # could be rbd or rbd-nbd
LOCAL_SOURCE_TOOL="raw" # could be raw, lvm, zfs

IMPORT_DEST="" # could be xenserver, cinder or opennebula
CLEAN_ONLY=NO

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
    -u=*|--user=*)
    SSH_USER="${i#*=}"
    shift # past argument=value
    ;;
    -s=*|--src=*)
    SOURCE_IMAGE="${i#*=}"
    shift # past argument=value
    ;;
    --src-type=*)
    SOURCE_TYPE="${i#*=}"
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
    --sr-uuid=*)
    TARGET_SR_UUID="${i#*=}"
    shift # past argument=value
    ;;
    --vdi-uuid=*)
    TARGET_VDI_UUID="${i#*=}"
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
    --rsync)
    IMPORT_TOOL="rsync"
    shift # past argument with no value
    ;;
    --dd)
    IMPORT_TOOL="dd"
    shift # past argument with no value
    ;;
    -2)
    FORCE_FORMAT="--image-format 2"
    shift # past argument with no value
    ;;
    --cinder)
    IMPORT_DEST="cinder"
    shift # past argument with no value
    ;;
    --one)
    IMPORT_DEST="opennebula"
    shift # past argument with no value
    ;;
    --xs)
    IMPORT_DEST="xenserver"
    shift # past argument with no value
    ;;
    -v|--verbose)
    VERBOSE=YES
    shift # past argument with no value
    ;;
    --clean)
    CLEAN_ONLY=YES
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

	if [[ $SOURCE_IMAGE == "/dev/"* ]]; then
		SOURCE_TYPE="local"
	fi
#if [[ "$VERBOSE" == "YES" ]]; then
	if [[ "$SOURCE_TYPE" == "local" ]]; then
		IMPORT_TOOL="rsync"
		
		# define LOCAL_SOURCE_TOOL
		if [[ $SOURCE_IMAGE == *"/zvol/"* ]]; then
			LOCAL_SOURCE_TOOL="zfs";
			ZFS_SOURCE_IMAGE=${SOURCE_IMAGE/\/dev\/zvol\//}
			SOURCE_POOL=${ZFS_SOURCE_IMAGE%%/*}
		else
			if lvdisplay | grep -q $SOURCE_IMAGE; then
		  		LOCAL_SOURCE_TOOL="lvm";
				echo found
			else
				echo not found
			fi
			SOURCE_POOL=${SOURCE_IMAGE/\/dev\//}
			SOURCE_POOL=${SOURCE_POOL%%/*}
		fi
	else
		SOURCE_POOL=${SOURCE_IMAGE%%/*}
	fi

	if [[ "$IMPORT_DEST" == "xenserver" ]]; then
		echo "TARGET SR UUID     = ${TARGET_SR_UUID}"
		echo "TARGET VDI UUID    = ${TARGET_VDI_UUID}"
		DEST_IMAGE="${XS_SR_PREFIX}${TARGET_SR_UUID}/${XS_VDI_PREFIX}${TARGET_VDI_UUID}"
	fi

	DEST_POOL=${DEST_IMAGE%%/*}

	echo "SSH USER           = ${SSH_USER}"
	echo "BRIDGE HOST        = ${BRIDGE_HOST}"
	echo "SOURCE POOL        = ${SOURCE_POOL}"
	echo "SOURCE IMAGE       = ${SOURCE_IMAGE}"
	echo "DESTINATION POOL   = ${DEST_POOL}"
	echo "DESTINATION IMAGE  = ${DEST_IMAGE}"
	echo "CEPHX ID           = ${CEPH_ID}"
	echo "LIVE SYNC          = ${LIVE}"
	echo "IMPORT TOOL        = ${IMPORT_TOOL}"
	if [[ "$SOURCE_TYPE" == "local" ]]; then
	echo "LOCAL SOURCE TOOL  = ${LOCAL_SOURCE_TOOL}"
	fi
	echo "FSFREEZE HOST      = ${FSFREEZE_HOST}"
	echo "FSFREEZE HOST KEY  = ${FSFREEZE_HOST_KEY}"
	echo "TARGET NAME        = ${TARGET_NAME}"

	if [[ "$IMPORT_DEST" == "opennebula" ]]; then
		echo "TARGET DATASTORE ID= ${TARGET_DATASTORE}"
	fi

	if [[ "$LIVE" == "YES" ]]; then
		echo "LIVE INTERVAL      = ${LIVE_INTERVAL}"
	fi

#fi


if [[ -n $1 ]]; then
    echo "Last line of file specified as non-opt/last argument:"
    tail -1 $1
fi

read -n1 -r -p "Start ? (y/n)" key
printf "\n"
if [ ! "$key" == 'y' ]; then
	exit
fi


if [[ "$SSH_USER" == "root" ]]; then
	SUDO_PREFIX=""
else
	SUDO_PREFIX="sudo -u ${SSH_USER} "
fi

if [[ "$BRIDGE_HOST" == "" ]]; then
	SSH_PREFIX="${SUDO_PREFIX}"
else
	SSH_PREFIX="${SUDO_PREFIX}ssh ${BRIDGE_HOST} "
fi

if [ ! -z "$FSFREEZE_HOST" ]; then
	xl list $FSFREEZE_HOST
	FSFREEZE_HOST_IS_LOCAL_VM=$?
else
	FSFREEZE_HOST_IS_LOCAL_VM=1
fi

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
SYNC_PREFIX="virt-sync-"
IMPORT_DEV_DIR="/dev/imports"

######## INIT VARS FUNCTION #######
if [[ "$SOURCE_TYPE" == "local" ]]; then
	SOURCE_POOL_DIR=$(cmd "dirname ${SOURCE_IMAGE}")
	cmd "mkdir -p ${IMPORT_DEV_DIR}/${SOURCE_POOL_DIR}"
else
	cmd "$SSH_PREFIX mkdir -p ${IMPORT_DEV_DIR}/${SOURCE_POOL}"
fi
cmd "$SSH_PREFIX mkdir -p ${IMPORT_DEV_DIR}/${DEST_POOL}"

init_vars () {
	if [[ "$SOURCE_TYPE" == "local" ]]; then
		S_DEV_PATH="${SOURCE_IMAGE}"
	else
		S_DEV_PATH=$(cmd "$SSH_PREFIX realpath ${IMPORT_DEV_DIR}/${SOURCE_IMAGE}")
	fi
	D_DEV_PATH=$(cmd "$SSH_PREFIX realpath ${IMPORT_DEV_DIR}/${DEST_IMAGE}")
}

quiesced_rbd_map () {
	if [ -z "$1" ]                           # Is parameter #1 zero length?
	then
		echo "-Parameter #1/source image name is zero length.-"  # Or no parameter passed.
		return
	else
		local image=$1
	fi
	if [ -z "$2" ]                           # Is parameter #1 zero length?
	then
		echo "-Parameter #2/fsfreeze host is zero length: Can't freeze fs."  # Or no parameter passed.
	fi
	local host=$2
	local vm=$2
	if [ $FSFREEZE_HOST_IS_LOCAL_VM -eq 0 ]; then
		cmd "xl pause $vm"
	elif [ ! -z "$host" ]; then
		cmd "${SUDO_PREFIX}ssh -i ${FSFREEZE_HOST_KEY} $host fsfreeze -f /"
	fi
	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${image}@${SYNC_PREFIX}${SYNC_ID}"
	if [ $FSFREEZE_HOST_IS_LOCAL_VM -eq 0 ]; then
		cmd "xl unpause $vm"
	elif [ ! -z "$host" ]; then
		cmd "${SUDO_PREFIX}ssh -i ${FSFREEZE_HOST_KEY} $host fsfreeze -u /"
	fi
	S_DEV_PATH=$(cmd "$SSH_PREFIX ${RBD_MODE} map --id ${CEPH_ID} --read-only ${image}@${SYNC_PREFIX}${SYNC_ID}")
}

quiesced_zfs_map () {
	if [ -z "$1" ]                           # Is parameter #1 zero length?
	then
		echo "-Parameter #1/source image name is zero length.-"  # Or no parameter passed.
		return
	else
		local image=$1
		image=${image/\/dev\/zvol\//}
	fi
	if [ -z "$2" ]                           # Is parameter #1 zero length?
	then
		echo "-Parameter #2/fsfreeze host is zero length: Can't freeze fs."  # Or no parameter passed.
	fi
	local host=$2
	local vm=$2
	if [ $FSFREEZE_HOST_IS_LOCAL_VM -eq 0 ]; then
		cmd "xl pause $vm"
	elif [ ! -z "$host" ]; then
		cmd "${SUDO_PREFIX}ssh -i ${FSFREEZE_HOST_KEY} $host fsfreeze -f /"
	fi
	cmd "zfs snapshot ${image}@${SYNC_PREFIX}${SYNC_ID}"
	if [ $FSFREEZE_HOST_IS_LOCAL_VM -eq 0 ]; then
		cmd "xl unpause $vm"
	elif [ ! -z "$host" ]; then
		cmd "${SUDO_PREFIX}ssh -i ${FSFREEZE_HOST_KEY} $host fsfreeze -u /"
	fi
	cmd "zfs clone ${image}@${SYNC_PREFIX}${SYNC_ID} ${SOURCE_POOL}/vm-export"
	sleep 1
	S_DEV_PATH="/dev/zvol/${SOURCE_POOL}/vm-export"
}

finalize_setup () {
	DEVUUID=$(cmd "$SSH_PREFIX blkid -s UUID -o value ${D_DM_PATH}")

	UUID_REGEX="[[:alnum:]]\\{8\\}-[[:alnum:]]\\{4\\}-[[:alnum:]]\\{4\\}-[[:alnum:]]\\{4\\}-[[:alnum:]]\\{12\\}"

	# change root uuid
	cmd "$SSH_PREFIX sed -r -i.bak 's/^UUID=.*\\([[:space:]]+\\/[[:space:]]+\\)/UUID=${DEVUUID}\\1/' /mnt/destination/etc/fstab"

	cmd "$SSH_PREFIX sed -r -i.bak 's/GRUB_CMDLINE_LINUX=\"\\(.*\\)\"/GRUB_CMDLINE_LINUX=\"\\1 hpet=disable\"/' /mnt/destination/etc/default/grub"

	#if [[ ! "$EXISTS" == "YES" ]]; then
		cmd "$SSH_PREFIX grub-install --modules=part_gpt --boot-directory=/mnt/destination/boot ${D_DM_PATH}"
	#fi

	# SWAP old UUID with new
	cmd "$SSH_PREFIX sed -r -i.bak 's/${UUID_REGEX}/${DEVUUID}/' /mnt/destination/boot/grub/grub.cfg"

	printf "#######################################################################\n"
	printf "Or execute manually:\n"
	printf "xe vm-param-set HVM-boot-policy='' uuid=\$VMUUID\n"
	printf "xe vm-param-set PV-bootloader='pygrub' uuid=\$VMUUID\n"
	printf "xe vm-param-set PV-bootloader-args='--offset=${OBJECT_SIZE}' uuid=\$VMUUID\n"
	printf "xe vm-param-set PV-args='root=UUID=${DEVUUID}' uuid=\$VMUUID\n"
	printf "Plug XS guest tools !\n"
	printf "Then inside boot:\n"
	printf "sed -r -i.bak 's/GRUB_CMDLINE_LINUX=\"\\(.*\\)\"/GRUB_CMDLINE_LINUX=\"\\1 hpet=disable\"/' /etc/default/grub\n"
	printf "update-grub2\n"
	printf "grub-install --modules=part_gpt /dev/xvda\n"
	printf "=> VERIFY /etc/fstab\n"
	printf "xe vm-param-set HVM-boot-policy='BIOS order' uuid=\$VMUUID\n"
}

######### INIT SYNC FUNCTIONS #########
rbd_init_sync () {
	# fetch last sync id
	INITIAL_ID=$(cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap ls ${SOURCE_IMAGE} | grep -oP '(?<=${SYNC_PREFIX})\d+' | sort | head -n 1")
	if [[ $INITIAL_ID ]]; then
		SYNC_ID=$INITIAL_ID
		printf "Starting from last sync at $SYNC_ID\n"
	else
		cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
		cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  export ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID} - | rbd --id ${CEPH_ID}  import ${FORCE_FORMAT} ${OBJECT_SIZE_OPT} - ${DEST_IMAGE}"
		cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${DEST_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
	fi
}

rsync_init_sync () {

		cmd "$SSH_PREFIX mkdir -p /mnt/destination"
		if [[ "$SOURCE_TYPE" == "local" ]]; then
			case "$LOCAL_SOURCE_TOOL" in
				"zfs")
					quiesced_zfs_map ${SOURCE_IMAGE} ${FSFREEZE_HOST}
					;;
			esac
			cmd "mkdir -p /mnt/source"
			cmd "mount ${S_DEV_PATH} /mnt/source"
			cmd "ln -s ${S_DEV_PATH} ${IMPORT_DEV_DIR}/${SOURCE_IMAGE}"
		else
			cmd "$SSH_PREFIX mkdir -p /mnt/source"
			#cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
			#S_DEV_PATH=$(cmd "$SSH_PREFIX ${RBD_MODE} map --id ${CEPH_ID} --read-only ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}")
			quiesced_rbd_map ${SOURCE_IMAGE} ${FSFREEZE_HOST}
			cmd "$SSH_PREFIX mount ${S_DEV_PATH} /mnt/source"
			cmd "$SSH_PREFIX ln -s ${S_DEV_PATH} ${IMPORT_DEV_DIR}/${SOURCE_IMAGE}"
		fi
		
		if [[ ! "$EXISTS" == "YES" ]]; then
			SIZE=$(expr ${SIZE} + 500)
			SIZE=$(expr ${SIZE} / 1024000)
			cmd "$SSH_PREFIX rbd --id ${CEPH_ID} create --size ${SIZE} ${FORCE_FORMAT} ${OBJECT_SIZE_OPT} ${DEST_IMAGE}"
		fi
		D_DEV_PATH=$(cmd "$SSH_PREFIX ${RBD_MODE} map --id ${CEPH_ID} ${DEST_IMAGE}")
		cmd "$SSH_PREFIX ln -s ${D_DEV_PATH} ${IMPORT_DEV_DIR}/${DEST_IMAGE}"

		if [[ ! "$EXISTS" == "YES" ]]; then
			read -n1 -r -p "Will partition ${D_DEV_PATH}. Continue ? (ctrl-c to stop)" key
			printf "\n"
			cmd "$SSH_PREFIX parted --script ${D_DEV_PATH} mklabel gpt"
			PART_END=$(expr ${OBJECT_SIZE} - 1)
			cmd "$SSH_PREFIX parted --script --align optimal ${D_DEV_PATH} -- mkpart primary 34s ${PART_END}b"
			cmd "$SSH_PREFIX parted --script --align optimal ${D_DEV_PATH} -- mkpart primary ext4 ${OBJECT_SIZE}b -1"
			cmd "$SSH_PREFIX parted --script ${D_DEV_PATH} set 1 bios_grub on"
			cmd "$SSH_PREFIX parted --script ${D_DEV_PATH} set 2 boot on"
			cmd "$SSH_PREFIX parted --script ${D_DEV_PATH} disk_set pmbr_boot on"
			cmd "$SSH_PREFIX parted --script ${D_DEV_PATH} align-check optimal 2"
		fi

		D_DEV_PART=$(cmd "$SSH_PREFIX kpartx -avs ${D_DEV_PATH} | grep -i '[nr]bd.*p2' | cut -d ' ' -f3")
		D_DM_PATH="/dev/mapper/${D_DEV_PART}"
		if [[ ! "$EXISTS" == "YES" ]]; then
			cmd "$SSH_PREFIX mkfs -t ext4 ${D_DM_PATH}"
		fi
		cmd "$SSH_PREFIX mount ${D_DM_PATH} /mnt/destination"
}

dd_init_sync () {
		read -n1 -r -p "DD needs to stop I/O directly. I/O have been stopped? (y)" key
		printf "\n"
		while [ ! "$key" == 'y' ]; do
			sleep 5;
			read -n1 -r -p "I/O have been stopped? (y)" key
			printf "\n"
		done

		cmd "$SSH_PREFIX mkdir -p /mnt/source"
		cmd "$SSH_PREFIX mkdir -p /mnt/destination"
		if [[ "$SOURCE_TYPE" == "local" ]]; then
			S_DEV_PATH="${SOURCE_IMAGE}"
		else
			cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
			S_DEV_PATH=$(cmd "$SSH_PREFIX ${RBD_MODE} map --id ${CEPH_ID} --read-only ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}")
			cmd "$SSH_PREFIX ln -s ${S_DEV_PATH} ${IMPORT_DEV_DIR}/${SOURCE_IMAGE}"
		fi
		if [[ ! "$EXISTS" == "YES" ]]; then
			SIZE=$(expr ${SIZE} + 500)
			SIZE=$(expr ${SIZE} / 1024000)
			cmd "$SSH_PREFIX rbd --id ${CEPH_ID} create --size ${SIZE} ${FORCE_FORMAT} ${OBJECT_SIZE_OPT} ${DEST_IMAGE}"
		fi
		D_DEV_PATH=$(cmd "$SSH_PREFIX ${RBD_MODE} map --id ${CEPH_ID} ${DEST_IMAGE}")
		cmd "$SSH_PREFIX ln -s ${D_DEV_PATH} ${IMPORT_DEV_DIR}/${DEST_IMAGE}"

		if [[ ! "$EXISTS" == "YES" ]]; then
			read -n1 -r -p "Will partition ${D_DEV_PATH}. Continue ? (ctrl-c to stop)" key
			printf "\n"
			cmd "$SSH_PREFIX parted --script ${D_DEV_PATH} mklabel gpt"
			PART_END=$(expr ${OBJECT_SIZE} - 1)
			cmd "$SSH_PREFIX parted --script --align optimal ${D_DEV_PATH} -- mkpart primary 34s ${PART_END}b"
			cmd "$SSH_PREFIX parted --script --align optimal ${D_DEV_PATH} -- mkpart primary ext4 ${OBJECT_SIZE}b -1"
			cmd "$SSH_PREFIX parted --script ${D_DEV_PATH} set 1 bios_grub on"
			cmd "$SSH_PREFIX parted --script ${D_DEV_PATH} set 2 boot on"
			cmd "$SSH_PREFIX parted --script ${D_DEV_PATH} disk_set pmbr_boot on"
			cmd "$SSH_PREFIX parted --script ${D_DEV_PATH} align-check optimal 2"
		fi

		D_DEV_PART=$(cmd "$SSH_PREFIX kpartx -avs ${D_DEV_PATH} | grep -i '[nr]bd.*p2' | cut -d ' ' -f3")
		D_DM_PATH="/dev/mapper/${D_DEV_PART}"
		cmd "$SSH_PREFIX dd if=${S_DEV_PATH} of=${D_DM_PATH} bs=${OBJECT_SIZE} conv=fdatasync status=progress"
		cmd "$SSH_PREFIX mount ${D_DM_PATH} /mnt/destination"
		
}

######### DIFF SYNC FUNCTIONS #########
rbd_diff_sync () {
	NEXT=$(expr $SYNC_ID + 1)
	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${SOURCE_IMAGE}@${SYNC_PREFIX}${NEXT}"
	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  export-diff --from-snap ${SYNC_PREFIX}${SYNC_ID} ${SOURCE_IMAGE}@${SYNC_PREFIX}${NEXT} - | rbd --id ${CEPH_ID}  import-diff - ${DEST_IMAGE}"
	#cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${DEST_IMAGE}@${SYNC_PREFIX}${NEXT}"

	# clean older snaps
	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap rm ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap rm ${DEST_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"

	SYNC_ID=$NEXT
}

rsync_diff_sync () {

	if [[ "$SOURCE_TYPE" == "local" ]]; then
		cmd "umount /mnt/source"
		cmd "unlink ${IMPORT_DEV_DIR}/${SOURCE_IMAGE}"
		case "$LOCAL_SOURCE_TOOL" in
			"zfs")
				cmd "zfs destroy ${SOURCE_POOL}/vm-export"
				cmd "zfs destroy ${ZFS_SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
				quiesced_zfs_map ${SOURCE_IMAGE} ${FSFREEZE_HOST}
				;;
		esac
		cmd "ln -s ${S_DEV_PATH} ${IMPORT_DEV_DIR}/${SOURCE_IMAGE}"
		cmd "mount ${S_DEV_PATH} /mnt/source"
		cmd "rsync -avx --delete /mnt/source/ ${BRIDGE_HOST}:/mnt/destination/"
	else
		cmd "$SSH_PREFIX umount /mnt/source"
		cmd "$SSH_PREFIX unlink ${IMPORT_DEV_DIR}/${SOURCE_IMAGE}"
		cmd "$SSH_PREFIX ${RBD_MODE} unmap ${S_DEV_PATH}"
		cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap rm ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
		quiesced_rbd_map ${SOURCE_IMAGE} ${FSFREEZE_HOST}
	#	cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap create ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
	#	S_DEV_PATH=$(cmd "$SSH_PREFIX ${RBD_MODE} map --id ${CEPH_ID} --read-only ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}")
		cmd "$SSH_PREFIX ln -s ${S_DEV_PATH} ${IMPORT_DEV_DIR}/${SOURCE_IMAGE}"
		cmd "$SSH_PREFIX mount ${S_DEV_PATH} /mnt/source"
		cmd "$SSH_PREFIX rsync -avx --delete /mnt/source/ /mnt/destination/"
	fi
}

dd_diff_sync () {
	printf "Nothing to do using dd... and can't rsync beacause of mount pb.\n"
}

######### CLEAN SYNC FUNCTIONS #########
rbd_clean_sync () {
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
}

rsync_clean_sync () {
	cmd "$SSH_PREFIX umount /mnt/destination"
	cmd "$SSH_PREFIX kpartx -ds ${D_DEV_PATH}"

	if [[ "$SOURCE_TYPE" == "local" ]]; then
		cmd "umount /mnt/source"
		cmd "unlink ${IMPORT_DEV_DIR}/${SOURCE_IMAGE}"
		case "$LOCAL_SOURCE_TOOL" in
			"zfs")
				cmd "zfs destroy ${SOURCE_POOL}/vm-export"
				cmd "zfs destroy ${ZFS_SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
				;;
		esac
	else
		cmd "$SSH_PREFIX umount /mnt/source"
		cmd "$SSH_PREFIX unlink ${IMPORT_DEV_DIR}/${SOURCE_IMAGE}"
		cmd "$SSH_PREFIX ${RBD_MODE} unmap ${S_DEV_PATH}"
		cmd "$SSH_PREFIX rbd --id ${CEPH_ID}  snap rm ${SOURCE_IMAGE}@${SYNC_PREFIX}${SYNC_ID}"
	fi	
	cmd "$SSH_PREFIX unlink ${IMPORT_DEV_DIR}/${DEST_IMAGE}"
	cmd "$SSH_PREFIX ${RBD_MODE} unmap ${D_DEV_PATH}"
}

dd_clean_sync () {
	rsync_clean_sync
}


######### MAIN #########

if [[ "$CLEAN_ONLY" == "YES" ]]; then

	init_vars

	case "$IMPORT_TOOL" in
	"rsync")
		rsync_clean_sync
		;;
	"dd")
		dd_clean_sync
		;;
	*)
		rbd_clean_sync
		;;
	esac

else

	# check FSFREEZE host conenction
	if [ ! -z "$FSFREEZE_HOST" && $FSFREEZE_HOST_IS_LOCAL_VM -neq 0 ]                           # Is parameter #1 zero length?
	then
		echo "Check $FSFREEZE_HOST connectivity"  # Or no parameter passed.
		status=$(ssh -i ${FSFREEZE_HOST_KEY} -o BatchMode=yes -o ConnectTimeout=5 ${SSH_USER}@${FSFREEZE_HOST} echo ok 2>&1)

		if [[ $status == ok ]] ; then
		  echo "Connection ok"
		else
		  echo "$status: Connection impossible. be sure it is possible to connect with the command: ssh -i ${FSFREEZE_HOST_KEY} ${SSH_USER}@${FSFREEZE_HOST}"
			exit 1
		fi
	fi

	cmd "$SSH_PREFIX rbd --id ${CEPH_ID} info '${DEST_IMAGE}'"
	if [[ $? -eq 0 ]]; then
		EXISTS=YES
		read -n1 -r -p "Destination image already exists. Continue ? (y/n)" key
		printf "\n"
		if [ ! "$key" == 'y' ]; then
			exit
		fi
	else
		EXISTS=NO
	fi

	# check size
	if [[ "$SOURCE_TYPE" == "local" ]]; then
		case "$LOCAL_SOURCE_TOOL" in
			"zfs")
			#SIZE=$(cmd "zfs list -p | grep '${ZFS_SOURCE_IMAGE}' | tr -s ' ' | cut -d ' ' -f2")
			SIZE=$(cmd "zfs list -pH -o usedbydataset ${ZFS_SOURCE_IMAGE}")
			;;
		esac
	else
		SIZE=$(cmd "${SSH_PREFIX} rbd --format json --id ${CEPH_ID} info ${SOURCE_IMAGE} | grep -Po '(?<=\"size\":)[^,\"]*'")
	fi
	
	printf "Initial sync of ${SOURCE_IMAGE} ($SIZE B)\n"

	case "$IMPORT_TOOL" in
	"rsync")
		rsync_init_sync
		;;
	"dd")
		dd_init_sync
		;;
	*)
		rbd_init_sync
		;;
	esac

	read -n1 -r -p "Init ready. Continue diffs ? (ctrl-c to stop)" key
	printf "\n"

	LAST_SYNC=$(expr $(timestamp) - $LIVE_INTERVAL - 10)
	while 	[ $(expr $(timestamp) - $LAST_SYNC) -gt "$LIVE_INTERVAL" ] && 
			[ "$MAX_SYNC" -gt "0" ]; do
		LAST_SYNC=$(timestamp)
		MAX_SYNC=$(expr $MAX_SYNC - 1)
		case "$IMPORT_TOOL" in
		"rsync")
			rsync_diff_sync
			;;
		"dd")
			dd_diff_sync
			;;
		*)
			rbd_diff_sync
			;;
		esac
	done

	printf "Last sync took less than $LIVE_INTERVAL sec.\nIt is time to stop the I/O (VM) to do the last sync and be able to start the VM using the imported image.\n"
	read -n1 -r -p "I/O have been stopped? (y/c) - c for cancel and clean" key
	printf "\n"
	if [ "$key" == 'c' ]; then
		case "$IMPORT_TOOL" in
			"rsync")
				rsync_clean_sync
				;;
			"dd")
				dd_clean_sync
				;;
			*)
				rbd_clean_sync
				;;
		esac
		exit 1
	fi

	while [ ! "$key" == 'y' ]; do
		sleep 5;
		read -n1 -r -p "I/O have been stopped? (y)" key
		printf "\n"
	done

	FSFREEZE_HOST="" # don't quiesce last (machine powed off)
	case "$IMPORT_TOOL" in
	"rsync")
		rsync_diff_sync
		finalize_setup
		rsync_clean_sync
		;;
	"dd")
		dd_diff_sync
		finalize_setup
		dd_clean_sync
		;;
	*)
		rbd_diff_sync
		rbd_clean_sync
		;;
	esac

	case "$IMPORT_DEST" in
	"opennebula")
		printf "Add image in Opennebula\n"
		cmd "sudo -u ${SSH_USER} oneimage create --name ${TARGET_NAME} --source ${DEST_IMAGE} --size $SIZE -d ${TARGET_DATASTORE} --persistent"
		;;
	"cinder")
		printf "Add image in Cinder\n"
		;;
	"xenserver")
		printf "Add image in Xenserver\n"
		cmd "${SSH_PREFIX} rbd --id ${CEPH_ID} image-meta set ${DEST_IMAGE} VDI_DESCRIPTION 'virt-ceph imported from ${SOURCE_IMAGE}'"
		cmd "${SSH_PREFIX} rbd --id ${CEPH_ID} image-meta set ${DEST_IMAGE} VDI_LABEL '${TARGET_NAME}'"
		cmd "${SSH_PREFIX} xe sr-scan uuid=${TARGET_SR_UUID}"
		;;
	*)
		printf "Don't add destination to specific system\n"
		;;
	esac


fi
