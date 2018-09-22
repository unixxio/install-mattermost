#!/bin/bash
# date: 09-22-2018
# creator: unixx.io

# version variables
mattermost_version="5.3.1"

# mattermost variables
mattermost_system_user="mattermost"
mattermost_mysql_user="mattermost"
mattermost_mysql_database="mattermost_db01"
nginx_host_name="mattermost.unixx.io"

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

# first install MySQL and Nginx
apt-get update > /dev/null 2>&1
apt-get install pwgen mysql-server mysql-client nginx -y > /dev/null 2>&1

# set root mysql password (and disable password-less socket auth)
mysql_password=`pwgen -s -1 16`

mysql mysql -e "UPDATE mysql.user SET Password=PASSWORD('${mysql_password}') WHERE User='root';"
mysql -e "update mysql.user set plugin=null where user='root';"
mysql -e "FLUSH PRIVILEGES;"

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

# generate mattermost user password
mattermost_user_password=`pwgen -s -1 12`

# add mattermost system user and set password
useradd -m -s /bin/bash ${mattermost_system_user}
echo "${mattermost_system_user}:${mattermost_user_password}" | chpasswd

# generate password file system user to lookup afterwards
cat <<EOF>> /home/${mattermost_system_user}/.my.passwd
user = ${mattermost_system_user}
password = ${mattermost_user_password}
EOF

# generate password file mysql to lookup afterwards
cat <<EOF>> /home/${mattermost_system_user}/.my.cnf
[client]
user = ${mattermost_mysql_user}
password = ${mattermost_mysql_password}
EOF

# download and install mattermost
cd /home/${mattermost_system_user}
wget -q https://releases.mattermost.com/${mattermost_version}/mattermost-${mattermost_version}-linux-amd64.tar.gz
tar -xvf mattermost-${mattermost_version}-linux-amd64.tar.gz > /dev/null 2>&1
mkdir -p mattermost/data
rm mattermost-${mattermost_version}-linux-amd64.tar.gz
mv mattermost mattermost-${mattermost_version}
ln -s mattermost-${mattermost_version} latest

# updata config.json
sed -i -e 's/:8065/127.0.0.1:8065/g' latest/config/config.json
sed -i -e 's/"mmuser:mostest@tcp(dockerhost:3306)\/mattermost_test?charset=utf8mb4,utf8&readTimeout=30s&writeTimeout=30s"/"'${mattermost_mysql_user}':'${mattermost_mysql_password}'@tcp(localhost:3306)\/'${mattermost_mysql_database}'?charset=utf8mb4,utf8"/g' latest/config/config.json

# set permissions
chown -R ${mattermost_system_user}: /home/${mattermost_system_user}/*
chown -R ${mattermost_system_user}: /home/${mattermost_system_user}/.*
chown -h ${mattermost_system_user}: /home/${mattermost_system_user}/latest

# add mattermost systemd init
cat <<EOF>> /etc/systemd/system/mattermost.service
[Unit]
Description=Mattermost is an open source, self-hosted Slack-alternative
After=syslog.target network.target

[Service]
Type=notify
User=${mattermost_system_user}
Group=${mattermost_system_user}
ExecStart=/home/${mattermost_system_user}/latest/bin/mattermost
PIDFile=/var/spool/mattermost/pid/master.pid
WorkingDirectory=/home/${mattermost_system_user}/latest
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
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -subj '/CN=localhost' -keyout mattermost.key -out mattermost.crt > /dev/null 2>&1
chmod 400 mattermost.key

# generate nginx vhost
variable="$"
cat <<EOF>> /etc/nginx/sites-available/mattermost.conf
server {
  listen 80;
  server_name ${nginx_host_name};
  return 301 https://${nginx_host_name};
}

server {
  listen 443 ssl;
  server_name ${nginx_host_name};

  ssl on;
  ssl_certificate /etc/nginx/ssl/mattermost.crt;
  ssl_certificate_key /etc/nginx/ssl/mattermost.key;
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
ln -s /etc/nginx/sites-available/mattermost.conf /etc/nginx/sites-enabled/

# start services
systemctl start mattermost
systemctl restart nginx

# done
echo ""
echo "You can find your user password in: /home/${mattermost_system_user}/.my.passwd"
echo "You can find your MySQL password in: /home/${mattermost_system_user}/.my.cnf"
echo ""
echo "You can now access https://${nginx_host_name}."
echo "Make sure your DNS settings are correct and that port 8065 is allowed in your firewall."
echo ""
exit
