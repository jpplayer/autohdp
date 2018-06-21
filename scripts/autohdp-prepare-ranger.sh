# Appache Ranger needs to talk to MySQL (same instance as Hive presumably)

# In HDP-Utils
yum -y install mariadb-server mysql-connector-java
systemctl start mariadb
systemctl enable mariadb

MYSQL_ROOT_PASSWORD=admin

expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"\r\"
expect \"Set root password?\"
send \"y\r\"
expect \"New password:\"
send \"MYSQL_ROOT_PASSWORD\r\"
expect \"Re-enter new password:\"
send \"MYSQL_ROOT_PASSWORD\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
"

mysql -u root --password=$MYSQL_ROOT_PASSWORD << EOF
create database hive;
create user 'hive'@'%' identified by 'hive';
grant all privileges on hive.* to 'hive'@'%' with grant option;
create user 'hive'@'localhost' identified by 'hive';
grant all privileges on hive.* to 'hive'@'localhost' with grant option;
flush privileges;
EOF


ambari-server setup --jdbc-db=mysql --jdbc-driver="/usr/share/java/mysql-connector-java.jar"

