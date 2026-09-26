<#
 校园网自动登录 - 一键卸载（删除计划任务）
#>
[CmdletBinding()]
param()

$TaskName = 'SNNU-CampusAutoLogin'
$ErrorActionPreference = 'SilentlyContinue'

Write-Host '==============================================' -ForegroundColor Cyan
Write-Host '        校园网自动登录 - 卸载' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan

if (Get-ScheduledTask -TaskName $TaskName) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host ('已删除计划任务：{0}' -f $TaskName) -ForegroundColor Green
} else {
    Write-Host '未找到计划任务，无需卸载。' -ForegroundColor Yellow
}

Write-Host '（本文件夹可自行保留或删除）'
