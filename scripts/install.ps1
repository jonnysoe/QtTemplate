# This script will install things into system directories so it needs to run as administrator
# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_requires?view=powershell-7.4#syntax
#Requires -RunAsAdministrator

# Use this workaround because Write-Output and Write-Host will clutter function return
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
        Write-Console "Downloading $File - $Url"

        Make-Directory "$Directory"

        if (!! (Get-Command aria2c -ErrorAction SilentlyContinue)) {
            aria2c.exe -c -o "$path" $Url | ForEach-Object { Write-Console $_ }
        } else {
            curl.exe -L -o "$path" $Url | ForEach-Object { Write-Console $_ }
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

function Append-Path {
    param (
        $Destination
    )

    $expanded = $Destination.Replace("%ProgramFiles%", "$env:ProgramFiles").Replace("%USERPROFILE%", "$env:USERPROFILE")

    # Registry GetValue
    # https://superuser.com/a/1341040
    $reg = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
    if ("$expended".Contains($env:USERPROFILE)) {
        $reg = "HKCU:\Environment"
    }

    Refresh-Path
    if (! ($env:Path.Contains($expanded))) {
        $path = (Get-Item -Path $reg).GetValue("Path", "", "DoNotExpandEnvironmentNames")
        $path = ($path + ";" + $Destination).Replace(";;", ";")

        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name "Path" -Value "$path" -PropertyType ExpandString -Force

        Refresh-Path
    }
}

function Prepend-Path {
    param (
        $Destination
    )

    $expanded = $Destination.Replace("%ProgramFiles%", "$env:ProgramFiles").Replace("%USERPROFILE%", "$env:USERPROFILE")

    # Registry GetValue
    # https://superuser.com/a/1341040
    $reg = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
    if ("$expended".Contains($env:USERPROFILE)) {
        $reg = "HKCU:\Environment"
    }

    Refresh-Path
    if (! ($env:Path.Contains($expanded))) {
        $path = (Get-Item -Path $reg).GetValue("Path", "", "DoNotExpandEnvironmentNames")
        $path = ($Destination + ";" + $path).Replace(";;", ";")

        New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name "Path" -Value "$path" -PropertyType ExpandString -Force

        Refresh-Path
    }
}

function Install-Aria2 {
    $ret = !! (Get-Command aria2c -ErrorAction SilentlyContinue)
    if (! $ret) {
        $file = Download https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip
        $ret = !! ($file)

        if ($ret) {
            $ret = Extract-Archive "$file" "$env:ProgramFiles\aria2"

            if ($ret) {
                Write-Console "Successfully installed aria2"
            }
        }

        # Add or fix missing PATH
        Append-Path "%ProgramFiles%\aria2"
    }
    return $ret
}

function Install-7z {
    $ret = !! (Get-Command 7z -ErrorAction SilentlyContinue)
    if (! $ret) {
        $file = Download https://www.7-zip.org/a/7z2406-x64.msi
        $ret = !! ($file)

        if ($ret) {
            Start-Process MsiExec.exe -ArgumentList @("/i", "$file", "/qn") -wait > $null
            $ret = $?

            if ($ret) {
                Write-Console "Successfully installed 7-Zip"
            }
        }

        # Add or fix missing PATH
        Append-Path "%ProgramFiles%\7-Zip"
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
    $list = pip list 2> $null
    $ret = !! ("$list".Contains("aqtinstall"))
    if (! $ret) {
        pip.exe install aqtinstall | ForEach-Object { Write-Console $_ }
    }

    Make-Directory "$Directory"
    Push-Location "$Directory"
    if (! (Test-Path "$Version\msvc2019_64")) {
        python.exe -m aqt install-qt windows desktop "$Version" win64_msvc2019_64
    }
    if (! (Test-Path "Tools\QtCreator")) {
        python.exe -m aqt install-tool windows desktop tools_qtcreator
    }
    if (! (Test-Path "Tools\QtInstallerFramework")) {
        python.exe -m aqt install-tool windows desktop tools_ifw
    }
    $ret = (Test-Path "$Version\msvc2019_64") -And (Test-Path "Tools\QtCreator") -And (Test-Path "Tools\QtInstallerFramework")
    Pop-Location

    return $ret
}

function Script-Main {
    Refresh-Path

    if (! (Install-Aria2)) {
        Write-Console ">> Error while installing aria2!"
    }
    if (! (Install-7z)) {
        Write-Console ">> Error while installing 7-Zip!"
    }
    # if (! (Install-CMake)) {
    #     Write-Console ">> Error while installing CMake!"
    # }
    # if (! (Install-Ninja)) {
    #     Write-Console ">> Error while installing Ninja!"
    # }
    # if (! (Install-Ccache)) {
    #     Write-Console ">> Error while installing Ccache!"
    # }
    # if (! (Install-Msvc)) {
    #     Write-Console ">> Error while installing MSVC!"
    # }
    # if (! (Install-Llvm)) {
    #     Write-Console ">> Error while installing LLVM!"
    # }
    # if (! (Install-Python)) {
    #     Write-Console ">> Error while installing Python!"
    # }
    if (! (Install-Qt)) {
        Write-Console ">> Error while installing Qt!"
    }
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