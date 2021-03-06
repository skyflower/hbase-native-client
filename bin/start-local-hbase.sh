#!/usr/bin/env bash
##
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Clean up from any other tests.
rm -rf /tmp/hbase-*

# Start the master/regionservers.
T_DIR=${1:-"/tmp/hbase-testing"}
$PWD/../bin/start-hbase.sh -Dhbase.tmp.dir="${T_DIR}"

until [ $(curl -s -o /dev/null -I -w "%{http_code}" http://localhost:16010/jmx) == "200" ]
do
     printf "Waiting for local HBase cluster to start\n"
     sleep 1
done

# This sucks, but master can easily be up and meta not be assigned yet.
sleep 10
