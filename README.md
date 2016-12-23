AutoHDP
======
Automatically installs a single node HDP cluster with the following features:
+ Kerberos
+ LDAP
+ Local repository creation
+ Optimized settings for machines with limited ram (wip)
+ Enables Phoenix, Hive interactive and other features
+ Ambari 2.2 or 2.4
+ HDP 2.4 or 2.5

**Requirements**
+ CentOS 6 or 7
+ Virtual Machine with 8 GB or more ram.

Not all HDP components can be running at the same time on an 8 GB VM. The script will turn off services that would exceed RAM and place them in maintenance mode. A 16 GB VM can run most components. 24 GB is required to run everything.

Quick Start
------
Spin up a virtual machine and clone autohdp. You can specify a known GA version of Ambari and HDP or provide custom repo links. If specified, the version must be listed under (repos/known_repos.txt).

```bash
# Install the latest version of HDP (2.5 as of 12/16)
./autohdp.sh
```
The command will complete once Ambari has acknowledged the cluster creation request.

Other syntax
------
A specific version can be specified. 

```bash
# Pick latest 2.5.x version
./autohdp.sh 2.5
# Pick latest 2.4.2.x version
./autohdp.sh 2.4.2
```

Custom repository links. The script will attempt to derive the version from the url. CLUSTERNAME is optional. By default it will pick the hostname.
```bash
export AMBARIREPO=http://public-repo-1.hortonworks.com/ambari/centos6/2.x/updates/2.2.2.0/ambari.repo
export HDPREPO=http://public-repo-1.hortonworks.com/HDP/centos6/2.x/updates/2.4.2.0/hdp.repo
export CLUSTERNAME=hadoop
./autohdp.sh
```
Ambari and HDP repos can be found at http://docs.hortonworks.com.

Post-install features enabled (wip)
------
+ Principal and ldap entry for "admin" user
+ HDFS folder for "admin" user
+ All components secured via Ranger

