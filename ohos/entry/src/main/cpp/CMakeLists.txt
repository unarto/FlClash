cmake_minimum_required(VERSION 3.5.0)
project(entry)

set(NATIVE_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVE_ROOT_PATH})

set(OHOS_CORE_ARCHIVE "")
foreach(CORE_CANDIDATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../libclash/ohos/arm64-v8a/libclash.a")
    if(EXISTS "${CORE_CANDIDATE}")
        set(OHOS_CORE_ARCHIVE "${CORE_CANDIDATE}")
        break()
    endif()
endforeach()

if(OHOS_CORE_ARCHIVE)
    add_library(clash_static STATIC IMPORTED)
    set_target_properties(clash_static PROPERTIES IMPORTED_LOCATION "${OHOS_CORE_ARCHIVE}")
endif()

add_library(entry SHARED bridge.cpp tracked_core_state.cpp)
target_link_libraries(entry PUBLIC
    libace_napi.z.so
    libchild_process.so
    libhilog_ndk.z.so
    libnet_connection.so)
