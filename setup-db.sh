#!/bin/bash

# Default values
HOST_MODE=false
IMAGE=""
MACHINE=""

# Function to display usage
usage() {
    echo
    echo "Usage: $0 [-a] [-i image] [-m machine]"
    echo "  -a          Specify script is run from admin"
    echo "  -i image    Specify the image name"
    echo "  -m machine  Specify the machine name e.g. cpu1-2gb"
    echo
    exit 1
}

# Show usage if no arguments provided
if [ $# -eq 0 ]; then
    usage
fi

# Parse command-line options
# a - flag with no argument
# i: - option that requires an argument (the colon means "takes a value")
# m: - option that requires an argument
while getopts "ai:m:" opt; do
    case $opt in
        a)
            HOST_MODE=true
            ;;
        i)
            IMAGE="$OPTARG"
            ;;
        m)
            MACHINE="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            ;;
    esac
done

# Shift past the parsed options
shift $((OPTIND-1))

# Validate required parameters
if [ -z "$IMAGE" ]; then
    echo "Error: -i image is required" >&2
    usage
fi

if [ -z "$MACHINE" ]; then
    echo "Error: -m machine is required" >&2
    usage
fi

# Your script logic here
#echo "Host: ${HOST_MODE}"
#echo "Image: ${IMAGE}"
#echo "Machine: ${MACHINE}"

OS_USER=dbuser
REPO_SOURCE=https://raw.githubusercontent.com/hwkcld/hwkdb/main
SETUP_SCR=setup-db.sh
CTN_CONFIG=postgresql.conf

set -o pipefail

if [ "$HOST_MODE" = true ]; then

    echo "Adding user: ${OS_USER} ..."
    sudo useradd -ms /bin/bash ${OS_USER}
    if [ $? -eq 0 ]; then
      echo "Please enter password for new user: ${OS_USER}"
      sudo passwd ${OS_USER}
    fi

    echo "enable linger for ${OS_USER}"
    sudo loginctl enable-linger ${OS_USER}

    sudo runuser -l ${OS_USER} -c "wget -O ~/${SETUP_SCR} ${REPO_SOURCE}/${SETUP_SCR} && chmod 700 ~/${SETUP_SCR} && ~/${SETUP_SCR} -i ${IMAGE} -m ${MACHINE}"

    echo "Status: $?"

else

    OCI_IMAGE="docker.io/hwkcld/${IMAGE}"

    podman pull docker.io/library/busybox:latest
    if [[ $? -ne 0 ]]; then
        echo "Failed downloading busybox."
        exit 1
    fi

    podman pull ${OCI_IMAGE}
    if [[ $? -ne 0 ]]; then
        echo "Failed downloading ${OCI_IMAGE}."
        exit 1
    fi

    # Get unique name for new container from podman
    podman run -d busybox \
        && CONTAINER_NAME=$(podman ps -a --filter "ancestor=busybox:latest" --sort created --format "{{.Names}}" | tail -1) \
        && podman rm ${CONTAINER_NAME}

    MOUNT_DATA=${CONTAINER_NAME}-data
    MOUNT_LOGS=${CONTAINER_NAME}-logs
    CONFIG_PATH=${HOME}/${CONTAINER_NAME}
    QUADLET_PATH=${HOME}/.config/containers/systemd

    export XDG_RUNTIME_DIR=/run/user/${UID}
    echo "XDG_RUNTIME_DIR = ${XDG_RUNTIME_DIR}"

    echo "create named volume for ${OS_USER}: ${MOUNT_DATA}"
    podman volume create ${MOUNT_DATA}

    echo "create named volume for ${OS_USER}: ${MOUNT_LOGS}"
    podman volume create ${MOUNT_LOGS}

    echo "Create directory for config files"
    mkdir -p ${CONFIG_PATH}

    echo "Download the default ${CTN_CONFIG}"
    srcfile="${REPO_SOURCE}/${MACHINE}/${CTN_CONFIG}"

    wget -O ${CONFIG_PATH}/${CTN_CONFIG} ${srcfile}
    if [[ $? -ne 0 ]]; then
        echo "Error downloading ${srcfile}."
        exit 1
    fi

    echo "Create directory for quadlet"
    mkdir -p ${QUADLET_PATH}

    quadlet_template=quadlet.template
    echo "Download the default ${quadlet_template}"
    srcfile="${REPO_SOURCE}/${MACHINE}/${quadlet_template}"

    quadlet_file=${QUADLET_PATH}/${CONTAINER_NAME}.container
    
    wget -O ${quadlet_file} ${srcfile}
    if [[ $? -ne 0 ]]; then
        echo "Error downloading ${srcfile}."
        exit 1
    fi

    sed -i -e "s|%OCI_IMAGE%|${OCI_IMAGE}|g" \
    -e "s|%CONTAINER_NAME%|${CONTAINER_NAME}|g" \
    -e "s|%MOUNT_DATA%|${MOUNT_DATA}|g" \
    -e "s|%MOUNT_LOGS%|${MOUNT_LOGS}|g" \
    -e "s|%CONFIG_PATH%|${CONFIG_PATH}|g" \
    ${quadlet_file}

    echo "Create the ${CONTAINER_NAME} service"
    systemctl --user daemon-reload

    echo "Start the service using systemd i.e. auto reload even after system restart"
    echo -e "\n" | systemctl --user start ${CONTAINER_NAME}.service
    if [[ $? -ne 0 ]]; then
        echo "Failed starting server"
        exit 1
    fi

fi
