#!/usr/bin/env bash

# Use single quotes instead of double quotes to make it work with special-character passwords
MYSQL_PASSWORD='12345'
PROJECTFOLDER='/var/www/html'

# update / upgrade
sudo apt-get update
sudo apt-get -y upgrade

# Install Basics
# build-essential needed for "make" command
sudo apt-get install -y build-essential software-properties-common vim curl wget tmux

# install apache 2.5 and php 5.5
sudo apt-get install -y apache2
sudo apt-get install -y php5 php5-dev php5-curl php-pear php5-xdebug

# install mysql and give password to installer
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_PASSWORD"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD"
sudo apt-get -y install mysql-server
sudo apt-get -y install php5-mysql

# install phpmyadmin and give password(s) to installer
# for simplicity I'm using the same password for mysql and phpmyadmin
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password $MYSQL_PASSWORD"
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_PASSWORD"
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password $MYSQL_PASSWORD"
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"
sudo apt-get -y install phpmyadmin

# setup hosts file
VHOST=$(cat <<EOF
<VirtualHost *:80>
    ServerName localhost

    ServerAdmin webmaster@localhost
    DocumentRoot "${PROJECTFOLDER}"

    <Directory "${PROJECTFOLDER}">
            AllowOverride All
    </Directory>
</VirtualHost>

EOF
)
echo "${VHOST}" > /etc/apache2/sites-available/000-default.conf

sed -i -e '0,/index/s//index.php index/' /etc/apache2/mods-available/dir.conf

# ativando modulos do PHP
sudo php5enmod mcrypt
pecl install xdebug

# enable mod_rewrite
sudo a2enmod rewrite

# Atualiza as configurações do PHP
declare -A php_ini

php_ini["upload_max_filesize"]=900M
php_ini["post_max_size"]=900M
php_ini["max_execution_time"]=100
php_ini["max_input_time"]=223

for key in ${!php_ini[@]}; do
    sed -i "s/^\($key\).*/\1 = $(eval echo \${php_ini[${key}]})/" /etc/php5/apache2/php.ini
done

# restart apache
service apache2 restart

# install git
# sudo apt-get -y install git

# install Composer
curl -s https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# Install PHPUnit 4.8.9
wget https://phar.phpunit.de/phpunit-4.8.9.phar
chmod +x phpunit-4.8.9.phar
sudo mv phpunit-4.8.9.phar /usr/local/bin/phpunit

# XDEBUG=$(sudo find /usr/lib/php5/ -name 'xdebug.so')
# echo "zend_extension=${XDEBUG}" >> /etc/php5/apache2/php.ini

service apache2 restart

# Install Mailcatcher Dependencies (sqlite, ruby)
sudo apt-get install -y libsqlite3-dev ruby1.9.1-dev

# Install Mailcatcher as a Ruby gem
sudo gem install mailcatcher

MAILCATCHER_CONF=$(cat <<EOF
description "Mailcatcher"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

exec /usr/bin/env \$(which mailcatcher) --foreground --ip=0.0.0.0

EOF
)
echo "${MAILCATCHER_CONF}" > /etc/init/mailcatcher.conf

# Add config to mods-available for PHP
# -f flag sets "from" header for us
echo "sendmail_path = /usr/bin/env $(which catchmail) -f test@local.dev" | sudo tee /etc/php5/mods-available/mailcatcher.ini

# Enable sendmail config for all php SAPIs (apache2, fpm, cli)
sudo php5enmod mailcatcher

# Restart Apache if using mod_php
sudo service apache2 restart

clear

sudo mailcatcher --ip=0.0.0.0

# Libera o acesso do mysql
sudo sed -i '/skip-external-locking/ s/^/#/' /etc/mysql/my.cnf
sudo sed -i '/bind-address/ s/^/#/' /etc/mysql/my.cnf
sudo service mysql restart
