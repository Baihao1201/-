<#
=====================================================================
 校园网 自动登录脚本（陕西师范大学 Portal / 可迁移版）
 --------------------------------------------------------------------
 配置文件：同目录 config.psd1（账号、密码、运营商、认证地址、重试参数）
 日志    ：同目录 logs\campus-login.log
 --------------------------------------------------------------------
 逻辑：
   1. 已能上外网 → 直接退出（不做任何多余操作，及时、省事）
   2. 否则等待网络就绪（拿到 IP / 路由），最多 waitReadySec 秒
      —— 解决"刚连上 WiFi、DHCP 还没就绪就登录导致失败"的问题
   3. 逐个端口尝试门户认证，登录后用"能否上外网"来校验是否成功
   4. 失败自动重试 maxRounds 轮
 --------------------------------------------------------------------
 手动运行：
   powershell -NoProfile -ExecutionPolicy Bypass -File "本脚本"
 强制断开并重新登录（排查用）：
   powershell -NoProfile -ExecutionPolicy Bypass -File "本脚本" -ForceLogin
=====================================================================
#>
[CmdletBinding()]
param(
    [switch]$ForceLogin
)

# ===================== 默认配置（会被 config.psd1 覆盖）=====================
$defaults = @{
    account            = ''
    password           = ''
    carrier            = 'unicom'
    portalHost         = '202.117.144.205'
    portalPorts        = @(8603, 8602, 8601)
    internetTargets    = @('https://www.baidu.com', 'https://www.qq.com', 'https://www.163.com')
    waitReadySec       = 60
    portalTimeoutSec   = 6
    internetTimeoutSec = 4
    maxRounds          = 8
    retryDelaySec      = 3
}
# ==========================================================================

$ScriptDir  = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ConfigPath = Join-Path $ScriptDir 'config.psd1'
$LogDir     = Join-Path $ScriptDir 'logs'
$LogFile    = Join-Path $LogDir 'campus-login.log'

# ---------------------- 读取配置 ----------------------
$cfg = @{}
foreach ($k in $defaults.Keys) { $cfg[$k] = $defaults[$k] }
$configError = $null
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $userCfg = Import-PowerShellDataFile -LiteralPath $ConfigPath -ErrorAction Stop
        if ($userCfg) { foreach ($k in $userCfg.Keys) { $cfg[$k] = $userCfg[$k] } }
    } catch {
        $configError = $_.Exception.Message
    }
}
$cfg.portalPorts     = @($cfg.portalPorts)
$cfg.internetTargets = @($cfg.internetTargets)

$script:HasCurl = [bool](Get-Command curl.exe -ErrorAction SilentlyContinue)

# ---------------------- 日志 ----------------------
function Write-Log {
    param([string]$Msg)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        # 日志超过 512KB 时只保留末尾 200 行，避免无限增长
        if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item -LiteralPath $LogFile).Length -gt 524288)) {
            $tail = Get-Content -LiteralPath $LogFile -Tail 200 -Encoding UTF8
            Set-Content -LiteralPath $LogFile -Value $tail -Encoding UTF8
        }
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    } catch { }
    Write-Output $line
}

# ---------------------- HTTP 基础 ----------------------
# 发请求（跟随跳转）；返回 { Status, FinalUri }；网络不可达返回 $null
function Invoke-Http {
    param([string]$Uri, [string]$Method = 'Get', $Body = $null, [int]$TimeoutSec = 0)
    if ($TimeoutSec -le 0) { $TimeoutSec = [int]$cfg.portalTimeoutSec }
    try {
        $p = @{ Uri = $Uri; Method = $Method; UseBasicParsing = $true; TimeoutSec = $TimeoutSec; ErrorAction = 'Stop' }
        if ($null -ne $Body) { $p['Body'] = $Body }
        $r = Invoke-WebRequest @p
        $final = $Uri
        if ($r.BaseResponse -and $r.BaseResponse.ResponseUri) { $final = $r.BaseResponse.ResponseUri.AbsoluteUri }
        return [pscustomobject]@{ Status = [int]$r.StatusCode; FinalUri = [string]$final }
    } catch {
        return $null
    }
}

# 外网是否可用：任一目标返回 200/204 即视为「能上网」
# 注意：不跟随跳转 —— 未认证时校园网门户会把外网请求重定向到门户登录页，
#       若跟随跳转可能被门户页面骗成"已联网"，导致漏登录。
function Test-Internet {
    param([int]$MaxTime = 0, [int]$MaxTargets = 0)
    if ($MaxTime -le 0) { $MaxTime = [int]$cfg.internetTimeoutSec }
    $list = @($cfg.internetTargets)
    if ($MaxTargets -gt 0 -and $list.Count -gt $MaxTargets) { $list = $list[0..($MaxTargets - 1)] }
    foreach ($t in $list) {
        if ($script:HasCurl) {
            $out = & curl.exe -s -o NUL -w '%{http_code}' --connect-timeout 2 --max-time $MaxTime $t 2>$null
            if ("$out" -eq '200' -or "$out" -eq '204') { return $true }
        } else {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $r = Invoke-WebRequest -Uri $t -UseBasicParsing -TimeoutSec $MaxTime -ErrorAction Stop
                if ([int]$r.StatusCode -eq 200 -or [int]$r.StatusCode -eq 204) { return $true }
            } catch { }
        }
    }
    return $false
}

# 门户是否可达（拿到任何 HTTP 响应即视为可达）
function Test-PortalReachable {
    param([int]$Port, [int]$TimeoutSec = 0)
    $res = Invoke-Http -Uri ("http://{0}:{1}/snnuportal/login.jsp" -f $cfg.portalHost, $Port) -TimeoutSec $TimeoutSec
    return ($null -ne $res)
}

# 提交登录；返回 $true=请求已送达
function Invoke-PortalLogin {
    param([int]$Port)
    $body = @{
        sourceurl = 'null'
        account   = $cfg.account
        password  = $cfg.password
        yys       = $cfg.carrier
        issave    = ''
    }
    $res = Invoke-Http -Uri ("http://{0}:{1}/snnuportal/login" -f $cfg.portalHost, $Port) -Method 'Post' -Body $body
    return ($null -ne $res)
}

# 断开连接（仅 -ForceLogin 使用）
function Invoke-PortalLogoff {
    param([int]$Port)
    $null = Invoke-Http -Uri ("http://{0}:{1}/snnuportal/logoff" -f $cfg.portalHost, $Port) -Method 'Post'
}

# 等待网络就绪：返回 'online'(已能上网) / 'portal'(门户可达，需认证) / 'none'(都没有)
function Wait-NetworkReady {
    param([int]$TimeSec)
    $deadline  = (Get-Date).AddSeconds($TimeSec)
    $firstPort = [int]$cfg.portalPorts[0]
    while ($true) {
        if (Test-Internet -MaxTime 2 -MaxTargets 2) { return 'online' }
        if (Test-PortalReachable -Port $firstPort -TimeoutSec 2) { return 'portal' }
        if ((Get-Date) -ge $deadline) { return 'none' }
        Start-Sleep -Milliseconds 1000
    }
}

# ===================== 主逻辑 =====================
if ($configError) { Write-Log ("警告：config.psd1 读取失败，已使用默认配置（{0}）" -f $configError) }
Write-Log ("开始检测（账号 {0} / 运营商 {1}）" -f $cfg.account, $cfg.carrier)

# 1) 快速路径：已经能上网就直接退出，不做任何多余动作
if ((-not $ForceLogin) -and (Test-Internet)) {
    Write-Log '外网正常，已在线，无需重连。'
    exit 0
}

# 2) 等待网络就绪（覆盖刚连上 WiFi / 刚插网线时 DHCP 还没好的情况）
$state = Wait-NetworkReady -TimeSec ([int]$cfg.waitReadySec)
if ($state -eq 'online' -and -not $ForceLogin) {
    Write-Log '外网正常，已在线，无需重连。'
    exit 0
}
if ($state -eq 'none' -and -not $ForceLogin) {
    Write-Log ("网络未就绪（已等待 {0} 秒），本次退出，等下次触发。" -f $cfg.waitReadySec)
    exit 1
}

# 3) 尝试登录（多端口 + 多轮重试）
$done = $false
for ($round = 1; $round -le [int]$cfg.maxRounds -and -not $done; $round++) {
    foreach ($port in $cfg.portalPorts) {
        $port = [int]$port
        if (-not (Test-PortalReachable -Port $port)) { continue }

        if ($ForceLogin) {
            Write-Log ("强制登录：先断开连接 (端口 {0}) ..." -f $port)
            Invoke-PortalLogoff -Port $port
            Start-Sleep -Seconds 1
        }

        Write-Log ("正在登录校园网 (端口 {0}) ..." -f $port)
        if (-not (Invoke-PortalLogin -Port $port)) {
            Write-Log ("登录请求未送达 (端口 {0})。" -f $port)
            continue
        }

        # 登录后校验：外网是否真的恢复
        for ($i = 0; $i -lt 6; $i++) {
            Start-Sleep -Milliseconds 800
            if (Test-Internet) { $done = $true; break }
        }
        if ($done) { Write-Log ("登录成功，外网已恢复 (端口 {0})。" -f $port); break }
        Write-Log ("已提交登录，但外网仍未恢复 (端口 {0})。" -f $port)
    }

    if (-not $done -and $round -lt [int]$cfg.maxRounds) {
        Write-Log ("第 {0} 轮未成功，{1} 秒后重试..." -f $round, $cfg.retryDelaySec)
        Start-Sleep -Seconds ([int]$cfg.retryDelaySec)
    }
}

# 4) 结果
if (Test-Internet) {
    Write-Log '结果：外网已连接。'
    exit 0
} else {
    Write-Log '结果：仍未连接外网。'
    exit 1
}
