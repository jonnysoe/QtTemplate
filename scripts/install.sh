#!/bin/bash

# Stop user from running the script as root as there are commands that uses sudo explicitly!
# https://stackoverflow.com/a/28776100
if [ `id -u` -eq 0 ]; then
    echo "Do not run as sudo/root!"
    exit 1
fi

# S{BASH_SOURCE[0]} - is valid when script was called with `source`
# S{0} - is valid when script was executed normally, eg. `.`, `bash`
SCRIPT_SOURCE=${BASH_SOURCE[0]:?${0}}
SCRIPT_PATH=`realpath ${SCRIPT_SOURCE}`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
pushd ${SCRIPT_DIR} > /dev/null

function install_deb() {
    # Essential C++ (GCC)
    sudo apt install -y \
        git \
        build-essential \
        cmake ninja-build ccache \
        python3-dev python-is-python3

    # Optional LLVM/Clang 17 for developer
    local clangv=17
    if ! command -v clang-${clangv} &> /dev/null; then
        wget https://apt.llvm.org/llvm.sh
        chmod a+x llvm.sh
        sudo ./llvm.sh ${clangv} all
        rm -f ./llvm.sh

        # Don't overwrite symlinks, so that the default version can stick around when developer set it
        if ! command -v clang &> /dev/null; then
            sudo ln -sfT `command -v clang-${clangv}` /usr/bin/clang
        fi
        if ! command -v clang++ &> /dev/null; then
            sudo ln -sfT `command -v clang++-${clangv}` /usr/bin/clang++
        fi
        if ! command -v clang-cl &> /dev/null; then
            sudo ln -sfT `command -v clang-cl-${clangv}` /usr/bin/clang-cl
        fi
        if ! command -v clangd &> /dev/null; then
            sudo ln -sfT `command -v clangd-${clangv}` /usr/bin/clangd
        fi
        if ! command -v clang-format &> /dev/null; then
            sudo ln -sfT `command -v clang-format-${clangv}` /usr/bin/clang-format
        fi
        if ! command -v clang-tidy &> /dev/null; then
            sudo ln -sfT `command -v clang-tidy-${clangv}` /usr/bin/clang-tidy
        fi
    fi

    # Qt graphic dependencies
    # https://www.wikihow.com/Install-Mesa-(OpenGL)-on-Linux-Mint
    sudo add-apt-repository -y ppa:kisak/kisak-mesa
    sudo apt install -y mesa-utils libxmu-dev libxi-dev libgl-dev glew-utils libglew-dev
    # These needs to be installed after libglew-dev
    sudo apt install -y libglewmx-dev freeglut3-dev freeglut3 mesa-common-dev

    if command -v python &> /dev/null; then
        # Install aqtinstall
        # NOTE: pip list will push notice in stderr so ignore stream 2 before grep
        pip list 2> /dev/null | grep aqtinstall > /dev/null
        if [[ $? -ne 0 ]]; then
            pip install aqtinstall
        fi

        # Qt
        mkdir -p ~/Qt
        pushd ~/Qt > /dev/null

        if [[ ! -d ./6.7.0/gcc_64 ]]; then
            python -m aqt install-qt linux desktop 6.7.0 gcc_64 -m all
        fi
        if [[ ! -d ./Tools/QtCreator ]]; then
            python -m aqt install-tool linux desktop tools_qtcreator
        fi
        if [[ ! -d ./Tools/QtInstallerFramework ]]; then
            python -m aqt install-tool linux desktop tools_ifw
        fi

        # Copy icons
        local share=~/.local/share
        cp -nr ./Tools/QtCreator/share/icons ${share}/

        # Copy the desktop application configuration file
        local desktop=${share}/applications/org.qt-project.qtcreator.desktop
        cp -n ./Tools/QtCreator/share/applications/org.qt-project.qtcreator.desktop ${desktop}

        # Patch up the desktop file
        sed -i "s@Exec=qtcreator@Exec=\"`realpath ~`/Qt/Tools/QtCreator/bin/qtcreator\"@" ${desktop}
        if [[ -z "`cat ${desktop} | grep 'text/x-qml'`" ]]; then
            sed -i "s@^MimeType=.*@&text/x-qml;@" ${desktop}
        fi
        if [[ -z "`cat ${desktop} | grep 'text/x-qt.qml'`" ]]; then
            sed -i "s@^MimeType=.*@&text/x-qt.qml;@" ${desktop}
        fi
        if [[ -z "`cat ${desktop} | grep 'text/x-qt.qbs'`" ]]; then
            sed -i "s@^MimeType=.*@&text/x-qt.qbs;@" ${desktop}
        fi

        popd > /dev/null
    fi

    # @todo Check for installed packages and exit with error code if any is missing
}

function install_rpm() {
    echo "RPM-based distros are not supported yet!"
    exit 2
}

# https://askubuntu.com/questions/41332/how-do-i-check-if-i-have-a-32-bit-or-a-64-bit-os/447306#447306
case `uname` in
    Darwin|FreeBSD)
        echo "`uname` is not supported!"
        exit 3
        ;;
    Linux)
        source /etc/os-release
        if command -v apt &> /dev/null || [[ -n "`echo ${ID} ${ID_LIKE} | grep -e ubuntu -e debian`" ]]; then
            install_deb
        elif [[ -n "`echo ${ID} ${ID_LIKE} | grep -e fedora -e rhel`" ]]; then
            install_rpm
        else
            echo "`uname` is not supported!"
            exit 4
        fi
        ;;
    *)
        # Assumed to be Windows, pass over to PowerShell
        # NOTE: Too many different flavors of Windows (with or without NT keyword) so lump them in asterisk
        powershell -File install.ps1
        exit ${?}
        ;;
esac

# Unnecessary popd in shell script
popd > /dev/null