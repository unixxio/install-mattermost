# Install Mattermost

This script will help you install Mattermost, an open source, self-hosted Slack-alternative. Change `mattermost.yourdomain.com` accordingly.

### Important

Do **NOT** use this script if you already have `Nginx`, `MySQL` or `MariaDB` installed!

#### Download and install Mattermost

```
bash <( curl -sSL https://raw.githubusercontent.com/unixxio/install-mattermost/master/install_mattermost.sh ) mattermost.yourdomain.com
```

#### Obtaining an Let's Encrypt SSL Certificate

```
sudo certbot --nginx -d mattermost.yourdomain.com
```

#### Tested on

* Debian 9 Stretch

#### Changelog (D/m/Y)

* 06/05/2019 - v1.1 - Update Mattermost version
* 22/09/2018 - v1.0 - First release
