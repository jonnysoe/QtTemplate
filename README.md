# Qt (CMake) Template

Adapted from the following:
https://youtu.be/XiMplRfuFJc

## Requirements

There requirements can be installed with the dependency installer script.

Linux:
```
./scripts/install.sh
```
Windows (cmd):
```
.\scripts\install.cmd
```
Windows (powershell):
```
Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force
.\scripts\install.ps1
```

- [CMake](https://cmake.org/download/)
- [Ninja](https://ninja-build.org/)
- C++ Compiler ([gcc](https://gcc.gnu.org/releases.html), [clang](https://llvm.org/), [msvc](https://visualstudio.microsoft.com/visual-cpp-build-tools/))
- [Python](https://www.python.org/downloads/) - [python-is-python3](https://packages.ubuntu.com/focal/python-is-python3) for Linux

### Linux (Debian-based)
- [X11 Requirements](https://doc.qt.io/qt-6/linux-requirements.html):
```
sudo apt install -y libgl1-mesa-dev libxkbcommon-x11-0 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-xinerama0 libxcb-icccm4
```
- [OpenGL](https://www.wikihow.com/Install-Mesa-(OpenGL)-on-Linux-Mint):
```
sudo add-apt-repository -y ppa:kisak/kisak-mesa
sudo apt install -y mesa-utils libxmu-dev libxi-dev libgl-dev glew-utils libglew-dev
sudo apt install -y libglewmx-dev freeglut3-dev freeglut3 mesa-common-dev
```
- [Qt Framework](https://www.qt.io/download-open-source) - needs to be installed manually, or use [aqtinstall](https://github.com/miurahr/aqtinstall)
```
mkdir -p ~/Qt
cd ~/Qt
pip install aqtinstall
python -m aqt install-qt linux desktop 6.7.0 -m all
```
- Optionally set Environment variable:
```
export QTDIR=~/Qt/6.7.0/gcc_64
```
- [linuxdeployqt](https://github.com/probonopd/linuxdeployqt) - optional, see [walkthrough](https://wiki.qt.io/Deploying_a_Qt5_Application_Linux) for more information

### Windows
Windows dependencies are easier since OpenGL will be automatically installed, so its is not an explicit requirement.
- [Qt Framework](https://www.qt.io/download-open-source) - needs to be installed manually, or use [aqtinstall](https://github.com/miurahr/aqtinstall)
```
mkdir C:\Qt
cd C:\Qt
pip install aqtinstall
python -m aqt install-qt windows desktop 6.7.0 win64_msvc2019_64 -m all
```
- Optionally set Environment variable:
```
setx QTDIR C:\Qt\6.7.0\msvc2019_64
```

## Build
Build and execute:
```
cmake -S . -B build -G Ninja && cmake --build build
./bin/QtTemplate
```
