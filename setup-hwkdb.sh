#!/bin/bash

pguser=postgres
dbdata=postgres-data
containername=hwkdb

set -o pipefail

if [[ "$1" == "host" ]]; then
    echo "Adding user: ${pguser} ..."
    sudo useradd -ms /bin/bash ${pguser}
    if [ $? -eq 0 ]; then
      echo "Please enter password for ${pguser}"
      sudo passwd ${pguser}
    fi

    echo "enable linger for ${pguser}"
    sudo loginctl enable-linger ${pguser}

    sudo runuser -l ${pguser} -c "wget -O ~/setup-hwkdb.sh https://raw.githubusercontent.com/hwkcld/hwkdb/main/setup-hwkdb.sh && chmod 700 ~/setup-hwkdb.sh"

    sudo runuser -l ${pguser} -c "~/setup-hwkdb.sh"
	
	echo $?
	
else
    export XDG_RUNTIME_DIR=/run/user/${UID}
    echo XDG_RUNTIME_DIR = ${XDG_RUNTIME_DIR}

    echo "create named volume for ${pguser}: ${dbdata}"
    podman volume create ${dbdata}

    echo "Download the default postgres.conf"
    wget -O ~/postgres.conf https://raw.githubusercontent.com/hwkcld/hwkdb/main/postgres.conf

    echo "Create directory for quadlet"
    mkdir -p ~/.config/containers/systemd

    echo "Download the default quadlet file"
    wget -O ~/.config/containers/systemd/hwkdb.container https://raw.githubusercontent.com/hwkcld/hwkdb/main/hwkdb.container
    
    echo Create the hwkdb service
    systemctl --user daemon-reload  

    echo "Start the service using systemd i.e. auto reload even after system restart"
    systemctl --user start hwkdb.service

    if [ $? -eq 0 ]; then
	    echo "waiting for database server ..."
	    sleep 10
        podman exec -it ${containername} psql -U ${pguser} -c "\password ${pguser};"
        if [ $? -ne 0 ]; then
		    echo "You can manually set the password again"
		fi
    else
        echo "failed."  
    fi
        
fi
