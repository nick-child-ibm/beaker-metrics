#!/bin/bash

# This script will install and setup:
# 1. Nicks branch of beaker-sre - https://github.com/nick-child-ibm/beaker-sre.git
# 1. prometheus - https://prometheus.io/download/
# 2. grafana - https://grafana.com/grafana/download?plcmt=top-nav&cta=downloads
# 3. sql-agent - https://github.com/chop-dbhi/sql-agent
# 4. prometheus-sql - https://github.com/chop-dbhi/prometheus-sql

# expectations:
#	1. This is run with root privileges
# 2. This is run on a beaker server machine (localhost is used to reference it)
# 3. Areas labeled "USER TODO" should be read and edited by the user running this script

# this script will expose the following ports:
# 9090 - prometheus
# 3000 - grafana
# 5000 - sql agent
# 8080 - prometheus-sql data endpoint
# 3306 - mysql database port, probably already exposed

# USER TODO 
BEAKER_SERVER_IP="192.168.120.104"
SRC_DIR=$PWD'/'
SERVER_USR="beaker_prometheus"
BEAKER_DB_USR="sql_agent"
BEAKER_DB_PSWD="SqLAgENNT"
BEAKER_SRE_GIT_URL="https://github.com/nick-child-ibm/beaker-sre.git"
BEAKER_SRE_GIT_BRANCH="devel"
PROM_SQL_CONFIGS_GIT_URL="https://github.com/nick-child-ibm/beaker-metrics"
PROM_SQL_CONFIGS_GIT_BRANCH="master"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v2.31.1/prometheus-2.31.1.linux-amd64.tar.gz"
GRAFANA_URL="https://dl.grafana.com/enterprise/release/grafana-enterprise-8.2.3.linux-amd64.tar.gz"
PROM_SQL_URL="https://github.com/chop-dbhi/prometheus-sql/releases/download/1.4.3/prometheus-sql-linux-amd64.tar.gz"

# function to print line number $1, and exit with return code -1
function error_exit(  ) {
	>&2 echo "Script failed at line $1"
	exit 1
}

# cd into working directory, create if needed
echo Working in $SRC_DIR
[ ! -d "$SRC_DIR" ] && mkdir $SRC_DIR
! cd $SRC_DIR && error_exit $LINENO

# make user if needed
if id $SERVER_USR &> /dev/null; then
	echo "$SERVER_USR exists continuing..."
else
	echo "Creating user $SERVER_USR"
	useradd $SERVER_USR
fi
! id $SERVER_USR &> /dev/null && error_exit $LINENO

# clone beaker-sre
git clone -b $BEAKER_SRE_GIT_BRANCH $BEAKER_SRE_GIT_URL
! cd beaker-sre  && error_exit $LINENO
cd ..

# install prometheus
mkdir prometheus
! cd prometheus && error_exit $LINENO
# extract file name from url
PROM_TAR_BALL=${PROM_URL##*\/}
echo "expecting file $PROM_TAR_BALL"
if [ ! -f $PROM_TAR_BALL ]; then 
	wget $PROM_URL
else
	echo "$PROM_TAR_BALL already found to exist, continuing"
fi
! tar -xf  ${PROM_TAR_BALL} && error_exit $LINENO
PROM_DIR=${SRC_DIR}/prometheus/${PROM_TAR_BALL%.tar.gz}
cd ..
# copy config file from beaker-sre
! cp ./beaker-sre/prometheus/prometheus.yml ${PROM_DIR}/prometheus.yml && error_exit $LINENO
# replace some strings in prometheus service file
! sed -i "s:/home/prometheus/prometheus:${PROM_DIR}:g" beaker-sre/prometheus/prometheus.service && error_exit $LINENO
! sed -i "s:=prometheus:=${SERVER_USR}:g" beaker-sre/prometheus/prometheus.service && error_exit $LINENO
! sed -i "s:beaker-sre.target:${SERVER_USR}.target:g" beaker-sre/prometheus/prometheus.service && error_exit $LINENO

# transfer ownership to the given server_usr
! chown -R ${SERVER_USR}:${SERVER_USR} prometheus

# start prometheus service
! cp beaker-sre/prometheus/prometheus.service /etc/systemd/system/prometheus.service && error_exit $LINENO
! systemctl enable prometheus.service && error_exit $LINENO
! systemctl start prometheus.service && error_exit $LINEN

# ensure prometheus is running properly
! systemctl status prometheus.service | grep "active (running)" && error_exit $LINENO
! wget http://${BEAKER_SERVER_IP}:9090/targets -O /dev/null && error_exit $LINENO
! wget http://${BEAKER_SERVER_IP}:9090/metrics -O /dev/null && error_exit $LINENO

# download and install grafana
mkdir grafana
! cd grafana && error_exit $LINENO
GRAFANA_TAR_BALL=${GRAFANA_URL##*\/}
echo "expecting file $GRAFANA_TAR_BALL"
if [ ! -f $GRAFANA_TAR_BALL ]; then 
	wget $GRAFANA_URL
else
	echo "$GRAFANA_TAR_BALL already found to exist, continuing"
fi
! tar -zxf $GRAFANA_TAR_BALL && error_exit $LINENO
GRAFANA_DIR=${SRC_DIR}/grafana/${GRAFANA_TAR_BALL%.linux-amd64.tar.gz}
GRAFANA_DIR=${GRAFANA_DIR/-enterprise/}
cd ..

# replace some strings in grafana service file
! sed -i "s:/home/grafana/grafana:${GRAFANA_DIR}:g" beaker-sre/grafana/grafana.service && error_exit $LINENO
! sed -i "s:=grafana:=${SERVER_USR}:g" beaker-sre/grafana/grafana.service && error_exit $LINENO
! sed -i "s:beaker-sre.target:${SERVER_USR}.target:g" beaker-sre/grafana/grafana.service && error_exit $LINENO

# transfer ownership to the given server_usr
! chown -R ${SERVER_USR}:${SERVER_USR} grafana

# start grafana service
! cp beaker-sre/grafana/grafana.service /etc/systemd/system/grafana.service && error_exit $LINENO
! systemctl enable grafana.service && error_exit $LINENO
! systemctl start grafana.service && error_exit $LINEN

# ensure grafana is running properly
! systemctl status grafana.service | grep "active (running)" && error_exit $LINENO
# sometimes this fails if time is not given to get the service set up
sleep 2
! wget http://${BEAKER_SERVER_IP}:3000 -O /dev/null && error_exit $LINENO

# USER TODO
# user should now go to the grafana url navigate to Configuration -> Data sources -> Add data source -> Prometheus -> Select
# then add ${SERVER_URL}:9090 to link prometheus datasource to grafana UI


# get config files for later use
# clone beaker-metrics
git clone -b $PROM_SQL_CONFIGS_GIT_BRANCH $PROM_SQL_CONFIGS_GIT_URL
! cd beaker-metrics && error_exit $LINENO
cd ..

# set up sql-agent docker container
# this container will be named "sql_agent"
# check to see if it already exists
if ! docker container ls --all | grep "sql_agent" ; then
	docker run --name sql_agent -d -p 5000:5000 dbhi/sql-agent
else
	echo "Docker container 'sql_agent' already exists... continuing"
fi
# check to see if it is already running
if ! [[ $(docker container inspect -f '{{.State.Status}}' sql_agent) = "running" ]]; then
	docker start sql_agent
else
	echo "Docker container 'sql_agent' is already running... continuing"
fi
# now it should definitely be running
! [[ $(docker container inspect -f '{{.State.Status}}' sql_agent) = "running" ]] && error_exit $LINENO
# get IP address for future use
SQL_AGENT_IP=`docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' sql_agent`
echo "'sql_agent' docker container has IP: ${SQL_AGENT_IP}"

# create user/password for accessing the beaker database
! mysql -e "GRANT SELECT ON beaker.* to '${BEAKER_DB_USR}'@'${SQL_AGENT_IP}' identified by '${BEAKER_DB_PSWD}'; flush privileges;" && error_exit $LINENO

# edit test json config with out values
! sed -i "s:192.168.120.104:${BEAKER_SERVER_IP}:g" beaker-metrics/test_post.json && error_exit $LINENO
! sed -i "s/\"admin\",/\"${BEAKER_DB_USR}\",/g" beaker-metrics/test_post.json && error_exit $LINENO
! sed -i "s/\"admin\"/\"${BEAKER_DB_PSWD}\"/g" beaker-metrics/test_post.json && error_exit $LINENO

# check sql-agent container is now able to read beaker database with credentials
! curl -v -H "Content-Type: application/json" -X POST -d @beaker-metrics/test_post.json http://localhost:5000 | grep '"cnt":' && error_exit $LINENO

# download and install prometheus-sql
mkdir prometheus-sql
! cd prometheus-sql && error_exit $LINENO
PROM_SQL_TAR_BALL=${PROM_SQL_URL##*\/}
echo "expecting file $PROM_SQL_TAR_BALL"
if [ ! -f $PROM_SQL_TAR_BALL ]; then 
	wget $PROM_SQL_URL
else
	echo "$PROM_SQL_TAR_BALL already found to exist, continuing"
fi
! tar -zxf $PROM_SQL_TAR_BALL && error_exit $LINENO
PROM_SQL_DIR=${SRC_DIR}/prometheus-sql/${PROM_SQL_TAR_BALL%.tar.gz}
PROM_SQL_DIR=${PROM_SQL_DIR/prometheus-sql-/}
cd ..
# make some edits to the prometheus-sql config file
! sed -i "s:192.168.120.104:${BEAKER_SERVER_IP}:g" beaker-metrics/config.yml && error_exit $LINENO
! sed -i "s/user: admin/user: ${BEAKER_DB_USR}/g" beaker-metrics/config.yml && error_exit $LINENO
! sed -i "s/password: admin/password: ${BEAKER_DB_PSWD}/g" beaker-metrics/config.yml && error_exit $LINENO
! cp beaker-metrics/config.yml ${PROM_SQL_DIR}/ && error_exit $LINENO
! cp beaker-metrics/queries.yml ${PROM_SQL_DIR}/ && error_exit $LINENO

# replace some strings in prom-sql service file
! sed -i "s:/home/prometheus-sql/linux-amd64:${PROM_SQL_DIR}:g" beaker-metrics/prometheus-sql.service && error_exit $LINENO
! sed -i "s:=prometheus:=${SERVER_USR}:g" beaker-metrics/prometheus-sql.service && error_exit $LINENO

# transfer ownership to the given server_usr
! chown -R ${SERVER_USR}:${SERVER_USR} prometheus-sql

# start prometheus-sql service
! cp  beaker-metrics/prometheus-sql.service /etc/systemd/system/prometheus-sql.service && error_exit $LINENO
! systemctl enable prometheus-sql.service && error_exit $LINENO
! systemctl start prometheus-sql.service && error_exit $LINEN

# ensure prometheus-sql is running properly
! systemctl status prometheus-sql.service | grep "active (running)" && error_exit $LINENO
! wget http://${BEAKER_SERVER_IP}:8080/metrics -O /dev/null && error_exit $LINENO
echo Success
