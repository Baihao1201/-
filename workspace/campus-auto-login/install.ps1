<#
=====================================================================
 校园网自动登录 - 一键安装
 --------------------------------------------------------------------
 作用：为当前 Windows 用户注册「校园网自动登录」计划任务
 用法：
   1) 先改好同目录 config.psd1（账号 / 密码 / 运营商）
   2) 双击 install.cmd（或右键 install.ps1 → 使用 PowerShell 运行）
 说明：无需管理员权限；重复运行会自动覆盖旧任务。
=====================================================================
#>
[CmdletBinding()]
param(
    [switch]$NoTest
)

$ErrorActionPreference = 'Stop'
$TaskName = 'SNNU-CampusAutoLogin'
$dir  = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ps1  = Join-Path $dir 'campus-login.ps1'
$vbs  = Join-Path $dir 'run-hidden.vbs'
$cfgP = Join-Path $dir 'config.psd1'

Write-Host '==============================================' -ForegroundColor Cyan
Write-Host '        校园网自动登录 - 安装' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan

# ---------- 检查必需文件 ----------
$missing = @()
foreach ($f in @($ps1, $vbs)) { if (-not (Test-Path -LiteralPath $f)) { $missing += $f } }
if ($missing.Count -gt 0) {
    Write-Host ('缺少文件：' + ($missing -join ', ')) -ForegroundColor Red
    exit 1
}

# ---------- 读取并显示配置 ----------
$cfg = $null
if (Test-Path -LiteralPath $cfgP) {
    try { $cfg = Import-PowerShellDataFile -LiteralPath $cfgP }
    catch { Write-Host ('config.psd1 读取失败：' + $_.Exception.Message) -ForegroundColor Yellow }
}
if ($cfg) {
    $carrierName = switch ("$($cfg.carrier)") {
        'unicom'  { '中国联通' }
        'mobile'  { '中国移动' }
        'telecom' { '中国电信' }
        default   { '校园网(默认出口)' }
    }
    Write-Host ("账号     : {0}" -f $cfg.account)
    Write-Host ("运营商   : {0}" -f $carrierName)
    Write-Host ("认证地址 : http://{0}" -f $cfg.portalHost)
} else {
    Write-Host '警告：未读到 config.psd1，脚本将使用内置默认配置。' -ForegroundColor Yellow
}
Write-Host ("安装目录 : {0}" -f $dir)
Write-Host ''

# ---------- 组装触发器 ----------
function New-EventTrigger {
    param([string]$Subscription)
    $c = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace 'Root/Microsoft/Windows/TaskScheduler'
    $t = New-CimInstance -CimClass $c -ClientOnly
    $t.Enabled      = $true
    $t.Subscription = $Subscription
    return $t
}

$user = '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME

# 网络已连接（插网线 / 连上任意 WiFi）
$subNet  = '<QueryList><Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"><Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[(EventID=10000)]]</Select></Query></QueryList>'
# WiFi 已连接（不限定 SSID，兼容 SNNU / SNNU-5G 等）
$subWlan = '<QueryList><Query Id="0" Path="Microsoft-Windows-WLAN-AutoConfig/Operational"><Select Path="Microsoft-Windows-WLAN-AutoConfig/Operational">*[System[Provider[@Name=''Microsoft-Windows-WLAN-AutoConfig''] and (EventID=8001)]]</Select></Query></QueryList>'
# 掉网（原本能上网，网络状态发生变化 = 认证过期/掉线）
$subNcsi = '<QueryList><Query Id="0" Path="Microsoft-Windows-NCSI/Operational"><Select Path="Microsoft-Windows-NCSI/Operational">*[System[Provider[@Name=''Microsoft-Windows-NCSI''] and (EventID=4042)]] and *[EventData[Data[@Name=''PreviousCapability'']=''2'']]</Select></Query></QueryList>'

$triggers = @(
    (New-ScheduledTaskTrigger -AtLogOn -User $user),
    (New-EventTrigger -Subscription $subNet),
    (New-EventTrigger -Subscription $subWlan),
    (New-EventTrigger -Subscription $subNcsi)
)

$action    = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}"' -f $vbs)
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings `
        -Description '校园网自动登录（登录 / 插网线 / 连WiFi / 掉网 时自动认证）' -Force | Out-Null
    Write-Host '计划任务注册成功。' -ForegroundColor Green
} catch {
    Write-Host ('计划任务注册失败：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

# ---------- 立即测试一次 ----------
if (-not $NoTest) {
    Write-Host '正在测试运行一次 ...' -ForegroundColor Cyan
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 10
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Host ("运行结果码: {0}   (0 = 成功)" -f $info.LastTaskResult)
    $log = Join-Path $dir 'logs\campus-login.log'
    if (Test-Path -LiteralPath $log) {
        Write-Host '最近日志：' -ForegroundColor Cyan
        Get-Content -LiteralPath $log -Encoding UTF8 -Tail 5 | ForEach-Object { Write-Host ('  ' + $_) }
    }
}

Write-Host ''
Write-Host '安装完成！触发时机：登录 Windows / 插上网线 / 连上 WiFi / 掉网时。' -ForegroundColor Green
Write-Host '手动测试：双击 run-login.cmd        卸载：双击 uninstall.cmd' -ForegroundColor Green
