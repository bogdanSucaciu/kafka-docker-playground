#!/bin/bash

# Exit immediately if a *pipeline* returns a non-zero status. (Add -x for command tracing)
set -e

#
# Set up the JMX options
#
: ${JMXAUTH:="false"}
: ${JMXSSL:="false"}
if [[ -n "$JMXPORT" && -n "$JMXHOST" ]]; then
    echo "Enabling JMX on ${JMXHOST}:${JMXPORT}"
    export KAFKA_JMX_OPTS="-Djava.rmi.server.hostname=${JMXHOST} -Dcom.sun.management.jmxremote.rmi.port=${JMXPORT} -Dcom.sun.management.jmxremote.port=${JMXPORT} -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=${JMXAUTH} -Dcom.sun.management.jmxremote.ssl=${JMXSSL} "
fi

# Copy config files if not provided in volume
cp -rn $KAFKA_HOME/config.orig/* $KAFKA_HOME/config

if [[ -z "$LOG_LEVEL" ]]; then
    LOG_LEVEL="INFO"
fi
sed -i -r -e "s|=INFO, stdout|=$LOG_LEVEL, stdout|g" $KAFKA_HOME/config/log4j.properties
sed -i -r -e "s|^(log4j.appender.stdout.threshold)=.*|\1=${LOG_LEVEL}|g" $KAFKA_HOME/config/log4j.properties
export KAFKA_LOG4J_OPTS="-Dlog4j.configuration=file:$KAFKA_HOME/config/log4j.properties"
unset LOG_LEVEL

# Add missing EOF at the end of the config file
echo "" >> $KAFKA_HOME/config/server.properties

#
# Process all environment variables that start with 'KAFKA_' (but not 'KAFKA_HOME' or 'KAFKA_VERSION'):
#
for VAR in `env`
do
  env_var=`echo "$VAR" | sed -r "s/(.*)=.*/\1/g"`
  if [[ $env_var =~ ^KAFKA_ && $env_var != "KAFKA_VERSION" && $env_var != "KAFKA_HOME"  && $env_var != "KAFKA_LOG4J_OPTS" && $env_var != "KAFKA_JMX_OPTS" ]]; then
    prop_name=`echo "$VAR" | sed -r "s/^KAFKA_(.*)=.*/\1/g" | tr '[:upper:]' '[:lower:]' | tr _ .`
    if [[ $prop_name = "zookeeper.client.cnxn.socket" ]]; then
      prop_name="zookeeper.clientCnxnSocket"
    fi
    if [[ $prop_name =~ ^super.users ]]; then
      prop_name="super.users"
      env_var=`echo "$VAR" | sed "s/[^=]*=//"`
      echo "$prop_name=${env_var}" >> $KAFKA_HOME/config/server.properties
    elif egrep -q "(^|^#)$prop_name=" $KAFKA_HOME/config/server.properties; then
        #note that no config names or values may contain an '@' char
        sed -r -i "s@(^|^#)($prop_name)=(.*)@\2=${!env_var}@g" $KAFKA_HOME/config/server.properties
    else
        #echo "Adding property $prop_name=${!env_var}"
        echo "$prop_name=${!env_var}" >> $KAFKA_HOME/config/server.properties
    fi
  fi
done

exec $KAFKA_HOME/bin/kafka-server-start.sh $KAFKA_HOME/config/server.properties