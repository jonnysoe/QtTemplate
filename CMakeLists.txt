cmake_minimum_required(VERSION 3.16)

# Treat string as is, do not treat as variables to be expanded
cmake_policy(SET CMP0054 NEW)

# Set project name
get_filename_component(ProjectId ${CMAKE_CURRENT_SOURCE_DIR} NAME)
string(REPLACE " " "_" ProjectId ${ProjectId})
project(${ProjectId} VERSION 0.1.0 LANGUAGES CXX)

message(STATUS "CMAKE_GENERATOR: ${CMAKE_GENERATOR}")

# Enable CCache
# https://stackoverflow.com/a/64600661/19336104
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    message(STATUS "Using ccache: ${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
    set(CMAKE_C_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
endif()

# Multi-config: set default build configurations
set(CMAKE_CONFIGURATION_TYPES "Release;RelWithDebInfo" CACHE STRING "" FORCE)

# Single-config: set the default build type if not specified
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING
        "Choose the type of build: None, Debug, Release, RelWithDebInfo, MinSizeRel"
        FORCE)
else()
    # Case-insensitive correction hack
    string(TOLOWER ${CMAKE_BUILD_TYPE} CMAKE_BUILD_TYPE_LOWER)
    if(CMAKE_BUILD_TYPE_LOWER STREQUAL "release")
        set(CMAKE_BUILD_TYPE "Release")
    elseif(CMAKE_BUILD_TYPE_LOWER STREQUAL "debug")
        set(CMAKE_BUILD_TYPE "Debug")
    elseif(CMAKE_BUILD_TYPE_LOWER STREQUAL "relwithdebinfo")
        set(CMAKE_BUILD_TYPE "RelWithDebInfo")
    elseif(CMAKE_BUILD_TYPE_LOWER STREQUAL "minsizerel")
        set(CMAKE_BUILD_TYPE "MinSizeRel")
    endif()
endif()

option(QT_DEPLOY "Enable Qt deployment" OFF)

# Output directories
# https://cmake.org/cmake/help/latest/manual/cmake-buildsystem.7.html#output-artifacts
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin) # .exe/.dll for executable
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin) # shared library .so/.dylib, .dll (Windows) files are not affected
# Archives are not required in the final output
# set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin) # .a/.lib for linker
set(CMAKE_PDB_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}) # .pdb for debugging

# Make sure QTDIR environment variable is set
if(NOT $ENV{QTDIR})
    if(UNIX)
        # Attempt to search version directories
        file(GLOB QTDIR_TEMP $ENV{HOME}/Qt/[0-9].[0-9].[0-9])
        if(EXISTS ${QTDIR_TEMP})
            # Match latest version directory
            list(GET QTDIR_TEMP -1 QTDIR_TEMP)
            if(EXISTS ${QTDIR_TEMP}/gcc_64)
                set(QTDIR ${QTDIR_TEMP}/gcc_64)
                set(ENV{QTDIR} ${QTDIR})
            endif()
        endif()
    endif()

    # Check again, since only Linux was handled
    if(NOT DEFINED ENV{QTDIR} AND NOT DEFINED QTDIR)
        message(FATAL_ERROR "Need to set QTDIR environment variable!")
    endif()
endif()
set(QTDIR $ENV{QTDIR})
message(STATUS "QTDIR: $ENV{QTDIR}")

# Use C++17
set(CMAKE_CXX_STANDARD 17)

# Download OS's deployqt
if(UNIX)
    # Download linuxdeployqt
    if(APPLE)
        # MacOS
        # https://doc.qt.io/qt-5/macos.html
        message(FATAL_ERROR "Need to prepare deployqt for MacOS!")
    else()
        # Linux
        # https://wiki.qt.io/Deploying_a_Qt5_Application_Linux
        if(NOT EXISTS ${CMAKE_SOURCE_DIR}/linuxdeployqt.AppImage)
            file(DOWNLOAD
                https://github.com/probonopd/linuxdeployqt/releases/download/continuous/linuxdeployqt-continuous-x86_64.AppImage
                ${CMAKE_SOURCE_DIR}/linuxdeployqt.AppImage
                SHOW_PROGRESS
            )
        endif()

        if(EXISTS ${CMAKE_SOURCE_DIR}/linuxdeployqt.AppImage)
            execute_process(
                COMMAND chmod a+x linuxdeployqt.AppImage
                WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
                ERROR_QUIET
            )
        endif()
    endif()
else()
    # Windows
    # https://wiki.qt.io/Deploy_an_Application_on_Windows
    message(FATAL_ERROR "Need to prepare deployqt for Windows!")
endif()

#======================= INCLUSION OF Qt =======================#
set(CMAKE_INCLUDE_CURRENT_DIR ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_PREFIX_PATH $ENV{QTDIR})
find_package(Qt6Core REQUIRED)
find_package(Qt6Widgets REQUIRED)

# RPATH for UNIX-like OS
# https://crascit.com/2019/10/16/cppcon-2019-deep-cmake-for-library-authors/#comment-315
if(APPLE)
    set(CMAKE_INSTALL_RPATH "@loader_path;@loader_path/../lib")
elseif(UNIX)
    set(CMAKE_INSTALL_RPATH "$ORIGIN:$ORIGIN/../lib")
endif()

#=================== INCLUSION OF Project Files ====================#
set(FORMS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/forms)
set(INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)

include_directories(
    ${FORMS_DIR}
    ${INCLUDE_DIR}
    ${SOURCE_DIR}
)

file(GLOB_RECURSE SOURCES
    ${FORMS_DIR}/*.ui
    ${FORMS_DIR}/*.qrc
    ${INCLUDE_DIR}/*.h
    ${SOURCE_DIR}/*.cpp
)

#=================== SETUP EXECTUABLE ====================#
# Enable debug logging on RELWITHDEBINFO configuration
# Multi-config
add_compile_definitions($<$<CONFIG:RELWITHDEBINFO>:QT_MESSAGELOGCONTEXT>)
# Single-config
if(${CMAKE_BUILD_TYPE} MATCHES "Debug" OR ${CMAKE_BUILD_TYPE} MATCHES "RelWithDebInfo")
    add_compile_definitions(QT_MESSAGELOGCONTEXT)
endif()

# Add the forms directory to the AUTOUIC search paths
set(CMAKE_AUTOUIC_SEARCH_PATHS ${CMAKE_AUTOUIC_SEARCH_PATHS} ${FORMS_DIR})

# Add WIN32 so that Windows won't have a terminal popup alongside the GUI.
if (WIN32)
    set(SOURCES ${SOURCES} WIN32)
endif()

# Add the executable
add_executable(${ProjectId} ${SOURCES})

#===================== LINKING LIBRARIES =======================#
target_link_libraries(${ProjectId} Qt6::Widgets)

if(${QT_DEPLOY})
    if(UNIX)
        if(NOT APPLE)
            add_custom_command(TARGET ${ProjectId} POST_BUILD
                COMMAND export PATH=$ENV{PATH}:${QTDIR}/bin
                COMMAND export LD_LIBRARY_PATH=${QTDIR}/lib
                COMMAND ./linuxdeployqt.AppImage $<TARGET_FILE:${ProjectId}> -always-overwrite -no-strip -no-translations -verbose=2
                WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
            )
        endif()
    endif()
endif()