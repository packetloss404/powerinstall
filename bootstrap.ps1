[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$TARGET_REF = "main"
if ($env:PI_TARGET_REF) { $TARGET_REF = $env:PI_TARGET_REF }

$BASE_URL = "https://raw.githubusercontent.com/packetloss404/powerinstall"
if ($env:PI_BASE_URL) { $BASE_URL = $env:PI_BASE_URL }

$KIT_INSTALL_URL = "${BASE_URL}/${TARGET_REF}/full-kit/Kit-Install.ps1"

Invoke-Expression ((New-Object Net.WebClient).DownloadString($KIT_INSTALL_URL))
