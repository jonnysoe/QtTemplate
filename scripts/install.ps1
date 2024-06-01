# This script will install things into system directories so it needs to run as administrator
# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_requires?view=powershell-7.4#syntax
#Requires -RunAsAdministrator

# Use this workaround because Write-Output and Write-Host will clutter function return,
# that is until a better method was discovered...
# https://stackoverflow.com/a/10288256/19336104
function Write-Console {
    param (
        $Text
    )
    Write-Information $Text -InformationAction Continue
}

function Get-Parent-Name {
    param (
        $Path
    )
    Split-Path -Path "$Path" -Parent
}

function Get-Base-Name {
    param (
        $Path
    )
    Split-Path -Path "$Path" -Leaf
}

function Make-Directory {
    param (
        $Path
    )

    # Create directory
    # -Force - similar to "mkdir --parents" to create nested directories
    #    https://stackoverflow.com/a/20983885/19336104
    # -ErrorAction SilentlyContinue - parents will also not error out if directory already exist
    #    https://serverfault.com/a/336139
    New-Item -Path "$Path" -Type directory -Force -ErrorAction SilentlyContinue > $null
}

function Remove-Directory {
    param (
        $Path
    )
    Remove-Item -Path "$Path" -Recurse -ErrorAction SilentlyContinue
}

function Empty-Directory {
    param (
        $Path
    )
    return ! (Test-Path "$Path\*")
}

function Extract-Archive {
    param (
        $Archive,
        $Destination
    )
    if (! $Destination) {
        $Destination = Get-Location
    }

    Write-Console "Extracting $Archive . . ."

    if (Get-Command 7z -ErrorAction SilentlyContinue) {
        7z.exe e "$Archive" -o"$Destination" | ForEach-Object { Write-Console $_ }
    } else {
        # Use native if 7z haven't been installed
        Make-Directory "$Destination"
        Expand-Archive -LiteralPath $Archive -DestinationPath "zip"
        $extracted = Resolve-Path "zip\*"
        Move-Item -Path "$extracted\*" -Destination $Destination -Force
        Remove-Directory "zip"
    }

    return ! (Empty-Directory "$Destination")
}

function Download {
    param (
        $Url,
        $File,
        $Directory
    )
    if (! $File) {
        $File = Get-Base-Name ([uri]::UnescapeDataString($Url).Replace(" ", "_"))
    }
    if (! $Directory) {
        $Directory = "temp"
    }
    $path = "$Directory\$File"

    if (! (Test-Path -Path "$path")) {
        # Download when file is not available
        Write-Console "Downloading $File - $Url . . ."

        Make-Directory "$Directory"

        if (!! (Get-Command aria2c -ErrorAction SilentlyContinue)) {
            aria2c.exe -c -o "$path" $Url > $null
        } else {
            curl.exe -L -o "$path" $Url > $null
        }

        if (! (Test-Path -Path "$path")) {
            $path = ""
        }
    }

    return $path
}

function Refresh-Path {
    # https://stackoverflow.com/a/31845512/19336104
    $env:Path = ([System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")).Replace(";;", ";")
}

function Expand-Path {
    param (
        $Destination
    )
    return $Destination.Replace("%ProgramFiles%", "$env:ProgramFiles").Replace("%USERPROFILE%", "$env:USERPROFILE")
}

function Collapse-Path {
    param (
        $Destination
    )
    return $Destination.Replace("$env:ProgramFiles", "%ProgramFiles%").Replace("$env:USERPROFILE", "%USERPROFILE%")
}

function Add-Path {
    param (
        $Destination,
        [bool]$Prepend
    )

    $expanded = Expand-Path $Destination

    Refresh-Path
    if (! ($env:Path.Contains($expanded))) {

        # Use .NET's RegistryKey.GetValue because Get-ItemProperty cannot keep string as ExpandString (REG_EXPAND_SZ)
        # https://superuser.com/a/1341040
        $reg = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
        if ("$expanded".Contains($env:USERPROFILE)) {
            $reg = "HKCU:\Environment"
        }

        $key = Get-Item -Path $reg
        $path = $key.GetValue("Path", "", "DoNotExpandEnvironmentNames")

        if (! $Prepend) {
            $path = ($path + ";" + $Destination).Replace(";;", ";")
        } else {
            $path = ($Destination + ";" + $path).Replace(";;", ";")
        }

        # Collapse all path instead of just new Destination
        $path = Collapse-Path $path

        # Use PS's New-ItemProperty because older PS errors out on RegistryKey.SetValue's overload with RegistryValueKind.ExpandString
        New-ItemProperty -Path "$reg" -Name "Path" -Value "$path" -PropertyType ExpandString -Force

        Refresh-Path
    }
}

function Append-Path {
    param (
        $Destination
    )

    Add-Path $Destination $false
}

function Prepend-Path {
    param (
        $Destination
    )

    Add-Path $Destination $true
}

# Common Archive
function Install-Aria2 {
    $program = "aria2c"
    # Check if command is valid
    $ret = !! (Get-Command $program -ErrorAction SilentlyContinue)
    if (! $ret) {
        $name = "aria2"
        $dir = "$env:ProgramFiles\aria2"
        $link = "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip"
        # https://github.com/aria2/aria2/releases/latest

        # Check if program was installed
        if (Empty-Directory "$dir") {
            # Download
            $file = Download $link
            $ret = !! ($file)

            # Install
            if ($ret) {
                Write-Console "Installing $name . . ."
                $ret = Extract-Archive "$file" "$dir"

                if ($ret) {
                    Write-Console "Successfully installed $name."
                }
            }
        }

        # Add or fix missing PATH
        Append-Path "$dir"
    }
    return $ret
}

# Common MSI
function Install-7z {
    $program = "7z"
    # Check if command is valid
    $ret = !! (Get-Command $program -ErrorAction SilentlyContinue)
    if (! $ret) {
        $name = "7-Zip"
        $dir = "$env:ProgramFiles\7-Zip"
        $link = "https://www.7-zip.org/a/7z2406-x64.msi"
        # https://www.7-zip.org/download.html

        # Check if program was installed
        if (Empty-Directory "$dir") {
            # Download
            $file = Download $link
            $ret = !! ($file)

            # Install
            if ($ret) {
                Write-Console "Installing $name . . ."
                Start-Process MsiExec.exe -ArgumentList @("/i", "$file", "/qn") -wait > $null
                $ret = $?

                if ($ret) {
                    Write-Console "Successfully installed $name."
                }
            }
        }

        # Add or fix missing PATH
        Append-Path "$dir"
    }
    return $ret
}

# Common MSI
function Install-Cmake {
    $program = "cmake"
    # Check if command is valid
    $ret = !! (Get-Command $program -ErrorAction SilentlyContinue)
    if (! $ret) {
        $name = "CMake"
        $dir = "$env:ProgramFiles\CMake\bin"
        $link = "https://github.com/Kitware/CMake/releases/download/v3.29.3/cmake-3.29.3-windows-x86_64.msi"
        # https://github.com/Kitware/CMake/releases/latest

        # Check if program was installed
        if (Empty-Directory "$dir") {
            # Download
            $file = Download $link
            $ret = !! ($file)

            # Install
            if ($ret) {
                Write-Console "Installing $name . . ."
                Start-Process MsiExec.exe -ArgumentList @("/i", "$file", "/qn") -wait > $null
                $ret = $?

                if ($ret) {
                    Write-Console "Successfully installed $name."
                }
            }
        }

        # Add or fix missing PATH
        Append-Path "$dir"
    }
    return $ret
}

# Common Archive
function Install-Ninja {
    $program = "ninja"
    # Check if command is valid
    $ret = !! (Get-Command $program -ErrorAction SilentlyContinue)
    if (! $ret) {
        $name = "Ninja"
        $dir = "$env:ProgramFiles\Ninja"
        $link = "https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-win.zip"
        # https://github.com/ninja-build/ninja/releases/latest

        # Check if program was installed
        if (Empty-Directory "$dir") {
            # Download
            $file = Download $link
            $ret = !! ($file)

            # Install
            if ($ret) {
                Write-Console "Installing $name . . ."
                $ret = Extract-Archive "$file" "$dir"

                if ($ret) {
                    Write-Console "Successfully installed $name."
                }
            }
        }

        # Add or fix missing PATH
        Append-Path "$dir"
    }
    return $ret
}

# Common Archive
function Install-Ccache {
    $program = "ccache"
    # Check if command is valid
    $ret = !! (Get-Command $program -ErrorAction SilentlyContinue)
    if (! $ret) {
        $name = "Ccache"
        $dir = "$env:ProgramFiles\Ccache"
        $link = "https://github.com/ccache/ccache/releases/download/v4.10/ccache-4.10-windows-x86_64.zip"
        # https://github.com/ccache/ccache/releases/latest

        # Check if program was installed
        if (Empty-Directory "$dir") {
            # Download
            $file = Download $link
            $ret = !! ($file)

            # Install
            if ($ret) {
                Write-Console "Installing $name . . ."
                $ret = Extract-Archive "$file" "$dir"

                if ($ret) {
                    Write-Console "Successfully installed $name."
                }
            }
        }

        # Add or fix missing PATH
        Append-Path "$dir"
    }
    return $ret
}

# Unique Executable
function Install-Msvc {
    $program = "Get-Command"
    # Check if command is valid
    $ret = !! (Get-Command $program -ErrorAction SilentlyContinue)
    if (! $ret) {
        $name = "Microsoft C++ Build Tools"
        $dir = "$env:ProgramFiles\Microsoft Visual Studio"
        $link = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
        # https://visualstudio.microsoft.com/visual-cpp-build-tools/

        # Check if program was installed
        if (Empty-Directory "$dir") {
            # Download
            $file = Download $link
            $ret = !! ($file)

            # Install
            if ($ret) {
                Write-Console "Installing $name . . ."

                # https://dimitri.janczak.net/2018/10/22/visual-c-build-tools-silent-installation/
                # https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=vs-2019
                Start-Process "$file" -ArgumentList @("--add", "Microsoft.VisualStudio.Workload.VCTools", "--includeRecommended", "--includeOptional", "--passive", "--norestart", "--wait") -Wait > $null
                $ret = $?

                if ($ret) {
                    Write-Console "Successfully installed $name."
                }
            }
        }

        # MSVC does not add PATH
        # Append-Path "$dir"
    }
    return $ret
}

# Unique Executable
# Requires Windows SDK (also installed by MSVC)
function Install-Llvm {
    $program = "clang"
    # Check if command is valid
    $ret = !! (Get-Command $program -ErrorAction SilentlyContinue)
    if (! $ret) {
        $name = "LLVM"
        $dir = "$env:ProgramFiles\LLVM\bin"
        $link = "https://github.com/llvm/llvm-project/releases/download/llvmorg-17.0.6/LLVM-17.0.6-win64.exe"
        # https://github.com/llvm/llvm-project/releases/latest

        # Check if program was installed
        if (Empty-Directory "$dir") {
            # Download
            $file = Download $link
            $ret = !! ($file)

            # Install
            if ($ret) {
                Write-Console "Installing $name . . ."

                # Install in quiet/silent mode
                Start-Process "$file" -ArgumentList "/S" -Wait
                $ret = $?

                if ($ret) {
                    Write-Console "Successfully installed $name."
                }
            }
        }

        # Add or fix missing PATH
        Append-Path "$dir"
    }
    return $ret
}

# Unique Executable
# Requires MSVC in pip (since 3.11)
function Install-Python {
    $program = "python"
    # Check if command is valid
    $ret = !! (Get-Command $program -ErrorAction SilentlyContinue)
    if (! $ret) {
        $name = "Python"
        $dir = "$env:ProgramFiles\Python312"
        $link = "https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe"
        # https://www.python.org/downloads/

        # Check if program was installed
        if (Empty-Directory "$dir") {
            # Download
            $file = Download $link
            $ret = !! ($file)

            # Install
            if ($ret) {
                Write-Console "Installing $name . . ."

                # Install in quiet/silent mode
                Start-Process "$file" -ArgumentList @("/quiet", "InstallAllUsers=1", "PrependPath=1", "AssociateFiles=1") -Wait
                $ret = $?

                if ($ret) {
                    Write-Console "Successfully installed $name."
                }
            }
        }

        # Add or fix missing PATH
        Prepend-Path "$dir"
        Prepend-Path "$dir\Scripts"
    }
    return $ret
}

function Install-Qt {
    param (
        $Version,
        $Directory
    )
    if (! $Version) {
        $Version = "6.7.0"
    }
    if (! $Directory) {
        $Directory = "C:\Qt"
    }

    # NOTE: pip list will push notice in stderr so ignore stream 2 before grep
    $list = pip.exe list 2> $null
    $ret = !! ("$list".Contains("aqtinstall"))
    if (! $ret) {
        Write-Console "Installing aqtinstall . . ."
        pip.exe install aqtinstall > $null
        $ret = $?
    }

    Make-Directory "$Directory"
    Push-Location "$Directory"
    $check = $false
    if (! (Test-Path "$Version\msvc2019_64")) {
        Write-Console "Installing Qt Core $Version . . ."
        python.exe -m aqt install-qt windows desktop "$Version" win64_msvc2019_64 > $null
        $check = $true
    }
    if (! (Test-Path "Tools\QtCreator")) {
        Write-Console "Installing Qt Creator . . ."
        python.exe -m aqt install-tool windows desktop tools_qtcreator > $null
        $check = $true
    }
    if (! (Test-Path "Tools\QtInstallerFramework")) {
        Write-Console "Installing Qt Installer Framework . . ."
        python.exe -m aqt install-tool windows desktop tools_ifw > $null
        $check = $true
    }

    if ($check) {
        $ret = (Test-Path "$Version\msvc2019_64") -And (Test-Path "Tools\QtCreator") -And (Test-Path "Tools\QtInstallerFramework")
        if ($ret) {
            Write-Console "Successfully installed Qt Framework."
        }
    }

    Pop-Location

    return $ret
}

function Script-Main {
    Refresh-Path

    Write-Console "Starting dependency installation script . . ."

    if (! (Install-Aria2)) {
        Write-Console ">> Error while installing aria2!"
    }
    if (! (Install-7z)) {
        Write-Console ">> Error while installing 7-Zip!"
    }
    if (! (Install-Cmake)) {
        Write-Console ">> Error while installing CMake!"
    }
    if (! (Install-Ninja)) {
        Write-Console ">> Error while installing Ninja!"
    }
    if (! (Install-Ccache)) {
        Write-Console ">> Error while installing Ccache!"
    }
    if (! (Install-Msvc)) {
        Write-Console ">> Error while installing MSVC!"
    }
    if (! (Install-Llvm)) {
        Write-Console ">> Error while installing LLVM!"
    }
    if (! (Install-Python)) {
        Write-Console ">> Error while installing Python!"
    }
    if (! (Install-Qt)) {
        Write-Console ">> Error while installing Qt!"
    }

    Write-Console "End of dependency installation script."
}

Push-Location $PSScriptRoot

try {
    Script-Main
} catch {
    # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_try_catch_finally?view=powershell-7.4#accessing-exception-information
    Write-Host -ForegroundColor red $_
    Write-Host -ForegroundColor red $_.ScriptStackTrace
} finally {
    Pop-Location
}