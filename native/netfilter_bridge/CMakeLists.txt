cmake_minimum_required(VERSION 3.15)
project(netfilter_bridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# NetFilter SDK 目录（含 nfapi.h / nfapi.lib）—— 由你自备，本仓库不包含。
# 默认在 ./sdk/ 下；也可用 -DNFAPI_DIR=<path> 指定。
set(NFAPI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/sdk" CACHE PATH "NetFilter SDK dir (contains nfapi.h / nfapi.lib)")

add_library(netfilter_bridge SHARED netfilter_bridge.cpp)
target_include_directories(netfilter_bridge PRIVATE "${NFAPI_DIR}")
target_link_libraries(netfilter_bridge PRIVATE "${NFAPI_DIR}/nfapi.lib" ws2_32)
set_target_properties(netfilter_bridge PROPERTIES PREFIX "" OUTPUT_NAME "netfilter_bridge")
