#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "[-] This script must be run as root." 
    exit 0
else
    export SCRUMMAGE_IP="localhost"
    export SCRUMMAGE_PORT=5000
    export DEBIAN_FRONTEND=noninteractive
    export POETRY_HOME=/opt/poetry
    export POETRY_VIRTUALENVS_IN_PROJECT=true
    export PATH="$POETRY_HOME/bin:$PATH"
    apt update
    apt install software-properties-common -y
    apt install -y python3-distutils python3-distutils-extra postgresql postgresql-contrib build-essential wget unzip git openssl
    service postgresql start
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt install ./google-chrome-stable_current_amd64.deb -y
    LINE=$(printf %"$COLUMNS"s | tr " " "-")

    echo "[+] Creating protected directory."
    if [ ! -d "../app/static/protected" ]; then
        mkdir ../app/static/protected
    fi
    mkdir ../app/static/protected/output
    mkdir ../app/static/protected/screenshots
    echo "[+] Changing owner of protected directory to user $SUDO_USER."
    chown $SUDO_USER:$SUDO_USER ../app/static/protected
    chown $SUDO_USER:$SUDO_USER ../app/static/protected/output
    chown $SUDO_USER:$SUDO_USER ../app/static/protected/screenshots
    chmod -R 770 ../app/static/protected
    echo "[+] Obtaining Chrome Driver."
    mkdir chrome_dev
    cd ./chrome_dev
    LatestVersions=$(curl -X GET "https://chromedriver.chromium.org/downloads" | grep -oP "(https\:\/\/chromedriver\.storage\.googleapis\.com\/index\.html\?path\=[0-9\.]+\/)" | sort -u)
    for lv in ${LatestVersions[$i]}; do
        if [[ $lv == *"$GoogleChromeVersion"* ]]; then
            ShortLV=$(echo "$lv" | awk -F "=" '{print $2}' | awk -F "/" '{print $1}')
            wget "https://chromedriver.storage.googleapis.com/$ShortLV/chromedriver_linux64.zip"
            if [ -f "chromedriver_linux64.zip" ]; then
                echo "[+] Unzipping chromedriver_linux64.zip."
                unzip chromedriver_linux64.zip
                if [ -f "chromedriver" ]; then
                    echo "[+] Moving the unzipped chromedriver binary to the /usr/bin directory."
                    mv ./chromedriver /usr/bin/chromedriver
                else
                    echo "[-] Failed to locate the chromedriver file."
                    exit 0
                fi
            else
                echo "[-] Failed to locate the chromedriver_linux64.zip file."
                exit 0
            fi
            echo "[i] Cleaning up."
            rm chromedriver_linux64.zip
            break
        fi
    done
    cd ..

    echo "[+] Setting up python3 dependencies."
    echo $LINE
    curl -sSL https://install.python-poetry.org/ | python3 -
    poetry self update
    poetry install
    echo $LINE
    echo "[+] Dependency installation complete. Configuring."
    echo $LINE

    DISK_UUID=$(blkid -s UUID -o value /dev/$(lsblk -io KNAME | grep "sd" | head -n 1))

    if [ -z $DISK_UUID ]; then
        DISK_UUID="UBQKry-4Hdy-LvA1-33n4-otfL-OvAH-C2sY8f"
    fi
    
    echo "[+] Exporting disk_uuid, database, user, passwd variables."
    echo "export DISK_UUID=$DISK_UUID" >> ~/.bashrc
    export DISK_UUID=$DISK_UUID
    export POSTGRES_IP="localhost"
    export POSTGRES_PORT=5432
	  export DATABASE="scrummage"
    export USER="scrummage"
    export PASSWD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n 1)
    echo "[i] Done!"

    # Change below value to "production" for prod environments.
    FLASK_ENVIRONMENT="development"
    echo "export FLASK_ENV=$FLASK_ENVIRONMENT" >> ~/.bashrc
    echo "[+] Environment variable added to startup."

    sudo -u postgres psql -c "CREATE DATABASE $DATABASE;"
    sudo -u postgres psql -c "CREATE USER $USER WITH ENCRYPTED PASSWORD '$PASSWD';"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DATABASE TO $USER;"
    echo "[+] Database has been created with the following details, please retain these for later."    

    PRINT_DATABASE="Database: $DATABASE"
    PRINT_USER="Username: $USER"
    PRINT_PASSWD="Password: $PASSWD"
    echo "Database Details:"
    echo $PRINT_DATABASE
    echo $PRINT_USER
    echo $PRINT_PASSWD
    echo $LINE

    PRIVATE_KEY="../certs/privateKey.key"
    CERTIFICATE_CRT="../certs/certificate.crt"
    API_SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-64} | head -n 1)
    export PRIVATE_KEY=$PRIVATE_KEY
    export CERTIFICATE_CRT=$CERTIFICATE_CRT
    export API_SECRET=$API_SECRET
    
    echo "[+] Generating JSON configuration for the web application."
    poetry run python3 ./support_files/generate_configuration_files.py
    echo "[+] poetry lefutott."
   
    chown $SUDO_USER:$SUDO_USER ../app/plugins/common/config/config.config
    chmod 770 ../app/plugins/common/config/config.config
    chown $SUDO_USER:$SUDO_USER ../app/plugins/common/config/db.json
    chmod 770 ../app/plugins/common/config/db.json
    echo $LINE

    pushd support_files

    echo "[+] Creating Tables using Create_Tables.py"
    poetry run python3 ./Create_Tables.py
    popd
    echo $LINE

    echo "[+] Creating Admin user using Create_User.py"
    echo $LINE
    pushd support_files
    ADMIN_USER="admin"
    ADMIN_PASSWD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w 30 | head -n 1)
    poetry run python3 ./Create_User.py -u $ADMIN_USER -p $ADMIN_PASSWD -a True -b False
    popd
    echo $LINE
    echo "[+] Admin user created, user details:"
    ADMIN_USER="Username: $ADMIN_USER"
    ADMIN_PASSWD="Password: $ADMIN_PASSWD"
    echo $ADMIN_USER
    echo $ADMIN_PASSWD
    echo $LINE
    echo "[+] Setting up Self-Signed Certificates. Creating Private Key: $PRIVATE_KEY and Certificate File: $CERTIFICATE_CRT. If you want to replace these, please do so in the ../certs directory"
    mkdir ../certs
    #Change to your company details
    country=AU
    state=NSW
    locality=Sydney
    commonname=$(domainname)
    organization=Scrummage
    organizationalunit=Scrummage
    email=Scrummage@Scrummage.com

    if [ -z $commonname ]; then
        commonname=Scrummage
    fi

    openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout $PRIVATE_KEY -out $CERTIFICATE_CRT -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email"
    echo "[+] Script finished."
fi
