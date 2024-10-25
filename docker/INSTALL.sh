#!/bin/bash
################################################################################
# Script Name: INSTALL.sh
# Description: Install the latest version of OpenPanel
# Usage: bash <(curl -sSL https://raw.githubusercontent.com/stefanpejcic/OpenPanel/main/docker/INSTALL.sh)
# Author: Stefan Pejcic
# Created: 26.01.2024
# Last Modified: 13.06.2024
# Company: openpanel.co
# Copyright (c) OPENPANEL
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
################################################################################

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

# Defaults
CUSTOM_VERSION=false
INSTALL_TIMEOUT=1800 # 30 min
DEBUG=false
SKIP_APT_UPDATE=false
SKIP_IMAGES=false
REPAIR=false
LOCALES=true
NO_SSH=false
OVERLAY=false
IPSETS=true
SET_HOSTNAME_NOW=false
SETUP_SWAP_ANYWAY=false
SWAP_FILE="1"
SELFHOSTED_SCREENSHOTS=false
SEND_EMAIL_AFTER_INSTALL=false
SET_PREMIUM=false

# Paths
LOG_FILE="openpanel_install.log"
LOCK_FILE="/root/openpanel.lock"
OPENPANEL_DIR="/usr/local/panel/"
OPENPADMIN_DIR="/usr/local/admin/"
ETC_DIR="/etc/openpanel/"
OPENCLI_DIR="/usr/local/admin/scripts/"
OPENPANEL_ERR_DIR="/var/log/openpanel/"
TEMP_DIR="/tmp/"

# Redirect output to the log file
exec > >(tee -a "$LOG_FILE") 2>&1



#####################################################################
#                                                                   #
# START helper functions                                            #
#                                                                   #
#####################################################################

# logo
print_header() {
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
    echo -e "   ____                         _____                      _  "
    echo -e "  / __ \                       |  __ \                    | | "
    echo -e " | |  | | _ __    ___  _ __    | |__) | __ _  _ __    ___ | | "
    echo -e " | |  | || '_ \  / _ \| '_ \   |  ___/ / _\" || '_ \ / _  \| | "
    echo -e " | |__| || |_) ||  __/| | | |  | |    | (_| || | | ||  __/| | "
    echo -e "  \____/ | .__/  \___||_| |_|  |_|     \__,_||_| |_| \___||_| "
    echo -e "         | |                                                  "
    echo -e "         |_|                                   version: $version "

    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
}


install_started_message(){
    echo -e ""
    echo -e "\nStarting the installation of OpenPanel. This process will take approximately 5-10 minutes."
    echo -e "During this time, we will:"
    echo -e "- Install necessary services and tools."
    echo -e "- Create an admin account for you."
    echo -e "- Set up the firewall for enhanced security."
    echo -e "- Install needed Docker images."
    echo -e "- Set up basic hosting plans so you can start right away."
    echo -e "\nThank you for your patience. We're setting everything up for your seamless OpenPanel experience!\n"
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
    echo -e ""
}



# Display error and exit
radovan() {
    echo -e "${RED}Error: $2${RESET}" >&2
    exit $1
}


# print the command and its output if debug, else run and echo to /dev/null
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo "Running: $@"
        "$@"
    else
        "$@" > /dev/null 2>&1
    fi
}


# Get server ipv4 from ip.openpanel.co
current_ip=$(curl -s https://ip.openpanel.co || wget -qO- https://ip.openpanel.co)

# If site is not available, get the ipv4 from the hostname -I
if [ -z "$current_ip" ]; then
   # current_ip=$(hostname -I | awk '{print $1}')
    # ip addr command is more reliable then hostname - to avoid getting private ip
    current_ip=$(ip addr|grep 'inet '|grep global|head -n1|awk '{print $2}'|cut -f1 -d/)
fi




if [ "$CUSTOM_VERSION" = false ]; then
    # Fetch the latest version
    version=$(curl -s https://get.openpanel.co/version)
    if [[ $version =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
        version=$version
    else
        version="0.2.1"
    fi
fi

# print fullwidth line
print_space_and_line() {
    echo " "
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
    echo " "
}


# Progress bar script

PROGRESS_BAR_URL="https://raw.githubusercontent.com/pollev/bash_progress_bar/master/progress_bar.sh"
PROGRESS_BAR_FILE="progress_bar.sh"

wget "$PROGRESS_BAR_URL" -O "$PROGRESS_BAR_FILE" > /dev/null 2>&1

if [ ! -f "$PROGRESS_BAR_FILE" ]; then
    echo "Failed to download progress_bar.sh"
    exit 1
fi

# Source the progress bar script
source "$PROGRESS_BAR_FILE"

# Dsiplay progress bar
FUNCTIONS=(
    detect_os_and_package_manager
    update_package_manager
    install_packages
    download_skeleton_directory_from_github
    setup_openpanel
    setup_openadmin
    configure_docker
    
    setup_swap
    set_premium_features
    cleanup
    set_custom_hostname
    generate_and_set_ssl_for_panels
    verify_license
    set_system_cronjob
    setup_csf
)

TOTAL_STEPS=${#FUNCTIONS[@]}
CURRENT_STEP=0

update_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    PERCENTAGE=$(($CURRENT_STEP * 100 / $TOTAL_STEPS))
    draw_progress_bar $PERCENTAGE
}

main() {
    # Make sure that the progress bar is cleaned up when user presses ctrl+c
    enable_trapping
    
    # Create progress bar
    setup_scroll_area
    for func in "${FUNCTIONS[@]}"
    do
        # Execute each function
        $func
        update_progress
    done
    destroy_scroll_area
}




# END helper functions















































#####################################################################
#                                                                   #
# START main functions                                              #
#                                                                   #
#####################################################################



check_requirements() {
    if [ -z "$SKIP_REQUIREMENTS" ]; then

        # https://github.com/stefanpejcic/openpanel/issues/63

        architecture=$(lscpu | grep Architecture | awk '{print $2}')

        if [ "$architecture" == "aarch64" ]; then
            echo -e "${RED}Error: ARM CPU is not supported!${RESET}" >&2
            exit 1
        fi

        # check if the current user is not root
        if [ "$(id -u)" != "0" ]; then
            echo -e "${RED}Error: you must be root to execute this script.${RESET}" >&2
            exit 1
        # check if OS is MacOS
        elif [ "$(uname)" = "Darwin" ]; then
            echo -e "${RED}Error: MacOS is not currently supported.${RESET}" >&2
            exit 1
        # check if running inside a container
        elif [[ -f /.dockerenv || $(grep -sq 'docker\|lxc' /proc/1/cgroup) ]]; then
            echo -e "${RED}Error: running openpanel inside a container is not supported.${RESET}" >&2
            exit 1
        fi
        # check if python version is supported
        current_python_version=$(python3 --version 2>&1 | cut -d " " -f 2 | cut -d "." -f 1,2 | tr -d '.')
        allowed_versions=("39" "310" "311" "312" "38")
        if [[ ! " ${allowed_versions[@]} " =~ " ${current_python_version} " ]]; then
            echo -e "${RED}Error: Unsupported Python version $current_python_version. No corresponding branch available.${RESET}" >&2
            exit 1
        fi
    fi
}



parse_args() {
    show_help() {
        echo "Available options:"
        echo "  --key=<key_here>                Set the license key for OpenPanel Enterprise edition."
        echo "  --hostname=<hostname>           Set the hostname."
        echo "  --version=<version>             Set a custom OpenPanel version to be installed."
        echo "  --email=<stefan@example.net>    Set email address to receive email with admin credentials and future notifications."
        echo "  --skip-requirements             Skip the requirements check."
        echo "  --skip-panel-check              Skip checking if existing panels are installed."
        echo "  --skip-apt-update               Skip the APT update."
        echo "  --overlay2                      Enable overlay2 storage driver instead of device-mapper."
        echo "  --skip-firewall                 Skip UFW setup UFW - Only do this if you will set another Firewall manually!"
        echo "  --skip-images                   Skip installing openpanel/nginx and openpanel/apache docker images."
        echo "  --skip-blacklists               Do not set up IP sets and blacklists."
        echo "  --skip-ssl                      Skip SSL setup."
        echo "  --with_modsec                   Enable ModSecurity for Nginx."
        echo "  --ips                           Whiteliste IP addresses of OpenPanel Support Team."
        echo "  --no-ssh                        Disable port 22 and whitelist the IP address of user installing the panel."
        echo "  --enable-ftp                    Install FTP (experimental)."
        echo "  --enable-mail                   Install Mail (experimental)."
        echo "  --post_install=<path>           Specify the post install script path."
        echo "  --screenshots=<url>             Set the screenshots API URL."
        echo "  --swap=<2>                      Set space in GB to be allocated for SWAP."
        echo "  --debug                         Display debug information during installation."
        echo "  --repair                        Retry and overwrite everything."
        echo "  -h, --help                      Show this help message and exit."
    }





while [[ $# -gt 0 ]]; do
    case $1 in
        --key=*)
            SET_PREMIUM=true
            license_key="${1#*=}"
            ;;
        --hostname=*)
            SET_HOSTNAME_NOW=true
            new_hostname="${1#*=}"
            ;;
        --skip-requirements)
            SKIP_REQUIREMENTS=true
            ;;
        --skip-panel-check)
            SKIP_PANEL_CHECK=true
            ;;
        --skip-apt-update)
            SKIP_APT_UPDATE=true
            ;;
        --repair)
            REPAIR=true
            SKIP_PANEL_CHECK=true
            SKIP_REQUIREMENTS=true
            ;;
        --overlay2)
            OVERLAY=true
            ;;
        --skip-firewall)
            SKIP_FIREWALL=true
            ;;
        --skip-images)
            SKIP_IMAGES=true
            ;;
        --skip-blacklists)
            IPSETS=false
            ;;
        --skip-ssl)
            SKIP_SSL=true
            ;;
        --with_modsec)
            MODSEC=true
            ;;
        --debug)
            DEBUG=true
            ;;
        --ips)
            SUPPORT_IPS=true
            ;;
        --no-ssh)
            NO_SSH=true
            ;;
        --enable-ftp)
            INSTALL_FTP=true
            ;;
        --enable-mail)
            INSTALL_MAIL=true
            ;;
        --post_install=*)
            post_install_path="${1#*=}"
            ;;
        --version=*)
            CUSTOM_VERSION=true
            version="${1#*=}"
            ;;
        --swap=*)
            SETUP_SWAP_ANYWAY=true
            SWAP="${1#*=}"
            ;;
        --email=*)
            SEND_EMAIL_AFTER_INSTALL=true
            EMAIL="${1#*=}"
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
    shift
done

}






detect_installed_panels() {
    if [ -z "$SKIP_PANEL_CHECK" ]; then
        declare -A paths=(
            ["/usr/local/panel"]="You already have OpenPanel installed. ${RESET}\nInstead, did you want to update? Run ${GREEN}'opencli update --force' to update OpenPanel."
            ["/usr/local/cpanel/whostmgr"]="cPanel WHM is installed. OpenPanel only supports servers without any hosting control panel installed."
            ["/opt/psa/version"]="Plesk is installed. OpenPanel only supports servers without any hosting control panel installed."
            ["/usr/local/psa/version"]="Plesk is installed. OpenPanel only supports servers without any hosting control panel installed."
            ["/usr/local/CyberPanel"]="CyberPanel is installed. OpenPanel only supports servers without any hosting control panel installed."
            ["/usr/local/directadmin"]="DirectAdmin is installed. OpenPanel only supports servers without any hosting control panel installed."
            ["/usr/local/cwpsrv"]="CentOS Web Panel (CWP) is installed. OpenPanel only supports servers without any hosting control panel installed."
            ["/usr/local/httpd"]="Apache WebServer is already installed. OpenPanel only supports servers without any webservers installed."
            ["/usr/local/apache2"]="Apache WebServer is already installed. OpenPanel only supports servers without any webservers installed."
            ["/usr/sbin/httpd"]="Apache WebServer is already installed. OpenPanel only supports servers without any webservers installed."
            ["/usr/lib/nginx"]="Nginx WebServer is already installed. OpenPanel only supports servers without any webservers installed."
        )

        for path in "${!paths[@]}"; do
            if [ -d "$path" ] || [ -e "$path" ]; then
                radovan 1 "${paths[$path]}"
            fi
        done

        echo -e "${GREEN}No currently installed hosting control panels or webservers found. Proceeding with the installation process.${RESET}"
    fi
}



check_lock_file_age() {
    # Use flock to create a lock or exit if the lock is already held
    exec 200>"$LOCK_FILE"
    if flock -n 200; then
        # Inside the lock
        echo "OpenPanel installation started at: $(date)"
    else
        echo -e "${RED}Another instance is running. Exiting.${RESET}"
        exit 1
    fi
}



setup_csf() {
    if [ -z "$SKIP_FIREWALL" ]; then
        echo "Setting up the firewall.."
  
  
  read_email_address() {
      email=$(grep -E "^e-mail=" /etc/openpanel/openpanel/conf/openpanel.config | cut -d "=" -f2)
      echo "$email"
  }
  
    
  install_csf() {
      wget https://download.configserver.com/csf.tgz
      tar -xzf csf.tgz
      rm csf.tgz
      cd csf
      sh install.sh
  }
  
  edit_csf_conf() {
      sed -i 's/TESTING = "1"/TESTING = "0"/' /etc/csf/csf.conf
      sed -i 's/ETH_DEVICE_SKIP = ""/ETH_DEVICE_SKIP = "docker0"/' /etc/csf/csf.conf
      sed -i 's/DOCKER = "0"/DOCKER = "1"/' /etc/csf/csf.conf
  }
  
  set_csf_email_address() {
      email_address=$(read_email_address)
      if [[ -n "$email_address" ]]; then
          sed -i "s/LF_ALERT_TO = \"\"/LF_ALERT_TO = \"$email_address\"/" /etc/csf/csf.conf
      fi
  }
  
  
  read_email_address
  install_csf
  edit_csf_conf
  set_csf_email_address
  csf -r
  systemctl enable csf


}




set_premium_features(){
 if [ "$SET_HOSTNAME_NOW" = true ]; then
    echo "Setting OpenPanel enterprise version license key $license_key"
    opencli config update key "$license_key"
 fi
}



install_packages(){

debug_log sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf

packages=("docker.io" "default-mysql-client" "bind9" "jc" "certbot" "python3-certbot-nginx")

update-ca-certificates > /dev/null 2>&1

        for package in "${packages[@]}"; do
            echo -e "Installing ${GREEN}$package${RESET}"
            debug_log apt-get -qq install "$package" -y
        done   

}






download_skeleton_directory_from_github(){
    echo "Downloading configuration files to ${ETC_DIR}"
    debug_log git clone https://github.com/stefanpejcic/openpanel-configuration /etc/openpanel > /dev/null 2>&1
}



set_custom_hostname(){
        if [ "$SET_HOSTNAME_NOW" = true ]; then
            # Check if the provided hostname is a valid FQDN
            if [[ $new_hostname =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                # Check if PTR record is set to the provided hostname
                ptr=$(dig +short -x $current_ip)
                if [ "$ptr" != "$new_hostname." ]; then
                    echo "Warning: PTR record is not set to $new_hostname"
                fi
                
                # Check if A record for provided hostname points to server IP
                a_record_ip=$(dig +short $new_hostname)
                if [ "$a_record_ip" != "$current_ip" ]; then
                    echo "WARNING: A record for $new_hostname does not point to server IP: $current_ip"
                    echo "After pointing the domain run this command to set domain for panel: opencli config update force_domain $new_hostname"
                else
                    opencli config update force_domain "$new_hostname"
                fi

            else
                echo "Hostname provided: $new_hostname is not a valid FQDN, OpenPanel will use IP address $current_ip for access."
            fi

            # Set the provided hostname as the system hostname
            hostnamectl set-hostname $new_hostname
        fi
}            




set_email_address_and_email_admin_logins(){
        if [ "$SEND_EMAIL_AFTER_INSTALL" = true ]; then
            # Check if the provided email is valid
            if [[ $EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                echo "Setting email address $EMAIL for notifications"
                opencli config update email "$EMAIL"
                # Send an email alert
                
                generate_random_token_one_time_only() {
                    local config_file="${OPENPANEL_DIR}conf/panel.config"
                    TOKEN_ONE_TIME="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 64)"
                    local new_value="mail_security_token=$TOKEN_ONE_TIME"
                    sed -i "s|^mail_security_token=.*$|$new_value|" "${OPENPANEL_DIR}conf/panel.config"
                }

                
                email_notification() {
                  local title="$1"
                  local message="$2"
                  generate_random_token_one_time_only
                  TRANSIENT=$(awk -F'=' '/^mail_security_token/ {print $2}' "${OPENPANEL_DIR}conf/panel.config")
                                
                  SSL=$(awk -F'=' '/^ssl/ {print $2}' "${OPENPANEL_DIR}conf/panel.config")
                
                # Determine protocol based on SSL configuration
                if [ "$SSL" = "yes" ]; then
                  PROTOCOL="https"
                else
                  PROTOCOL="http"
                fi
                
                # Send email using appropriate protocol
                curl -k -X POST "$PROTOCOL://127.0.0.1:2087/send_email" -F "transient=$TRANSIENT" -F "recipient=$EMAIL" -F "subject=$title" -F "body=$message"
                
                }

                server_hostname=$(hostname)
                email_notification "OpenPanel successfully installed" "OpenAdmin URL: http://$server_hostname:2087/ | username: admin | password: $admin_password"
            else
                echo "Address provided: $EMAIL is not a valid email address. Admin login credentials and future notifications will not be sent."
            fi
        fi
}        





configure_docker() {

    apt-get install docker.io docker -y
    
    docker_daemon_json_path="/etc/docker/daemon.json"
    debug_log mkdir -p $(dirname "$docker_daemon_json_path")

    if [ "$OVERLAY" = true ]; then
        debug_log "Setting 'overlay2' as the default storage driver for Docker.."
        cp ${ETC_DIR}docker/overlay2/daemon.json  > "$docker_daemon_json_path"
    else
        debug_log "Setting 'devicemapper' as the default storage driver for Docker.."
        cp ${ETC_DIR}docker/devicemapper/daemon.json  > "$docker_daemon_json_path"
    fi

    echo -e "${GREEN}Docker is configured.${RESET}"
    debug_log systemctl daemon-reload
    systemctl restart docker
}



docker_compose_up(){




# install docker and docker compose
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.27.1/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# CHECK WITH 
#docker compose version



# download conf files first
git clone https://github.com/stefanpejcic/openpanel-configuration /etc/openpanel > /dev/null 2>&1

# generate random password for mysql
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 -hex 9)
echo "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" >> .env

# save it to /etc/my.cnf
ln -s /etc/openpanel/mysql/db.cnf /etc/my.cnf
sed -i 's/password = .*/password = '"${MYSQL_ROOT_PASSWORD}"'/g' ${ETC_DIR}mysql/db.cnf


# start the stack
docker compose up -d

}





set_system_cronjob(){
    echo "Setting cronjobs.."
    mv ${ETC_DIR}cron /etc/cron.d/openpanel
    chown root:root /etc/cron.d/openpanel
    chmod 0600 /etc/cron.d/openpanel
}


cleanup() {
    echo "Cleaning up.."
    # https://www.faqforge.com/linux/fixed-ubuntu-apt-get-upgrade-auto-restart-services/
    sed -i 's/$nrconf{restart} = '"'"'a'"'"';/#$nrconf{restart} = '"'"'i'"'"';/g' /etc/needrestart/needrestart.conf
}




generate_and_set_ssl_for_panels() {
    if [ -z "$SKIP_SSL" ]; then
        echo "Checking if SSL can be generated for the server hostname.."
        debug_log opencli ssl-hostname
    fi
}



run_custom_postinstall_script() {
    if [ -n "$post_install_path" ]; then
        # run the custom script
        echo " "
        echo "Running post install script.."
        debug_log "https://dev.openpanel.co/customize.html#After-installation"
        debug_log bash $post_install_path
    fi
}



verify_license() {
  # LEGACY, WILL BE REMOVED
    debug_log "echo Current time: $(date +%T)"
    server_hostname=$(hostname)
    license_data='{"hostname": "'"$server_hostname"'", "public_ip": "'"$current_ip"'"}'
    response=$(curl -s -X POST -H "Content-Type: application/json" -d "$license_data" https://api.openpanel.co/license-check)
    debug_log "echo Checking OpenPanel license for IP address: $current_ip"
    debug_log "echo Response: $response"
}

send_install_log(){
    # Restore normal output to the terminal, so we dont save generated admin password in log file!
    exec > /dev/tty
    exec 2>&1
    opencli report --public >> "$LOG_FILE"
    curl -F "file=@/root/$LOG_FILE" http://support.openpanel.co/install_logs.php
    # Redirect again stdout and stderr to the log file
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
}


rm_helpers(){
    rm -rf $PROGRESS_BAR_FILE
}



setup_swap(){
    # Function to create swap file
    create_swap() {
        fallocate -l ${SWAP_FILE}G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo "/swapfile   none    swap    sw    0   0" >> /etc/fstab
    }

    # Check if swap space already exists
    if [ -n "$(swapon -s)" ]; then
        echo "ERROR: Skipping creating swap space as there already exists a swap partition."
        return
    fi

    # Check if we should set up swap anyway
    if [ "$SETUP_SWAP_ANYWAY" = true ]; then
        create_swap
    else
        # Only create swap if RAM is less than 8GB
        memory_kb=$(grep 'MemTotal' /proc/meminfo | awk '{print $2}')
        memory_gb=$(awk "BEGIN {print $memory_kb/1024/1024}")

        if [ $(awk "BEGIN {print ($memory_gb < 8)}") -eq 1 ]; then
            create_swap
        else
            echo "Total available memory is ${memory_gb}GB, skipping creating swap file."
        fi
    fi
}








support_message() {
    echo ""
    echo "🎉 Welcome aboard and thank you for choosing OpenPanel! 🎉"
    echo ""
    echo "Your journey with OpenPanel has just begun, and we're here to help every step of the way."
    echo ""
    echo "To get started, check out our Getting Started guide:"
    echo "👉 https://openpanel.co/docs/admin/intro/#post-install-steps"
    echo ""
    echo "Need assistance or looking to learn more? We've got you covered:"
    echo ""
    echo "📚 Admin Docs: Dive into our comprehensive documentation for all things OpenPanel:"
    echo "👉 https://openpanel.co/docs/admin/intro/"
    echo ""
    echo "💬 Forums: Join our community forum to ask questions, share tips, and connect with fellow admins:"
    echo "👉 https://community.openpanel.co/"
    echo ""
    echo "🎮 Discord: For real-time chat and support, hop into our Discord server:"
    echo "👉 https://discord.openpanel.co/"
    echo ""
    echo "We're thrilled to have you with us. Let's make something amazing together! 🚀"
    echo ""
}



success_message() {

    echo -e "${GREEN}OpenPanel installation complete.${RESET}"
    echo ""

    # Restore normal output to the terminal, so we dont save generated admin password in log file!
    exec > /dev/tty
    exec 2>&1

    # for 0.1.9
    echo "$version" > $OPENPANEL_DIR/version
    
    opencli admin
    echo "Username: admin"
    echo "aditya1010: $admin_password"
    echo " "
    print_space_and_line
    
    # added in 0.2.0
    # email to user the new logins
    set_email_address_and_email_admin_logins

    # Redirect again stdout and stderr to the log file
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1

}

# END main functions







#####################################################################
#                                                                   #
# START main script execution                                       #
#                                                                   #
#####################################################################

print_header

parse_args "$@"

check_requirements

detect_installed_panels

check_lock_file_age

install_started_message

main

send_install_log

rm_helpers

print_space_and_line

support_message

print_space_and_line

success_message

run_custom_postinstall_script


# END main script execution



# added in 0.1.9
cp ${ETC_DIR}ssh/admin_welcome.sh /etc/profile.d/welcome.sh
chmod +x /etc/profile.d/welcome.sh  
