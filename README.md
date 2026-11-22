# XDRBoost

一个精简的 macOS 菜单栏工具，用于在支持 EDR 的内置 XDR 屏幕上启用额外亮度。

当前版本：**1.1.1**。使用原生 Swift、AppKit、Metal 和 Core Graphics，无第三方运行时依赖。

## 功能

- 菜单栏太阳图标：增强开关、目标值滑杆、系统 EDR 上限、退出。
- 使用屏幕角落的极小 EDR 触发点和 Gamma 表调整，不使用全屏白色乘法浮层。
- 可调目标上限随系统当前 EDR 余量更新；临时受限时保留用户原先选择的目标值。
- 睡眠、会话切换和高温时暂停；合并重复唤醒通知，避免不必要的重建。
- 检测外部 Gamma 修改后停止增强，并保留新设置。
- 独立恢复子进程在主程序异常退出后恢复本程序仍拥有的 Gamma 设置。
- 检查恢复进程和 GPU 渲染状态；渲染停滞时尝试重建一次，再失败则关闭增强。

## 系统要求

- Apple Silicon Mac，macOS 13 或更新版本。
- 支持 EDR 的内置屏幕，并使用允许 XDR 的显示预设。
- 构建需要 Apple Command Line Tools，无需完整 Xcode。

目前在 **16 英寸 MacBook Pro（2021，M1 Pro、Liquid Retina XDR）和 macOS 27.2.1** 上验证过。其他机型和系统版本尚未验证。外接屏幕不在当前支持范围内。

## 构建和运行

```sh
git clone https://github.com/7uvss/XDRBoost.git
cd XDRBoost
xcode-select --install # 已安装 Command Line Tools 时可跳过
./build.sh
open XDRBoost.app
```

构建脚本输出 `XDRBoost.app` 并做本机临时签名。应用没有经过 Apple 公证；仓库不包含预编译应用。

点击菜单栏太阳图标，选择“开启额外亮度”。等系统建立 EDR 余量后，用滑杆调整目标值。建议从 1.25× 开始。关闭增强或退出程序即可撤销。每次启动默认关闭增强。

## 亮度刻度与限制

滑杆是**目标增强刻度**，不是实测尼特或物理亮度倍率。系统报告的 EDR 上限、Gamma 系数和实际屏幕亮度是不同的量。例如，参考 EDR 为 3.2× 时，满档使用约 1.59 的 Gamma 系数。

实际效果受系统亮度、显示预设、温度和色彩管理影响。高亮度会增加耗电，Gamma 调整会影响色彩；进行色彩校准或其他需要准确颜色的工作时应关闭增强。角落触发点极小，但在部分截图或显示配置中仍可能可见。

Gamma 扩展范围的行为依赖 macOS 与显示器实现，系统升级后需要重新验证。程序无需录屏、辅助功能或管理员权限，没有网络访问代码。

## 验证

只读取型号及 EDR 能力：

```sh
./XDRBoost.app/Contents/MacOS/XDRBoost --probe
```

退出正常运行的 XDRBoost 后，执行硬件回归测试：

```sh
./XDRBoost.app/Contents/MacOS/XDRBoost --self-test
```

测试约 12 秒，会短暂修改屏幕亮度，并在结束时撤销模拟的 Gamma 修改。覆盖连续亮度曲线、滑杆与 Gamma 读回、重复通知、渲染恢复、色彩冲突及恢复进程故障等 15 项检查。结果为 `REGRESSION_SUITE PASS checks=15` 时退出码为 0。

GitHub Actions 只验证编译、应用配置和本地签名；不会在云端运行需要真实 XDR 屏幕的亮度测试。自动检查不能代替真实触控板手势、快速应用切换、睡眠唤醒和色彩效果的目视验证。

## 项目结构

```text
Source/main.swift         菜单栏界面与生命周期管理
Source/GammaBoost.swift   Gamma、EDR 触发点和恢复子进程
Source/Diagnostics.swift  本机硬件回归测试
Info.plist               应用配置
build.sh                 Apple Silicon 构建脚本
```

开发流程与问题反馈见 [CONTRIBUTING.md](CONTRIBUTING.md)。版本记录见 [CHANGELOG.md](CHANGELOG.md)。

## 许可与致谢

采用 [GNU GPL v3](LICENSE)。EDR 和 Gamma 技术参考并改编自 [BrightXDR](https://github.com/starkdmi/BrightXDR) 与 [BrightIntosh](https://github.com/niklasr22/BrightIntosh)。完整声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
