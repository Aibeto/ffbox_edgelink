cmake_minimum_required(VERSION 3.22)
project(ffbox_nodeext)

# libnode.so（nodejs-mobile）与头文件由 tool/build-mobile.mjs 下载放置：
#   jniLibs/arm64-v8a/libnode.so
#   cpp/include/node/*.h
add_library(node SHARED IMPORTED)
set_target_properties(node PROPERTIES
        IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libnode.so)

add_library(nodeext SHARED nodejni.cpp)
target_include_directories(nodeext PRIVATE ${CMAKE_SOURCE_DIR}/include/node)
target_link_libraries(nodeext node)
