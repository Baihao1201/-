# -
陕西师范大学校园网开机自动连接程序。以太网连接最快罪稳定，连接SNNU校园网也可以连接，最好打开"自动连接“

# 校园网自动登录（陕西师范大学 Portal）

自动完成校园网 Portal 认证：**开机、插网线、连 WiFi、掉网** 时自动连接，全程静默无弹窗。
支持有线以太网和 WiFi（不限定 SSID），适配笔记本，**换电脑/给同学用只需改一个配置文件**。

---

## 一、目录里有什么

| 文件 | 作用 |
|---|---|
| `config.psd1` | **配置文件**：账号、密码、运营商、认证地址、重试参数（只改这个） |
| `campus-login.ps1` | 主脚本：检测外网 → 需要时登录 → 校验 |
| `install.cmd` / `install.ps1` | **一键安装**：注册计划任务（右键 install.cmd 或双击） |
| `uninstall.cmd` / `uninstall.ps1` | 一键卸载：删除计划任务 |
| `run-hidden.vbs` | 以隐藏窗口启动脚本（所以不会弹 PowerShell 窗口） |
| `run-login.cmd` | 手动登录一次（排查用） |
| `logs\campus-login.log` | 运行日志（超过 512KB 自动截断） |

---

## 二、安装（3 步）

> 无需管理员权限，不需要装 Python 等任何东西。

1. **改配置**：用记事本打开 `config.psd1`，填自己的账号 / 密码 / 运营商，保存。
2. **安装**：双击 `install.cmd`（会弹出窗口显示结果，跑完按任意键关闭）。
3. **完成**。之后登录 Windows、插网线、连 WiFi、掉网时都会自动认证。

**给舍友 / 换到别的电脑**：把整个 `campus-auto-login` 文件夹拷过去 →
改 `config.psd1` → 双击 `install.cmd`，就装好了（不用管路径，脚本会自动识别所在目录）。

---

## 三、配置说明（config.psd1）

```powershell
account  = '42306999'                  # 学号 / 上网账号
password = '123456789'                 # 密码
carrier  = 'unicom'                    # 'unicom'=联通  'mobile'=移动  'telecom'=电信  ''=校园网

portalHost  = '202.117.144.205'        # 认证服务器（一般不用改）
portalPorts = @(8603, 8602, 8601)      # 端口优先级

internetTargets = @(                   # 判断"能不能上网"用的检测地址
    'http://www.msftconnecttest.com/connecttest.txt',
    'https://www.baidu.com',
    'https://www.taobao.com'
)

waitReadySec       = 60   # 连上网络后，等本机拿到 IP/路由的最长时间
portalTimeoutSec   = 6    # 门户请求超时
internetTimeoutSec = 4    # 外网检测超时
maxRounds          = 8    # 登录失败最多重试轮数
retryDelaySec      = 3    # 每轮间隔
```

> 改完 `config.psd1` 保存即可，**不用重新安装**（脚本每次运行都会重新读取）。

---

## 四、什么时候会自动触发（4 个时机，无周期轮询）

| 触发时机 | 说明 |
|---|---|
| **登录 Windows 时** | 开机进入桌面后自动认证 |
| **网络已连接时** | 插上网线 / 连上任意 WiFi |
| **连上 WiFi 时** | 不限定 SSID，SNNU、SNNU-5G 等都能触发 |
| **掉网时** | 网线/WiFi 还连着但外网断了（如认证过期），系统一检测到就触发 |

全部为事件驱动，**没有 3 分钟之类的定时轮询**，所以几乎不占资源、也不弹窗。

---

## 五、为什么在 WiFi / 笔记本上更稳、更快

1. **先等网络就绪再登录**：刚连上 WiFi 时 DHCP 可能还没拿到 IP，脚本会先等本机具备上网条件
   （最多 `waitReadySec` 秒），就绪后立刻认证 —— 解决"WiFi 登录成功率低"。
2. **不再依赖具体 SSID**：只要 WiFi 连上就触发，校园网换了 SSID 名称也不受影响。
3. **快速判定**：已能上网时 **1 秒内**判断完并退出，不做多余请求。
4. **登录结果用"能不能上网"来验证**，而不是只看网页返回值 —— 更可靠。
5. **点击即用**：即使当前走手机热点（本身能上网），脚本也只会判定"已联网"并跳过，不会乱登录。

---

## 六、手动测试

- **普通测试**：双击 `run-login.cmd`（静默运行，结果看日志）。
- **看日志**：`logs\campus-login.log`
- **强制断开重连**（排查用）：

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -File "campus-login.ps1" -ForceLogin
```

- **查看任务状态**：

```powershell
Get-ScheduledTask -TaskName 'SNNU-CampusAutoLogin' | Select State
Get-ScheduledTaskInfo -TaskName 'SNNU-CampusAutoLogin' | Select LastRunTime, LastTaskResult
```

---

## 七、卸载

双击 `uninstall.cmd`，或执行：

```powershell
Unregister-ScheduledTask -TaskName 'SNNU-CampusAutoLogin' -Confirm:$false
```

---

## 八、常见问题

**Q：连了 WiFi 但还是上不了网？**
先双击 `run-login.cmd` 手动跑一次，再看 `logs\campus-login.log`：
- 出现"外网正常，已在线" → 其实已经通了；
- 出现"网络未就绪" → WiFi 没真正拿到 IP，确认是否需要先在系统里点一下校园网；
- 出现"正在登录"但没"登录成功" → 检查 `config.psd1` 里账号/密码/运营商是否正确。

**Q：改了密码怎么办？**
只改 `config.psd1` 里的 `password`，保存即可。

**Q：换宿舍 / 换学校地址变了？**
改 `config.psd1` 里的 `portalHost` 和 `portalPorts`。

**Q：日志在哪里、要不要清？**
`logs\campus-login.log`，会自动截断，无需手动清理。
