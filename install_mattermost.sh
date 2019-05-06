#!/bin/bash
# date: 06/05/2019 (D/m/Y)
# version: v1.1
# creator: unixx.io

# version variables
mattermost_version="5.10.0"

# mattermost variables
mattermost_system_user="mattermost"
mattermost_mysql_user="mattermost"
mattermost_mysql_database="mattermost_db01"
nginx_hostname="$1"

# check if script is executed as root
myuid="$(/usr/bin/id -u)"
if [[ "${myuid}" != 0 ]]; then
    echo -e "\n[ Error ] This script must be run as root.\n"
    exit 0;
fi

# check if the nginx_hostname variable is not empty
if [[ "${nginx_hostname}" = "" ]]; then
    echo -e "\n[ Error ] Please enter a domain for mattermost. (Example: mattermost.yourdomain.com)\n"
    exit
fi

# prompt to accept before continue
clear
echo ""
echo "We are now going to install Mattermost ${mattermost_version}, an open source, self-hosted Slack-alternative."
echo "This will also install MySQL and Nginx."
echo ""
echo "#########################################################################"
echo "#                                                                       #"
echo "# DO NOT USE THIS SCRIPT IF YOU ALREADY HAVE MYSQL AND NGINX INSTALLED! #"
echo "#                                                                       #"
echo "#########################################################################"
echo ""
read -p "Are you sure you want to continue (y/n)? " choice
case "$choice" in
  y|Y ) echo "" && echo "Installation can take a few minutes, please wait...";;
  n|N ) echo "" && exit;;
  * ) echo "Invalid option";;
esac

# first install pwgen mysql and nginx with let's encrypt support
apt-get update > /dev/null 2>&1
#apt-get install pwgen mysql-server mysql-client nginx -y > /dev/null 2>&1
apt-get install pwgen mysql-server mysql-client python-certbot-nginx -y > /dev/null 2>&1

# set root mysql password (and disable password-less socket auth)
mysql_password=`pwgen -s -1 16`

mysql mysql -e "UPDATE mysql.user SET Password=PASSWORD('${mysql_password}') WHERE User='root';"
mysql -e "update mysql.user set plugin=null where user='root';"
mysql -e "FLUSH PRIVILEGES;"

# create .mysql folder to store user passwords
mkdir -p /root/.mysql

# generate .my.cnf for root user
cat <<EOF>> /root/.my.cnf
[client]
user = root
password = ${mysql_password}
EOF

# generate mattermost mysql password
mattermost_mysql_password=`pwgen -s -1 16`

# create database
mysql -e "CREATE DATABASE ${mattermost_mysql_database};"
mysql -e "GRANT ALL on ${mattermost_mysql_database}.* to ${mattermost_mysql_user}@'localhost' IDENTIFIED BY '${mattermost_mysql_password}';"
mysql -e "GRANT ALL on ${mattermost_mysql_database}.* to ${mattermost_mysql_user}@'127.0.0.1' IDENTIFIED BY '${mattermost_mysql_password}';"
mysql -e "FLUSH PRIVILEGES;"

# add mattermost system user and set password
useradd -r -s /bin/false ${mattermost_system_user}

# generate a mysql password for mattermost
cat <<EOF>> /root/.mysql/.my.${mattermost_system_user}.cnf
[client]
user = ${mattermost_mysql_user}
password = ${mattermost_mysql_password}
EOF

# download and install mattermost
cd /opt/
wget -q https://releases.mattermost.com/${mattermost_version}/mattermost-${mattermost_version}-linux-amd64.tar.gz
tar -xvf mattermost-${mattermost_version}-linux-amd64.tar.gz > /dev/null 2>&1
mkdir -p mattermost/data
rm mattermost-${mattermost_version}-linux-amd64.tar.gz
mv mattermost mattermost-${mattermost_version}
ln -s mattermost-${mattermost_version} mattermost

# update config.json
sed -i -e 's/:8065/127.0.0.1:8065/g' mattermost/config/config.json
sed -i -e 's/"mmuser:mostest@tcp(dockerhost:3306)\/mattermost_test?charset=utf8mb4,utf8&readTimeout=30s&writeTimeout=30s"/"'${mattermost_mysql_user}':'${mattermost_mysql_password}'@tcp(localhost:3306)\/'${mattermost_mysql_database}'?charset=utf8mb4,utf8"/g' mattermost/config/config.json

# set permissions
chown -R ${mattermost_system_user}: /opt/mattermost*
#chown -R ${mattermost_system_user}: /opt/mattermost/.*
chown -h ${mattermost_system_user}: /opt/mattermost

# add mattermost systemd init
cat <<EOF>> /etc/systemd/system/mattermost.service
[Unit]
Description=Mattermost is an open source, self-hosted Slack-alternative
After=syslog.target network.target

[Service]
Type=notify
User=${mattermost_system_user}
Group=${mattermost_system_user}
ExecStart=/opt/mattermost/bin/mattermost
PIDFile=/var/spool/mattermost/pid/master.pid
WorkingDirectory=/opt/mattermost
Restart=always
RestartSec=30
LimitNOFILE=49152

[Install]
WantedBy=multi-user.target
EOF

# enable mattermost system service
systemctl daemon-reload

# generate selfsigned certificate
mkdir -p /etc/nginx/ssl
cd /etc/nginx/ssl
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -subj '/CN=${nginx_hostname}' -keyout ${nginx_hostname}.key -out ${nginx_hostname}.crt > /dev/null 2>&1
chmod 400 ${nginx_hostname}.key

# generate nginx vhost
variable="$"
cat <<EOF>> /etc/nginx/sites-available/${nginx_hostname}.conf
server {
  listen 80;
  server_name ${nginx_hostname};
  return 301 https://${nginx_hostname};
}

server {
  listen 443 ssl;
  server_name ${nginx_hostname};

  access_log /var/log/nginx/${nginx_hostname}.access.log;
  error_log /var/log/nginx/${nginx_hostname}.error.log;

  ssl on;
  ssl_certificate /etc/nginx/ssl/${nginx_hostname}.crt;
  ssl_certificate_key /etc/nginx/ssl/${nginx_hostname}.key;
  ssl_session_timeout 5m;
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
  ssl_prefer_server_ciphers on;
  ssl_session_cache shared:SSL:10m;

  location / {
    gzip off;
    proxy_set_header X-Forwarded-Ssl on;
    client_max_body_size 50m;
    proxy_set_header Upgrade ${variable}http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host ${variable}http_host;
    proxy_set_header X-Real-IP ${variable}remote_addr;
    proxy_set_header X-Forwarded-For ${variable}proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto ${variable}scheme;
    proxy_set_header X-Frame-Options SAMEORIGIN;
    proxy_pass http://127.0.0.1:8065;
  }
}
EOF

# make nginx vhost active
ln -s /etc/nginx/sites-available/${nginx_hostname}.conf /etc/nginx/sites-enabled/

# start services
systemctl start mattermost
systemctl restart nginx

# done
echo ""
echo "You can find your MySQL password in: /root/.mysql/.my.${mattermost_system_user}.cnf"
echo ""
echo "You can now access https://${nginx_hostname}."
echo "Make sure your DNS settings are correct and that port 8065 is allowed in your firewall."
echo "If your DNS settings are correct you can obtain an Let's Certificate with: sudo certbot --nginx -d ${nginx_hostname}"
echo ""
exit
