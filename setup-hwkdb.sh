#!/bin/bash

pguser=postgres
dbdata=postgres-data
dblogs=postgres-logs
containername=hwkdb

set -o pipefail

if [[ "$1" == "host" ]]; then

    if [[ "$2" == "" ]]; then
       echo "Please specify the machine type e.g. cpu1-2gb"
       exit 1
    fi

    echo "Adding user: ${pguser} ..."
    sudo useradd -ms /bin/bash ${pguser}
    if [ $? -eq 0 ]; then
      echo "Please enter password for new user: ${pguser}"
      sudo passwd ${pguser}
    fi

    echo "enable linger for ${pguser}"
    sudo loginctl enable-linger ${pguser}

    sudo runuser -l ${pguser} -c "wget -O ~/setup-hwkdb.sh https://raw.githubusercontent.com/hwkcld/hwkdb/main/setup-hwkdb.sh && chmod 700 ~/setup-hwkdb.sh && ~/setup-hwkdb.sh $2"

    # sudo runuser -l ${pguser} -c "~/setup-hwkdb.sh $2"

    echo "Status: $?"

else

    if [[ "$1" == "" ]]; then
       echo "Please specify the machine type e.g. cpu1-2gb"
       exit 1
    fi

    machine=$1
    export XDG_RUNTIME_DIR=/run/user/${UID}
    echo "XDG_RUNTIME_DIR = ${XDG_RUNTIME_DIR}"

    echo "create named volume for ${pguser}: ${dbdata}"
    podman volume create ${dbdata}

    echo "create named volume for ${pguser}: ${dblogs}"
    podman volume create ${dblogs}

    echo "Download the default postgresql.conf"
    configfile="https://raw.githubusercontent.com/hwkcld/hwkdb/main/${machine}/postgresql.conf"
    wget -O ~/postgresql.conf ${configfile}
    if [[ $? -ne 0 ]]; then
        echo "Cannot locate ${configfile}."
        exit 1
    fi

    echo "Create directory for quadlet"
    mkdir -p ~/.config/containers/systemd

    echo "Download the default quadlet file"
    configfile="https://raw.githubusercontent.com/hwkcld/hwkdb/main/${machine}/${containername}.container"
    wget -O ~/.config/containers/systemd/hwkdb.container ${configfile}
    if [[ $? -ne 0 ]]; then
        echo "Cannot locate ${configfile}."
        exit 1
    fi

    echo "Create the ${containername} service"
    systemctl --user daemon-reload

    echo "Start the service using systemd i.e. auto reload even after system restart"
    echo -e "\n" | systemctl --user start ${containername}.service

    #if [ $? -eq 0 ]; then
        # 
        # echo "waiting for database server ..."
        # sleep 10
        # podman exec -it ${containername} psql -U ${pguser} -c "\password ${pguser};"
        #if [ $? -ne 0 ]; then
        #    echo "You can manually set the password again"
        #fi
    #else
        #echo "failed."
    #fi
fi
