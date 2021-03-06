# Licensed to the Apache Software Foundation (ASF) under one
#
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
cmake_minimum_required(VERSION 3.0)
PROJECT(hbaseclient CXX)
set(PROJECT_NAME "hbaseclient")
set(PROJECT_VERSION_MAJOR 0)
set(PROJECT_VERSION_MINOR 1 )
set(PROJECT_VERSION_PATCH 0)
set(BUILD_SHARED_LIBS ON)
## set our cmake module path
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(CMakeDependentOption)
include(CheckIncludeFile)
include(ExternalProject)
include(DownloadProject)
include(ExecuteMaven)
include(CheckCXXCompilerFlag)

option(DOWNLOAD_DEPENDENCIES "Downloads and builds all dependencies locally " OFF)
option(HBASE_TARGET_TAG "HBase tag to be used if HBASE_HOME is not set" "master")
option(HBASE_HOME "Path to HBase" "")
option(BUILD_HBASE "Build HBASE_HOME path if it is provided" OFF)
	
## Define the build byproduct prefix, suffix, and shared lib suffix
## These will be used in built local dependencies to locate and identify
## object files. These are defined here as they will be used throughout 
## the cmake modules.
if (WIN32)
  set(BYPRODUCT_PREFIX "" CACHE STRING "" FORCE)
  set(BYPRODUCT_SHARED_SUFFIX ".lib" CACHE STRING "" FORCE)
  set(BYPRODUCT_SUFFIX ".lib" CACHE STRING "" FORCE)
  set(BUILD_ARGS " -GVisual Studio 15 2017")
else()
  set(BYPRODUCT_PREFIX "lib" CACHE STRING "" FORCE)
  set(BYPRODUCT_SHARED_SUFFIX ".so" CACHE STRING "" FORCE)
  set(BYPRODUCT_SUFFIX ".a" CACHE STRING "" FORCE)
endif()
	
######### Includes
## include the Protobuf generation code
include(ProtobufGen)
include(DownloadBoost)
include(DownloadFolly)
include(DownloadWangle)
include(DownloadZookeeper)

set(PROJECT_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/dependencies")

set(BOOST_MIN_VERSION "1.6.1")
# Union of all the libs needed by the current project and dependencies (like folly, wangle etc).
# Just update this list if more libraries are needed and they will be included and linked automatically.
set(BOOST_LIBS context coroutine thread system filesystem regex program_options)

if (DOWNLOAD_DEPENDENCIES)
  ## we want to find the system protoc
  download_project(PROJ Protobuf PREFIX "${PROJECT_PREFIX}" IS_AUTOGEN GIT_REPOSITORY "https://github.com/protocolbuffers/protobuf.git" GIT_TAG "3.5.1.1")
	  			 
  set(PROTOBUF_DIR "${Protobuf_BINARY_DIR}" CACHE STRING "" FORCE)
	
  add_library(Protobuf STATIC IMPORTED)
  set_target_properties(Protobuf PROPERTIES IMPORTED_LOCATION "${Protobuf_BINARY_DIR}/lib/libprotobuf.a" )
  set(PROTOBUF_LIBS "${Protobuf_BINARY_DIR}/lib/libprotobuf.a" "${Protobuf_BINARY_DIR}/lib/libprotoc.a" CACHE STRING "" FORCE)
  set(PROTOBUF_INCLUDE_DIRS "${Protobuf_BINARY_DIR}/include" CACHE STRING "" FORCE)
  add_dependencies(Protobuf "${PROJECT_PREFIX}/Protobuf-download")
  set(PROTOBUF_FOUND TRUE CACHE STRING "" FORCE)
	
  set(PROTOBUF_PROTOC_EXECUTABLE "${Protobuf_BINARY_DIR}/bin/protoc" CACHE STRING "" FORCE)
  ## Add CMAKE_MODULE_PATHS
	
  list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/boost/local")
  list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/zookeeper/local")
  list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/protobuf/local")
  list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/folly/local")
  list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/wangle/local")
else()
  list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/zookeeper/system")
  list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/folly/system")
  list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/wangle/system")
endif(DOWNLOAD_DEPENDENCIES)

## Build Apache HBase components that are necessary for this project

find_package(Java REQUIRED)
find_package(Maven REQUIRED)

if( NOT HBASE_HOME )
  if (DOWNLOAD_DEPENDENCIES)
    ## Download Apache HBase, and build hbase-common so that we can have a targeted build of version.h
    download_project(PROJ apache-hbase PREFIX "${PROJECT_PREFIX}" IS_MAVEN GIT_REPOSITORY "https://github.com/apache/hbase.git" GIT_TAG "${HBASE_TARGET_TAG}")
    set(JAVA_HBASE_DIR "${PROJECT_PREFIX}/apache-hbase-src/")
  else()
    message(FATAL_ERROR "HBASE_HOME must be defined if local dependencies aren't built")
  endif()
else()
if (BUILD_HBASE)
  message(STATUS "Building HBase in ${HBASE_HOME}")
  execute_maven(${HBASE_HOME} mvn_output mvn_result)
  if(NOT "${mvn_result}" STREQUAL "0")
    message(FATAL_ERROR "Failed to build HBase. Please provide a valid path with HBASE_HOME")
  endif()
  else()
    message(STATUS "Using supplied HBase path ${HBASE_HOME}")
  endif()
  set(JAVA_HBASE_DIR "${HBASE_HOME}")
endif()

include_directories("${JAVA_HBASE_DIR}/hbase-common/target/generated-sources/native/")
############
## Validate that we have C++ 14 support
############

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

CHECK_CXX_COMPILER_FLAG("-std=c++14" COMPILER_SUPPORTS_CXX14)
CHECK_CXX_COMPILER_FLAG("-std=c++0x" COMPILER_SUPPORTS_CXX0X)
if(COMPILER_SUPPORTS_CXX14)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++14")
elseif(COMPILER_SUPPORTS_CXX0X)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++0x")
else()
  message(FATAL_ERROR "The compiler ${CMAKE_CXX_COMPILER} has no c++14 support. Please use a different C++ compiler.")
endif()

set(HBASE_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/hbase")
set(HBASE_PROTO_GEN_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/hbase/if")
set(HBASE_PROTO_GEN_INC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/include/hbase/if")
# Set the right openssl root path
if (${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
  set(OPENSSL_ROOT_DIR "/usr/local/opt/openssl/")
else()
  set(OPENSSL_ROOT_DIR "/usr/lib/x86_64-linux-gnu")
endif()
# Include OpenSSL
find_package (OpenSSL REQUIRED)
if (OPENSSL_FOUND)
  include_directories(${OPENSSL_INCLUDE_DIR})
else ()
  message( FATAL_ERROR "OpenSSL was not found. Please install OpenSSL" )
endif (OPENSSL_FOUND)
## Download Facebook Folly and build locally


if (DOWNLOAD_DEPENDENCIES)
  download_boost(${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR} "${BOOST_LIBS}")
  download_folly(${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR})
  download_wangle(${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR})
  download_zookeeper(${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR})
endif(DOWNLOAD_DEPENDENCIES)


# ensure we have required dependencies
find_package(Threads)
find_package(Boost ${BOOST_MIN_VERSION} REQUIRED COMPONENTS "${BOOST_LIBS}")
find_package(LibEvent REQUIRED)
find_package(Gflags REQUIRED)
if (DOWNLOAD_DEPENDENCIES)
  find_package(Sodium REQUIRED)
endif(DOWNLOAD_DEPENDENCIES)
find_package(Folly REQUIRED)
find_package(Krb5 REQUIRED)
find_package(Sasl2 REQUIRED)
find_package(Wangle REQUIRED)
find_package(GTest)
find_package(Glog)
find_package(Java REQUIRED)
find_package(JNI REQUIRED)
find_package(Zookeeper REQUIRED)
find_package(Protobuf REQUIRED)
find_Package(DoubleConversion REQUIRED)
if (NOT FOLLY_FOUND)
 message(FATAL_ERROR "-- Folly not found")
endif()
if (NOT WANGLE_FOUND)
 message(FATAL_ERROR "-- Wangle not found")
endif()
if (NOT PROTOBUF_FOUND)
  message(FATAL_ERROR "-- Protocol buffer include directory not found ${PROTOBUF_INCLUDE_DIRS}")
endif()
if (NOT JNI_FOUND)
  message(FATAL_ERROR "-- JAVA include directory not found")
endif()
### provide the include directories, starting at the base
### and including those from our
include_directories(include)
include_directories(${PROTOBUF_INCLUDE_DIRS})
include_directories(${ZOOKEEPER_INCLUDE_DIRS})
include_directories(${Boost_INCLUDE_DIR})
include_directories(${KRB5_INCLUDE_DIRS})
include_directories(${JAVA_INCLUDE_DIRS})
include_directories(${FOLLY_INCLUDE_DIR})
include_directories(${WANGLE_INCLUDE_DIR})
### create a directory for the hbase protobuf headers.
### this is helpful so that when we include it, later, we can generate
### the protocol buffer source/headers without polluting our tree.
set(CMAKE_BINARY_DIR_GEN "${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_FILES_DIRECTORY}/hbase/if/")
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR_GEN})
## build a recursive list of sources
file(GLOB_RECURSE CONNECTION_SRC "${HBASE_SRC_DIR}/connection/*.cc"  )
file(GLOB_RECURSE EXCEPTION_SRC "${HBASE_SRC_DIR}/exceptions/*.cc"  )
file(GLOB_RECURSE PROTO_SRC "${HBASE_SRC_DIR}/if/*.cc"  )
file(GLOB_RECURSE UTILS_SRC "${HBASE_SRC_DIR}/utils/*.cc"  )
file(GLOB_RECURSE CLIENT_SRC "${HBASE_SRC_DIR}/client/*.cc"  )
file(GLOB_RECURSE SECURITY_SRC "${HBASE_SRC_DIR}/security/*.cc"  )
file(GLOB_RECURSE SRDE_SRC "${HBASE_SRC_DIR}/serde/*.cc"  )
file(GLOB_RECURSE TEST_UTIL "${HBASE_SRC_DIR}/test-util/*.cc"  )
include_directories(${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_FILES_DIRECTORY})
include_directories(${SASL_INCLUDE_DIRS})
include_directories(${GFLAGS_INCLUDE_DIR})

## Use the java proto files defined by the tag
file(GLOB_RECURSE PROTO_FILES "${JAVA_HBASE_DIR}/hbase-protocol-shaded/src/main/protobuf/client/*.proto" 
	"${JAVA_HBASE_DIR}/hbase-protocol-shaded/src/main/protobuf/rpc/*.proto" 
	"${JAVA_HBASE_DIR}/hbase-protocol-shaded/src/main/protobuf/server/master/*.proto" 
	"${JAVA_HBASE_DIR}/hbase-protocol-shaded/src/main/protobuf/server/io/*.proto" 
	"${JAVA_HBASE_DIR}/hbase-protocol-shaded/src/main/protobuf/server/zookeeper/*.proto" 
	"${JAVA_HBASE_DIR}/hbase-protocol-shaded/src/main/protobuf/server/region/*.proto" 
	"${JAVA_HBASE_DIR}/hbase-protocol-shaded/src/main/protobuf/server/rsgroup/*.proto" 
	"${JAVA_HBASE_DIR}/hbase-protocol-shaded/src/main/protobuf/server/*.proto" 
	"${JAVA_HBASE_DIR}/hbase-protocol-shaded/src/main/protobuf/test/ipc/*.proto"
	"${JAVA_HBASE_DIR}/hbase-protocol-shaded/src/main/protobuf/*.proto" )
### generate the protocol buffers.
generate_protobuf_src(PROTO_SOURCES PROTO_HEADERS PROTO_HEADER_DIR "${JAVA_HBASE_DIR}/hbase-protocol-shaded/src/main/protobuf" ${PROTO_FILES})
include_directories(${PROTO_HEADER_DIR})
add_library(hbaseclient-static STATIC ${PROTO_SOURCES} ${CLIENT_SRC} ${CONNECTION_SRC} ${EXCEPTION_SRC} ${PROTO_SRC} ${SECURITY_SRC} ${SRDE_SRC} ${UTILS_SRC})
set_target_properties(hbaseclient-static PROPERTIES LINKER_LANGUAGE CXX)
SET_TARGET_PROPERTIES(hbaseclient-static PROPERTIES OUTPUT_NAME hbaseclient CLEAN_DIRECT_OUTPUT 1)
set_target_properties(hbaseclient-static PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/libs")
target_link_libraries(hbaseclient-static ${Boost_LIBRARIES})
target_link_libraries(hbaseclient-static ${SASL_LIBS})
target_link_libraries(hbaseclient-static ${GFLAGS_SHARED_LIB})
target_link_libraries(hbaseclient-static ${KRB5_LIBRARIES})
target_link_libraries(hbaseclient-static ${WANGLE_LIBRARIES})
if (DOWNLOAD_DEPENDENCIES)
  target_link_libraries(hbaseclient-static ${sodium_LIBRARY_RELEASE})
endif(DOWNLOAD_DEPENDENCIES)
target_link_libraries(hbaseclient-static ${FOLLY_LIBRARIES})
target_link_libraries(hbaseclient-static ${GLOG_SHARED_LIB})
target_link_libraries(hbaseclient-static ${LIB_EVENT_LIBRARY})
target_link_libraries(hbaseclient-static ${PROTOBUF_LIBRARY})
target_link_libraries(hbaseclient-static ${DOUBLE_CONVERSION_LIBRARY})
target_link_libraries(hbaseclient-static ${ZOOKEEPER_LIBRARIES})
target_link_libraries(hbaseclient-static ${OPENSSL_LIBRARIES})
target_link_libraries(hbaseclient-static ${CMAKE_DL_LIBS})

add_library(hbaseclient-shared SHARED ${PROTO_SOURCES} ${CLIENT_SRC} ${CONNECTION_SRC} ${EXCEPTION_SRC} ${PROTO_SRC} ${SECURITY_SRC} ${SRDE_SRC} ${UTILS_SRC})
set_target_properties(hbaseclient-shared PROPERTIES LINKER_LANGUAGE CXX)
SET_TARGET_PROPERTIES(hbaseclient-shared PROPERTIES COMPILE_FLAGS " -fPIC")
SET_TARGET_PROPERTIES(hbaseclient-shared PROPERTIES OUTPUT_NAME hbaseclient CLEAN_DIRECT_OUTPUT 1)
set_target_properties(hbaseclient-shared PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/libs")
target_link_libraries(hbaseclient-shared ${PROTOBUF_LIBRARY})
target_link_libraries(hbaseclient-shared ${Boost_LIBRARIES})
target_link_libraries(hbaseclient-shared ${WANGLE_LIBRARIES})
if (DOWNLOAD_DEPENDENCIES)
  target_link_libraries(hbaseclient-shared ${sodium_LIBRARY_RELEASE})
endif(DOWNLOAD_DEPENDENCIES)
target_link_libraries(hbaseclient-shared ${FOLLY_LIBRARIES})
target_link_libraries(hbaseclient-shared ${SASL_LIBS})
target_link_libraries(hbaseclient-shared ${GLOG_SHARED_LIB})
target_link_libraries(hbaseclient-shared ${GFLAGS_SHARED_LIB})
target_link_libraries(hbaseclient-shared ${KRB5_LIBRARIES})
target_link_libraries(hbaseclient-shared ${OPENSSL_LIBRARIES})
target_link_libraries(hbaseclient-shared ${LIB_EVENT_LIBRARY})
target_link_libraries(hbaseclient-shared ${ZOOKEEPER_LIBRARIES})
target_link_libraries(hbaseclient-shared ${DOUBLE_CONVERSION_LIBRARY})
target_link_libraries(hbaseclient-shared ${CMAKE_DL_LIBS})
add_executable(simple-client "${HBASE_SRC_DIR}/examples/simple-client.cc")
set_target_properties(simple-client PROPERTIES COMPILE_FLAGS "  ")
set_target_properties(simple-client PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin/examples")
target_link_libraries(simple-client ${PROTOBUF_LIBRARY})
target_link_libraries(simple-client ${Boost_LIBRARIES})
target_link_libraries(simple-client ${SASL_LIBS})
target_link_libraries(simple-client ${GFLAGS_SHARED_LIB})
target_link_libraries(simple-client ${KRB5_LIBRARIES})
target_link_libraries(simple-client ${ZOOKEEPER_LIBRARIES})
target_link_libraries(simple-client hbaseclient-static ${CMAKE_THREAD_LIBS_INIT})
add_executable(load-client "${HBASE_SRC_DIR}/examples/load-client.cc")
set_target_properties(load-client PROPERTIES COMPILE_FLAGS "  ")
set_target_properties(load-client PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin/examples")
target_link_libraries(load-client ${PROTOBUF_LIBRARY})
target_link_libraries(load-client ${Boost_LIBRARIES})
target_link_libraries(load-client ${SASL_LIBS})
target_link_libraries(load-client ${GFLAGS_SHARED_LIB})
target_link_libraries(load-client ${KRB5_LIBRARIES})
target_link_libraries(load-client ${ZOOKEEPER_LIBRARIES})
target_link_libraries(load-client hbaseclient-static ${CMAKE_THREAD_LIBS_INIT})
if (JNI_FOUND)
  message (STATUS "JNI_INCLUDE_DIRS=${JNI_INCLUDE_DIRS}")
  message (STATUS "JNI_LIBRARIES=${JNI_LIBRARIES}")
endif()
if (NOT SKIP_TESTS)
  include(BuildTests)
endif()
## Create a custom target for our linter
add_custom_target(
    linter
    COMMAND ${CMAKE_SOURCE_DIR}/bin/cpplint.sh)

if (DOWNLOAD_DEPENDENCIES)
  add_dependencies(facebook-folly-proj boost)
  add_dependencies(hbaseclient-static boost)
  add_dependencies(hbaseclient-shared boost)
  add_dependencies(hbaseclient-static Protobuf)
  add_dependencies(hbaseclient-shared Protobuf)
  add_dependencies(facebook-wangle-proj facebook-folly-proj)
  add_dependencies(hbaseclient-static facebook-wangle-proj)
  add_dependencies(hbaseclient-shared facebook-wangle-proj)
  add_dependencies(hbaseclient-static zookeeper)
  add_dependencies(hbaseclient-shared zookeeper)
endif(DOWNLOAD_DEPENDENCIES)

# Install library headers
include(GNUInstallDirs)
file(GLOB RECURSE HEADERS include/*.h)
set_target_properties(hbaseclient-static PROPERTIES PUBLIC_HEADER "${HEADERS}")
install(TARGETS hbaseclient-static
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    PUBLIC_HEADER DESTINATION include/
    COMPONENT LIBRARY )
install(TARGETS hbaseclient-shared
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    PUBLIC_HEADER DESTINATION include/
    COMPONENT LIBRARY )
install(
    DIRECTORY ${CMAKE_SOURCE_DIR}/include/
    DESTINATION include/
    FILES_MATCHING PATTERN "*.h*")
# Install pb-generated headers too
install(
    DIRECTORY "${CMAKE_BINARY_DIR_GEN}"
    DESTINATION include/hbase/if
    FILES_MATCHING PATTERN "hbase/if/*.h")

