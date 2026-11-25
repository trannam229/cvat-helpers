# cvat-helpers installer for Windows (Docker Desktop, Linux containers).
#   install.ps1             install or update the helpers UI (installs CVAT first if none is found)
#   install.ps1 uninstall   switch CVAT back to the stock UI
# Environment overrides: CVAT_DIR (where a fresh CVAT goes), CVAT_HELPERS_IMAGE (UI image to use).
param([ValidateSet('install', 'uninstall')][string]$Action = 'install')

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$CvatVersion = 'v2.84.0'
$HelpersImage = if ($env:CVAT_HELPERS_IMAGE) { $env:CVAT_HELPERS_IMAGE } else { 'ghcr.io/trannam229/cvat-helpers:v2.84.0-helpers.1' }
$StockUiImage = "cvat/ui:$CvatVersion"
$ServerImage = "cvat/server:$CvatVersion"
$OverrideName = 'docker-compose.helpers.yml'
$CvatUrl = 'http://localhost:8080'
# Files a CVAT Compose deployment reads from disk (docker-compose.yml bind mounts included).
$CvatFiles = @(
    'docker-compose.yml',
    'components/serverless/docker-compose.serverless.yml',
    'components/analytics/grafana_conf.yml',
    'components/analytics/vector/vector.toml',
    'components/analytics/grafana/dashboards/all_events.json',
    'components/analytics/grafana/dashboards/management.json',
    'components/analytics/grafana/dashboards/monitoring.json',
    'components/analytics/grafana/dashboards/users_exceptions.json'
)

$script:Project = 'cvat'
$script:CvatDir = if ($env:CVAT_DIR) { $env:CVAT_DIR } else { Join-Path $env:USERPROFILE 'cvat' }
$script:ComposeFiles = @()
$script:Fresh = $false

function Say([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
# Errors are thrown and reported once at the end, so a one-liner run never closes the user's PowerShell.
function Fail([string]$Message) { throw $Message }
function Ask([string]$Question) { (Read-Host $Question) -match '^[yYcC]' }
function AskDefaultYes([string]$Question) { (Read-Host $Question) -notmatch '^[nNkK]' }

# Runs docker and stops the installer when it fails; its output goes to the console.
# Windows PowerShell 5.1 turns native stderr (pull progress) into errors under 'Stop', hence 'Continue' here.
function Invoke-Docker {
    $ErrorActionPreference = 'Continue'
    & docker @args
    if ($LASTEXITCODE -ne 0) { Fail "Lệnh 'docker $($args -join ' ')' bị lỗi (mã $LASTEXITCODE)." }
}

# Runs docker quietly and returns its output, or $null when it fails.
function Get-DockerOutput {
    $ErrorActionPreference = 'Continue'
    $output = & docker @args 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return $output
}

function Ensure-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Start-Process 'https://www.docker.com/products/docker-desktop/'
        Fail 'Chưa cài Docker. Cài Docker Desktop (trang tải vừa mở trong trình duyệt) rồi chạy lại.'
    }
    if ($null -eq (Get-DockerOutput info)) {
        Say 'Docker chưa chạy, đang mở Docker Desktop...'
        $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if (Test-Path $desktop) { Start-Process $desktop }
        for ($i = 0; $i -lt 60 -and $null -eq (Get-DockerOutput info); $i++) { Start-Sleep -Seconds 3 }
        if ($null -eq (Get-DockerOutput info)) { Fail 'Docker vẫn chưa chạy. Mở Docker Desktop, đợi báo Running rồi chạy lại.' }
    }
    if ($null -eq (Get-DockerOutput compose version)) { Fail "Cần Docker Compose v2 (lệnh 'docker compose')." }
}

function Test-ArmHost { $env:PROCESSOR_ARCHITECTURE -eq 'ARM64' }

# CVAT publishes some images for amd64 only; Docker Desktop runs them under emulation on ARM.
function Ensure-Image([string]$Image, [string]$Platform = '') {
    if ($null -ne (Get-DockerOutput image inspect $Image)) { return }
    Say "Tải image $Image"
    if ($Platform) { Invoke-Docker pull --platform $Platform $Image } else { Invoke-Docker pull $Image }
}

# Fills Project, CvatDir and ComposeFiles from the running cvat_server container.
function Find-RunningCvat {
    $json = Get-DockerOutput inspect cvat_server --format '{{json .Config.Labels}}'
    if ($null -eq $json) { return $false }
    $labels = ($json -join '') | ConvertFrom-Json
    $script:Project = $labels.'com.docker.compose.project'
    $script:CvatDir = $labels.'com.docker.compose.project.working_dir'
    $script:ComposeFiles = @()
    foreach ($file in ($labels.'com.docker.compose.project.config_files' -split ',')) {
        if ((Split-Path $file -Leaf) -eq $OverrideName) { continue }
        if (-not (Test-Path -LiteralPath $file)) {
            Fail "CVAT đang chạy dùng file $file nhưng Windows không thấy file này (CVAT được khởi động từ WSL?). Khi đó chạy scripts/install.sh bên trong WSL."
        }
        $script:ComposeFiles += $file
    }
    if ($script:ComposeFiles.Count -eq 0) { Fail 'Không đọc được danh sách file Compose của CVAT đang chạy.' }
    return $true
}

function Download-Cvat {
    Say "Chưa thấy CVAT trên máy. Cài CVAT $CvatVersion vào $script:CvatDir"
    foreach ($file in $CvatFiles) {
        $target = Join-Path $script:CvatDir $file
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/cvat-ai/cvat/$CvatVersion/$file" -OutFile $target
        } catch {
            Fail "Không tải được $file từ GitHub. Kiểm tra mạng rồi chạy lại."
        }
    }
}

function Compose {
    $composeArgs = @('compose', '-p', $script:Project)
    foreach ($file in $script:ComposeFiles) { $composeArgs += @('-f', $file) }
    Invoke-Docker @composeArgs @args
}

function Wait-ForCvat {
    Say 'Đợi CVAT khởi động (lần đầu có thể mất vài phút)...'
    for ($i = 0; $i -lt 120; $i++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "$CvatUrl/api/server/about" -TimeoutSec 5 | Out-Null
            return
        } catch { Start-Sleep -Seconds 5 }
    }
    Fail "CVAT chưa trả lời ở $CvatUrl sau 10 phút. Xem log: docker logs cvat_server"
}

function Install-Helpers {
    if (Find-RunningCvat) {
        $running = (Get-DockerOutput inspect cvat_server --format '{{.Config.Image}}') -join ''
        Say "Tìm thấy CVAT đang chạy: $running ($script:CvatDir)"
        if (-not $running.EndsWith(":$CvatVersion")) {
            Write-Host "Helpers được build cho CVAT $CvatVersion, máy này đang chạy $running. Giao diện có thể lỗi với backend khác phiên bản."
            if (-not (Ask 'Vẫn cài? (y/N)')) { Fail "Đã huỷ. Nâng/hạ CVAT về $CvatVersion rồi chạy lại." }
        }
    } elseif (Test-Path (Join-Path $script:CvatDir 'docker-compose.yml')) {
        Say "Dùng CVAT có sẵn ở $script:CvatDir (đang tắt)"
        $script:ComposeFiles = @((Join-Path $script:CvatDir 'docker-compose.yml'))
        $script:Fresh = $true
    } else {
        Download-Cvat
        $script:ComposeFiles = @((Join-Path $script:CvatDir 'docker-compose.yml'))
        $script:Fresh = $true
    }

    Ensure-Image $HelpersImage
    $override = Join-Path $script:CvatDir $OverrideName
    $content = "# Written by the cvat-helpers installer: CVAT UI with the 3D helpers.`nservices:`n  cvat_ui:`n    image: $HelpersImage`n"
    [IO.File]::WriteAllText($override, $content)  # UTF-8 without BOM
    $script:ComposeFiles += $override

    if ($script:Fresh) {
        if (Test-ArmHost) { Ensure-Image $ServerImage 'linux/amd64' }
        Say 'Khởi động CVAT'
        Compose up -d
    } else {
        Say 'Thay giao diện CVAT bằng bản helpers'
        Compose up -d --no-deps cvat_ui
    }

    Wait-ForCvat
    $uiImage = (Get-DockerOutput inspect cvat_ui --format '{{.Config.Image}}') -join ''
    if ($uiImage -ne $HelpersImage) { Fail "cvat_ui không chạy image $HelpersImage." }

    if ($script:Fresh -and (AskDefaultYes 'Tạo tài khoản admin cho CVAT bây giờ? (Y/n)')) {
        $ErrorActionPreference = 'Continue'
        & docker exec -it cvat_server bash -ic 'python3 ~/manage.py createsuperuser'
        $ErrorActionPreference = 'Stop'
    }

    Say "Xong. CVAT có helpers đang chạy ở $CvatUrl"
    Write-Host "Lưu ý: nếu sau này tự chạy 'docker compose up', thêm '-f $override' để giữ giao diện helpers."
    Start-Process $CvatUrl
}

function Uninstall-Helpers {
    if (-not (Find-RunningCvat)) { Fail 'Không thấy CVAT đang chạy (container cvat_server).' }
    if (Test-ArmHost) { Ensure-Image $StockUiImage 'linux/amd64' }
    Say 'Trả CVAT về giao diện gốc'
    Compose up -d --no-deps cvat_ui
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $script:CvatDir $OverrideName)
    $uiImage = (Get-DockerOutput inspect cvat_ui --format '{{.Config.Image}}') -join ''
    Say "Đã gỡ helpers. cvat_ui chạy $uiImage"
}

try {
    Ensure-Docker
    if ($Action -eq 'uninstall') { Uninstall-Helpers } else { Install-Helpers }
} catch {
    Write-Host "`n[LỖI] $($_.Exception.Message)" -ForegroundColor Red
    if ($PSCommandPath) { exit 1 }
}
