# Install Mattermost

This script will help you install Mattermost, an open source, self-hosted Slack-alternative. Please change variables at the top of the script before executing.

### Important

`Do not use this script if you already have MySQL and Nginx installed!`

#### Download and install Mattermost

```
bash <( curl https://raw.githubusercontent.com/unixxio/install-mattermost/master/install_mattermost.sh ) yourdomain.example.com
```

#### Tested on

* Debian 9 Stretch

#### Changelog (D/m/Y)

* 06/05/2019 - v1.1 - Update Mattermost and allow arguments for yourdomain.example.com
* 22/09/2018 - v1.0 - First release
