#!/bin/bash

# Default values
HOST_MODE=false
IMAGE=""
MACHINE=""

# Function to display usage
usage() {
    echo
    echo "Usage: $0 [-h] [-i image] [-m machine]"
    echo "  -h          Specify script is run from host"
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
# h - flag with no argument
# i: - option that requires an argument (the colon means "takes a value")
# m: - option that requires an argument
while getopts "hi:m:" opt; do
    case $opt in
        h)
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

# OCI_IMAGE="docker.io/library/postgres:17"
OCI_IMAGE="docker.io/hwkcld/${IMAGE}"
OS_USER=dbuser

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

    sudo runuser -l ${OS_USER} -c "wget -O ~/setup-db.sh https://raw.githubusercontent.com/hwkcld/hwkdb/main/setup-db.sh && chmod 700 ~/setup-db.sh && ~/setup-db.sh -i ${IMAGE} -m ${MACHINE}"

    echo "Status: $?"

else

    podman pull docker.io/library/busybox
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
        && podman rm $CONTAINER_NAME

    MOUNT_DATA=$CONTAINER_NAME-data
    MOUNT_LOGS=$CONTAINER_NAME-logs
    CONTAINER_CONFIG=${HOME}/${CONTAINER_NAME}

    export XDG_RUNTIME_DIR=/run/user/${UID}
    echo "XDG_RUNTIME_DIR = ${XDG_RUNTIME_DIR}"

    echo "create named volume for ${OS_USER}: ${MOUNT_DATA}"
    podman volume create ${MOUNT_DATA}

    echo "create named volume for ${OS_USER}: ${MOUNT_LOGS}"
    podman volume create ${MOUNT_LOGS}


    echo "Download the default postgresql.conf"
    configfile="https://raw.githubusercontent.com/hwkcld/hwkdb/main/${MACHINE}/postgresql.conf"
    
    mkdir -p ${CONTAINER_CONFIG}
    wget -O ${CONTAINER_CONFIG}/postgresql.conf ${configfile}
    if [[ $? -ne 0 ]]; then
        echo "Error downloading ${configfile}."
        exit 1
    fi

    echo "Create directory for quadlet"
    mkdir -p ~/.config/containers/systemd

    echo "Download the default quadlet template"
    configfile="https://raw.githubusercontent.com/hwkcld/hwkdb/main/${MACHINE}/quadlet.template"
    localconfig="${HOME}/.config/containers/systemd/${CONTAINER_NAME}.container"
    wget -O $localconfig ${configfile}
    if [[ $? -ne 0 ]]; then
        echo "Error downloading ${configfile}."
        exit 1
    fi

    sed -i -e "s|%OCI_IMAGE%|${OCI_IMAGE}|g" \
    -e "s|%CONTAINER_NAME%|${CONTAINER_NAME}|g" \
    -e "s|%MOUNT_DATA%|${MOUNT_DATA}|g" \
    -e "s|%MOUNT_LOGS%|${MOUNT_LOGS}|g" \
    -e "s|%CONTAINER_CONFIG%|${CONTAINER_CONFIG}|g" \
    $localconfig

    echo "Create the ${CONTAINER_NAME} service"
    systemctl --user daemon-reload

    echo "Start the service using systemd i.e. auto reload even after system restart"
    echo -e "\n" | systemctl --user start ${CONTAINER_NAME}.service
    if [[ $? -ne 0 ]]; then
        echo "Failed starting server"
        exit 1
    fi

    #echo "Waiting for server ... "
    #sleep 10
    
    # Create application user with CREATEDB permission
    #echo "Creating application user ... "
    #podman exec -it ${CONTAINER_NAME} psql -U postgres -c "CREATE USER ${appuser} WITH PASSWORD 'mypass' CREATEDB;"
    #echo "Creating application database ... "
    #podman exec -it ${CONTAINER_NAME} psql -U postgres -c "CREATE DATABASE ${appuser};" 
    #echo "Assigning application database to application user ... "
    #podman exec -it ${CONTAINER_NAME} psql -U postgres -c "ALTER DATABASE ${appuser} OWNER TO ${appuser};"

    #if [ $? -eq 0 ]; then
        # 
        # echo "waiting for database server ..."
        # sleep 10
        # podman exec -it ${CONTAINER_NAME} psql -U ${pguser} -c "\password ${pguser};"
        #if [ $? -ne 0 ]; then
        #    echo "You can manually set the password again"
        #fi
    #else
        #echo "failed."
    #fi
fi
