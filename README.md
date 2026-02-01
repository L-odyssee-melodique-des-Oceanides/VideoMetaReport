# Video Meta Report

视频批量分析工具 - 能够批量检测视频的编码、分辨率、帧率、色彩空间等信息，并生成 HTML 报告。

## 运行方式 (开发模式)

```bash
# 安装依赖
pip install -r requirements.txt

# 运行
python gui_app.py
```

## 打包指南

本通过 `PyInstaller` 进行打包，支持 macOS 和 Windows。
项目包含两个特定的打包配置文件：`build_macos.spec` 和 `build_windows.spec`。

### 1. macOS 打包 (生成 .app)

本项目的 macOS 打包需注意目标架构：Apple Silicon (arm64) 或 Intel (x86_64)。

#### 选项 A: 仅为当前架构打包 (推荐)
适用于为你自己的电脑打包。

```bash
# 执行 standard 打包
pyinstaller build_macos.spec
```
生成的 `Video Meta Report.app` 将只能在与你当前电脑相同架构的 Mac 上运行。

#### 选项 B: 在 Apple Silicon 上打包 Intel 版本 (x86_64)
如果你想在 Apple Silicon (M1/M2/M3) 电脑上打包出可以在 Intel Mac 上运行的应用：

1.  **准备 x86 环境**:你需要创建一个 x86_64 的 Python 环境 (通过 Rosetta)。
    ```bash
    # 使用 Conda 创建 x86 环境 (推荐)
    CONDA_SUBDIR=osx-64 conda create -n x86_env python=3.13
    conda activate x86_env
    
    # 重新安装依赖 (在 x86 环境下)
    pip install -r requirements.txt
    pip install pyinstaller
    ```
2.  **执行打包**:
    ```bash
    pyinstaller build_macos_x86.spec
    ```
3.  **结果**: 
    `dist/Video Meta Report (Intel).app` 即为兼容 Intel Mac 的应用。

### 2. Windows 打包 (生成 .exe)
 
在 Windows 系统下运行：
 
 1.  **准备环境**:
     确保已安装 Python 和 PyInstaller。
     
 2.  **准备依赖**:
     确保 `external/windows_x86/` 目录下存在以下文件：
     - `ffprobe.exe`
     - `exiftool.exe` (注意：如果是 `exiftool(-k).exe`，请重命名为 `exiftool.exe`)
 
 3.  **执行打包**:
 
 ```bash
 pyinstaller build_windows.spec
 ```
 
 4.  **结果**:
     打包完成后，可执行文件位于 `dist/Video Meta Report/Video Meta Report.exe`。
     
     > 注意：PyInstaller 6.x 版本会将依赖文件放在 `_internal` 文件夹中。请确保 `Video Meta Report.exe` 同级目录下存在 `_internal` 文件夹，否则程序将无法找到 `ffprobe` 和 `exiftool`。
