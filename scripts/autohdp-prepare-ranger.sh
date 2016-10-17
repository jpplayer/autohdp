# Appache Ranger needs to talk to MySQL (same instance as Hive presumably)

# In HDP-Utils
yum -y install mysql-community-release
yum -y install mysql-server mysql-connector-java
service mysql start

/usr/bin/mysqladmin -u root password 'admin'


mysql -u root --password=admin << EOF
create database hive;
create user 'hive'@'%' identified by 'hive';
grant all privileges on *.* to 'hive'@'%' with grant option;
flush privileges;
EOF


ambari-server setup --jdbc-db=mysql --jdbc-driver="/usr/share/java/mysql-connector-java.jar"

