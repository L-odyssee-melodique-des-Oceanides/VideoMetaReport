# 视频批量分析脚本 v5.2 - 修改超链接为复制文本功能
# 需要先安装FFmpeg并确保ffprobe在系统路径中
 
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Path = ".",
 
    [string]$OutputFile,
 
    [switch]$NoCopyButtons = $false,
 
    [switch]$Help
)
 
# 显示帮助信息
function Show-Help {
    Write-Host @"
🎬 视频批量分析脚本 v5.2
 
📖 用法:
  .\video-analyzer.ps1 [-Path <路径>] [-OutputFile <文件名前缀>] [-NoCopyButtons] [-Help]
 
📋 参数说明:
  -Path <路径>         要分析的目录路径 (默认: 当前目录)
  -OutputFile <前缀>   输出HTML文件的前缀 (可选)
  -NoCopyButtons       禁用复制按钮功能
  -Help                显示此帮助信息
 
📊 输出说明:
  - 脚本会自动生成HTML格式的分析报告
  - HTML文件名格式: [最内层文件夹名-时间戳].html
  - 如果指定了OutputFile参数，则使用指定名称
  - 点击目录/文件名可复制完整路径到剪贴板
 
🎯 颜色编码:
  🟥 红色: 需要优先处理的问题
  🟨 黄色: 标准质量，建议优化
  🟩 绿色: 高质量，符合标准
  🟦 蓝色: HDR格式视频
  ⚪ 白色: SDR格式视频
 
📝 示例:
  .\video-analyzer.ps1
  .\video-analyzer.ps1 -Path "D:\Movies"
  .\video-analyzer.ps1 -OutputFile "MyVideoAnalysis"
  .\video-analyzer.ps1 -NoCopyButtons
 
🔧 系统要求:
  - Windows PowerShell 5.1 或更高版本
  - 已安装FFmpeg并添加到系统PATH
 
📄 输出文件:
  脚本会生成一个HTML格式的报告，包含:
  - 视频文件详细分析表格
  - 统计图表和分布情况
  - 点击复制完整路径功能
  - 颜色编码的问题分类
 
"@
    exit 0
}
 
# 如果请求帮助，显示帮助信息
if ($Help) {
    Show-Help
}
 
# 检查是否安装了ffprobe
if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-Host "错误: 请先安装FFmpeg并确保ffprobe在系统路径中" -ForegroundColor Red
    Write-Host "可以从 https://ffmpeg.org/download.html 下载" -ForegroundColor Yellow
    Write-Host "使用 -Help 参数查看使用说明" -ForegroundColor Cyan
    exit 1
}
 
# 支持的视频文件扩展名
$videoExtensions = @('.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.mpg', '.mpeg', '.ts', '.mts', '.m2ts', '.hevc', '.h264', '.264', '.265', '.hevc', '.rmvb', '.rm', '.3gp', '.f4v', '.m2v', '.m4v', '.mp2', '.mpe', '.mpv', '.ogv', '.qt', '.vob')
 
function Get-AbsolutePath {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Path,
        
        [Parameter(Position=1)]
        [string]$BasePath = (Get-Location).Path
    )
    
    # 如果输入的路径已经是绝对路径，直接返回
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    
    # 将相对路径转换为绝对路径
    return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($BasePath, $Path))
}
 
# 函数：获取最内层文件夹名
function Get-InnermostFolderName {
    param([string]$Path)
    
    # 规范化路径
    $fullPath = $Path
 
    # 如果路径是文件，获取其目录
    if (Test-Path -Path $fullPath -PathType Leaf) {
        $fullPath = [System.IO.Path]::GetDirectoryName($fullPath)
    }
    
    # 如果路径不存在，返回默认值
    if (-not (Test-Path -Path $fullPath)) {
        return "Unknown"
    }
 
    # 获取路径的最后一部分
    $folderName = [System.IO.Path]::GetFileName($fullPath)
    
    # 如果是根目录或为空，使用父目录名或驱动器名
    if ([string]::IsNullOrEmpty($folderName)) {
        # 如果是根目录，如 C:\
        $drive = [System.IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
        if (-not [string]::IsNullOrEmpty($drive)) {
            $folderName = $drive.Replace(':', '')
        } else {
            $folderName = "Root"
        }
    }
    
    # 如果是当前目录的特殊表示
    if ($folderName -eq "." -or $folderName -eq "..") {
        $currentDir = [System.IO.Path]::GetFileName((Get-Location).Path)
        if (-not [string]::IsNullOrEmpty($currentDir)) {
            $folderName = $currentDir
        } else {
            $folderName = "Current"
        }
    }
    
    # 清理文件夹名中的非法字符
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($char in $invalidChars) {
        $folderName = $folderName.Replace($char, '-')
    }
    
    return $folderName
}
 
# 获取脚本开始时间
$startTime = Get-Date
$timestamp = $startTime.ToString("yyyyMMdd-HHmmss")
 
$Path = Get-AbsolutePath -Path $Path -BasePath $PWD.Path
 
# 生成输出文件名
if ([string]::IsNullOrEmpty($OutputFile)) {
    $folderName = Get-InnermostFolderName -Path $Path
    $OutputFile = "${folderName}-${timestamp}"
} else {
    # 确保输出文件名没有扩展名
    $OutputFile = [System.IO.Path]::GetFileNameWithoutExtension($OutputFile)
}
 
# 确保输出文件路径完整
$htmlFile = "${OutputFile}.html"
 
# 初始化计数器
$totalFiles = 0
$lowResolutionCount = 0
$goodResolutionCount = 0
$excellentResolutionCount = 0
$lowFramerateCount = 0
$normalFramerateCount = 0
$highFramerateCount = 0
$hdrCount = 0
$otherColorSpaceCount = 0
 
# 创建结果数组
$results = @()
 
Write-Host "🎬 视频筛查脚本 v5.2" -ForegroundColor Cyan
Write-Host ("=" * 60)
 
# 获取所有视频文件
Write-Host "正在扫描视频文件..." -ForegroundColor Yellow
try {
    $videoFiles = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | 
        Where-Object { $videoExtensions -contains $_.Extension.ToLower() }
    
    $totalFiles = $videoFiles.Count
    
    if ($totalFiles -eq 0) {
        Write-Host "未找到视频文件，请检查文件是否存在，或脚本工作目录、目录参数是否正确" -ForegroundColor Red
        Write-Host "支持的格式: $($videoExtensions -join ', ')" -ForegroundColor Gray
        exit 1
    }
    
    Write-Host "找到 $totalFiles 个视频文件" -ForegroundColor Green
} catch {
    Write-Host "错误: 无法访问路径 '$Path'" -ForegroundColor Red
    Write-Host "请检查路径是否正确，或您是否有访问权限" -ForegroundColor Yellow
    exit 1
}
 
Write-Host "开始分析视频..." -ForegroundColor Yellow
 
# 处理每个视频文件
$processedCount = 0
foreach ($file in $videoFiles) {
    $processedCount++
    $percentComplete = [math]::Round(($processedCount / $totalFiles) * 100, 1)
    
    # 每处理10个文件或进度有整数变化时更新状态
    if ($processedCount % 10 -eq 0 -or [math]::Round($percentComplete) -ne [math]::Round(($processedCount - 1) / $totalFiles * 100)) {
        Write-Progress -Activity "分析视频文件" -Status "进度: $processedCount/$totalFiles ($percentComplete%)" `
            -PercentComplete $percentComplete -CurrentOperation "正在处理: $($file.Name)"
    }
    
    try {
        # 使用ffprobe获取视频信息
        $ffprobeOutput = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,color_transfer,color_primaries,color_space,pix_fmt -of json $file.FullName 2>$null
        
        # 解析JSON输出
        $videoInfo = $ffprobeOutput | ConvertFrom-Json
        
        if ($videoInfo.streams) {
            $stream = $videoInfo.streams[0]
            
            # 获取宽度和高度
            $width = [int]$stream.width
            $height = [int]$stream.height
            
            # 处理竖屏视频：取较大的值作为宽
            $effectiveWidth = [Math]::Max($width, $height)
            $effectiveHeight = [Math]::Min($width, $height)
            
            # 判断分辨率
            $resolution = "${width}x${height}"
            $resolutionStatus = ""
            $resolutionColor = "white"
            $resolutionCategory = ""
            
            if ($effectiveWidth -lt 1920 -or $effectiveHeight -lt 1080) {
                $resolutionStatus = "低画质(<1080p)"
                $resolutionColor = "red"
                $resolutionCategory = "Low"
                $lowResolutionCount++
            }
            elseif ($effectiveWidth -ge 3840 -and $effectiveHeight -ge 2160) {
                $resolutionStatus = "4K ✓"
                $resolutionColor = "green"
                $resolutionCategory = "4K"
                $excellentResolutionCount++
            }
            else {
                $resolutionStatus = "1080p"
                $resolutionColor = "yellow"
                $resolutionCategory = "1080p"
                $goodResolutionCount++
            }
            
            # 判断帧率
            $framerateText = $stream.r_frame_rate
            $framerate = 0
            if ($framerateText -match "(\d+)/(\d+)") {
                $num = [double]$Matches[1]
                $den = [double]$Matches[2]
                if ($den -ne 0) {
                    $framerate = $num / $den
                }
            }
            elseif ([double]::TryParse($framerateText, [ref]$framerate)) {
                # 已经是数字
            }
            
            $framerateStatus = ""
            $framerateColor = "white"
            $framerateDisplay = ""
            $framerateCategory = ""
            
            if ($framerate -eq 0) {
                $framerateDisplay = "未知"
                $framerateStatus = "未知"
                $framerateColor = "gray"
                $framerateCategory = "Unknown"
            }
            elseif ($framerate -lt 28) {
                $framerateDisplay = [math]::Round($framerate, 1).ToString("0.0") + " fps"
                $framerateStatus = "低帧率"
                $framerateColor = "red"
                $framerateCategory = "Low"
                $lowFramerateCount++
            }
            elseif ($framerate -ge 55 -and $framerate -le 65) {
                $framerateDisplay = "60 fps"
                $framerateStatus = "高帧率 ✓"
                $framerateColor = "green"
                $framerateCategory = "High"
                $highFramerateCount++
            }
            elseif (($framerate -ge 29 -and $framerate -le 31) -or 
                    ($framerate -ge 29.9 -and $framerate -le 30.1)) {
                $framerateDisplay = "30 fps"
                $framerateStatus = "标准帧率"
                $framerateColor = "yellow"
                $framerateCategory = "Normal"
                $normalFramerateCount++
            }
            else {
                $framerateDisplay = [math]::Round($framerate, 1).ToString("0.0") + " fps"
                $framerateStatus = $framerateDisplay
                $framerateColor = "white"
                $framerateCategory = "Other"
            }
            
            # 判断色彩空间 - 改为追加性写入
            $colorInfoArray = @()  # 用于存储颜色信息的数组
            $colorDisplayArray = @()  # 用于存储显示信息的数组
            $colorSpaceColor = "white"
            $colorCategory = "SDR"
            $isHDR = $false
            $isOtherColorSpace = $false
            
            # 检查传输特性
            if ($stream.color_transfer) {
                switch ($stream.color_transfer) {
                    "smpte2084" { 
                        $colorInfoArray += "PQ (SMPTE 2084)"
                        $colorDisplayArray += "HDR10"
                        $isHDR = $true
                        $colorSpaceColor = "blue"
                        $colorCategory = "HDR"
                    }
                    "arib-std-b67" { 
                        $colorInfoArray += "HLG (ARIB STD-B67)"
                        $colorDisplayArray += "HDR HLG"
                        $isHDR = $true
                        $colorSpaceColor = "blue"
                        $colorCategory = "HDR"
                    }
                    "bt2020-10" { 
                        $colorInfoArray += "BT.2020-10bit"
                        $colorDisplayArray += "HDR10"
                        $isHDR = $true
                        $colorSpaceColor = "blue"
                        $colorCategory = "HDR"
                    }
                    "bt2020" { 
                        $colorInfoArray += "BT.2020"
                        $colorDisplayArray += "宽色域"
                        $isOtherColorSpace = $true
                        $colorSpaceColor = "red"
                        $colorCategory = "WideGamut"
                    }
                    "bt709" { 
                        $colorInfoArray += "Rec.709"
                        $colorCategory = "SDR"
                    }
                    "smpte170m" { 
                        $colorInfoArray += "BT.601"
                        $colorCategory = "SDR"
                    }
                    "gamma22" { 
                        $colorInfoArray += "Gamma 2.2"
                        $colorCategory = "SDR"
                    }
                    "gamma28" { 
                        $colorInfoArray += "Gamma 2.8"
                        $colorCategory = "SDR"
                    }
                    default { 
                        $colorInfoArray += "$($stream.color_transfer)"
                        $colorDisplayArray += "非SDR"
                        $isOtherColorSpace = $true
                        $colorSpaceColor = "red"
                        $colorCategory = "Other"
                    }
                }
            }
            
            # 检查色彩原色（色域）
            if ($stream.color_primaries -and -not $isHDR) {
                switch ($stream.color_primaries) {
                    "bt2020" { 
                        if ($colorCategory -eq "SDR") {
                            $colorInfoArray += "BT.2020色域"
                            $colorDisplayArray += "宽色域"
                            $isOtherColorSpace = $true
                            $colorSpaceColor = "red"
                            $colorCategory = "WideGamut"
                        }
                    }
                    "p3" { 
                        $colorInfoArray += "DCI-P3色域"
                        $colorDisplayArray += "广色域"
                        $isOtherColorSpace = $true
                        $colorSpaceColor = "red"
                        $colorCategory = "WideGamut"
                    }
                    default { 
                        if ($stream.color_primaries -notin @("bt709", "smpte170m") -and $colorCategory -eq "SDR") {
                            $colorInfoArray += "$($stream.color_primaries)色域"
                            $colorDisplayArray += "非标准色域"
                            $isOtherColorSpace = $true
                            $colorSpaceColor = "red"
                            $colorCategory = "Other"
                        }
                    }
                }
            }
            
            # 检查色彩空间参数
            if ($stream.color_space) {
                switch ($stream.color_space) {
                    "bt2020nc" { 
                        $colorInfoArray += "BT.2020非恒定亮度"
                        $colorDisplayArray += "BT.2020 NC"
                    }
                    "bt2020c" { 
                        $colorInfoArray += "BT.2020恒定亮度"
                        $colorDisplayArray += "BT.2020 CL"
                    }
                    "bt709" { 
                        $colorInfoArray += "BT.709色彩空间"
                        $colorDisplayArray += "Rec.709"
                    }
                    default { 
                        $colorInfoArray += "$($stream.color_space)色彩空间"
                        $colorDisplayArray += "$($stream.color_space)"
                    }
                }
            }
            
            # 检查像素格式
            if ($stream.pix_fmt -and -not $isHDR -and $colorCategory -eq "SDR") {
                if ($stream.pix_fmt -match "p10|p12") {
                    $colorInfoArray += "10/12-bit色深: $($stream.pix_fmt)"
                    $colorDisplayArray += "高色深"
                    $isOtherColorSpace = $true
                    $colorSpaceColor = "red"
                    $colorCategory = "HighBitDepth"
                }
                elseif ($stream.pix_fmt -match "yuva") {
                    $colorInfoArray += "带Alpha通道: $($stream.pix_fmt)"
                    $colorDisplayArray += "带透明通道"
                    $isOtherColorSpace = $true
                    $colorSpaceColor = "red"
                    $colorCategory = "Advanced"
                }
                elseif ($stream.pix_fmt -match "yuv444") {
                    $colorInfoArray += "4:4:4色度抽样: $($stream.pix_fmt)"
                    $colorDisplayArray += "4:4:4格式"
                    $isOtherColorSpace = $true
                    $colorSpaceColor = "red"
                    $colorCategory = "Advanced"
                }
                elseif ($stream.pix_fmt -match "rgb|bgr") {
                    $colorInfoArray += "RGB格式: $($stream.pix_fmt)"
                    $colorDisplayArray += "RGB格式"
                    $isOtherColorSpace = $true
                    $colorSpaceColor = "red"
                    $colorCategory = "Advanced"
                }
                else {
                    $colorInfoArray += "像素格式: $($stream.pix_fmt)"
                    $colorDisplayArray += "$($stream.pix_fmt)"
                }
            }
            
            # 如果没有检测到任何颜色信息，添加默认值
            if ($colorInfoArray.Count -eq 0) {
                $colorInfoArray += "SDR"
                $colorDisplayArray += "SDR"
            }
            
            # 将数组转换为字符串，用逗号分隔
            $colorInfo = $colorInfoArray -join ", "
            $colorDisplay = $colorDisplayArray -join ", "
            
            # 更新计数器
            if ($isHDR) {
                $colorSpaceColor = "blue"
                $hdrCount++
            }
            if ($isOtherColorSpace) {
                $otherColorSpaceCount++
            }
            
            # 显示需要警告的文件
            # 创建结果对象
            $result = [PSCustomObject]@{
                Directory = $file.DirectoryName
                FileName = $file.Name
                FullPath = $file.FullName
                Resolution = $resolution
                ResolutionStatus = $resolutionStatus
                ResolutionColor = $resolutionColor
                ResolutionCategory = $resolutionCategory
                Framerate = $framerateDisplay
                FramerateStatus = $framerateStatus
                FramerateColor = $framerateColor
                FramerateCategory = $framerateCategory
                ColorSpace = $colorDisplay
                ColorInfo = $colorInfo
                ColorSpaceColor = $colorSpaceColor
                ColorCategory = $colorCategory
            }
                
                $results += $result
        }
    }
    catch {
        # 静默处理错误，继续处理下一个文件
    }
}
 
Write-Progress -Activity "分析视频文件" -Completed
 
# 计算分析时间
$endTime = Get-Date
$duration = $endTime - $startTime
 
$sdrCount = $totalFiles - $hdrCount - $otherColorSpaceCount
 
# 显示简要统计信息
Write-Host "`n分析完成!" -ForegroundColor Green
Write-Host ("=" * 60)
Write-Host "📊 统计概览:" -ForegroundColor Cyan
Write-Host "  [分辨率]"
Write-Host ("  <1080p:  {0,5} ({1:P1})" -f $lowResolutionCount, ($lowResolutionCount / $totalFiles)) -ForegroundColor Red
Write-Host ("  1080p:   {0,5} ({1:P1})" -f $goodResolutionCount, ($goodResolutionCount / $totalFiles)) -ForegroundColor Yellow
Write-Host ("  4K:      {0,5} ({1:P1})" -f $excellentResolutionCount, ($excellentResolutionCount / $totalFiles)) -ForegroundColor Green
Write-Host "  [帧率]"
Write-Host ("  <28fps:   {0,5} ({1:P1})" -f $lowFramerateCount, ($lowFramerateCount / $totalFiles)) -ForegroundColor Red
Write-Host ("  30fps:    {0,5} ({1:P1})" -f $normalFramerateCount, ($normalFramerateCount / $totalFiles)) -ForegroundColor Yellow
Write-Host ("  60fps:    {0,5} ({1:P1})" -f $highFramerateCount, ($highFramerateCount / $totalFiles)) -ForegroundColor Green
Write-Host "  [色彩空间]"
Write-Host ("  SDR:      {0,5} ({1:P1})" -f $sdrCount, ($sdrCount / $totalFiles)) -ForegroundColor Green
Write-Host ("  HDR:      {0,5} ({1:P1})" -f $hdrCount, ($hdrCount / $totalFiles)) -ForegroundColor Blue
Write-Host ("  其他:     {0,5} ({1:P1})" -f $otherColorSpaceCount, ($otherColorSpaceCount / $totalFiles)) -ForegroundColor Red
Write-Host ("`n  分析用时: {0:mm}分{0:ss}秒" -f $duration) -ForegroundColor Cyan
 
# 如果没有找到需要警告的文件
if ($results.Count -eq 0) {
    Write-Host "`n✅ 恭喜! 没有发现需要警告的视频文件。" -ForegroundColor Green
    exit 0
}
 
# 生成HTML报告
Write-Host "`n正在生成HTML报告..." -ForegroundColor Yellow
 
# 计算百分比
$lowResolutionPercent = if ($totalFiles -gt 0) { [math]::Round($lowResolutionCount / $totalFiles * 100, 1) } else { 0 }
$goodResolutionPercent = if ($totalFiles -gt 0) { [math]::Round($goodResolutionCount / $totalFiles * 100, 1) } else { 0 }
$excellentResolutionPercent = if ($totalFiles -gt 0) { [math]::Round($excellentResolutionCount / $totalFiles * 100, 1) } else { 0 }
$lowFrameratePercent = if ($totalFiles -gt 0) { [math]::Round($lowFramerateCount / $totalFiles * 100, 1) } else { 0 }
$normalFrameratePercent = if ($totalFiles -gt 0) { [math]::Round($normalFramerateCount / $totalFiles * 100, 1) } else { 0 }
$highFrameratePercent = if ($totalFiles -gt 0) { [math]::Round($highFramerateCount / $totalFiles * 100, 1) } else { 0 }
$hdrPercent = if ($totalFiles -gt 0) { [math]::Round($hdrCount / $totalFiles * 100, 1) } else { 0 }
$otherColorSpacePercent = if ($totalFiles -gt 0) { [math]::Round($otherColorSpaceCount / $totalFiles * 100, 1) } else { 0 }
$sdrPercent = if ($totalFiles -gt 0) { [math]::Round($sdrCount / $totalFiles * 100, 1) } else { 0 }
 
# 创建HTML文档
$html = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>视频分析报告 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</title>
    <style>
        body {
            font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
            margin: 20px;
            background-color: #1e1e1e;
            color: #d4d4d4;
        }
        h1 {
            color: #4ec9b0;
            border-bottom: 2px solid #4ec9b0;
            padding-bottom: 10px;
        }
        h2 {
            color: #ce9178;
            margin-top: 30px;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 20px 0;
            font-size: 14px;
        }
        th {
            background-color: #2d2d30;
            color: #9cdcfe;
            padding: 10px;
            text-align: left;
            border: 1px solid #3e3e42;
            font-weight: bold;
        }
        td {
            padding: 8px 10px;
            border: 1px solid #3e3e42;
            vertical-align: top;
        }
        tr:nth-child(even) {
            background-color: #252526;
        }
        tr:hover {
            background-color: #2a2d2e;
        }
        .red {
            color: #f48771;
            font-weight: bold;
        }
        .yellow {
            color: #ffd700;
        }
        .green {
            color: #6a9955;
            font-weight: bold;
        }
        .blue {
            color: #569cd6;
            font-weight: bold;
        }
        .cyan {
            color: #4ec9b0;
        }
        .gray {
            color: #858585;
        }
        .white {
            color: #d4d4d4;
        }
        .stats {
            display: flex;
            flex-wrap: wrap;
            gap: 20px;
            margin: 20px 0;
        }
        .stat-box {
            background-color: #252526;
            border: 1px solid #3e3e42;
            border-radius: 5px;
            padding: 15px;
            min-width: 200px;
            flex: 1;
        }
        .stat-title {
            font-size: 16px;
            margin-bottom: 10px;
            color: #ce9178;
        }
        .stat-value {
            font-size: 24px;
            font-weight: bold;
            margin: 5px 0;
        }
        .summary {
            background-color: #252526;
            border: 1px solid #3e3e42;
            border-radius: 5px;
            padding: 20px;
            margin: 20px 0;
        }
        .timestamp {
            color: #858585;
            font-style: italic;
            margin-top: 30px;
            text-align: center;
        }
        .copy-btn {
            color: #4ec9b0;
            cursor: pointer;
            text-decoration: underline;
            border: none;
            background: none;
            padding: 0;
            font: inherit;
            outline: inherit;
        }
        .copy-btn:hover {
            color: #6a9955;
        }
        .copy-btn:active {
            color: #ce9178;
        }
        .dir-cell {
            max-width: 300px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .file-cell {
            max-width: 250px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .filter-buttons {
            margin: 20px 0;
        }
        .filter-btn {
            padding: 8px 15px;
            margin-right: 10px;
            background-color: #2d2d30;
            border: 1px solid #3e3e42;
            color: #d4d4d4;
            cursor: pointer;
            border-radius: 3px;
        }
        .filter-btn:hover {
            background-color: #3e3e42;
        }
        .filter-btn.active {
            background-color: #007acc;
            color: white;
        }
        .toast {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background-color: #333;
            color: white;
            padding: 12px 20px;
            border-radius: 4px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.3);
            z-index: 1000;
            opacity: 0;
            transition: opacity 0.3s;
        }
        .toast.show {
            opacity: 1;
        }
    </style>
</head>
<body>
    <h1>🎬 视频分析报告</h1>
    <div class="summary">
        <p><strong>分析时间:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>分析路径:</strong> $Path</p>
        <p><strong>总文件数:</strong> $totalFiles</p>
        <p><strong>分析用时:</strong> $($duration.ToString('mm\分ss\秒'))</p>
        <p><em>点击目录或文件名可复制完整路径到剪贴板</em></p>
    </div>
    
    <h2>📊 统计概览</h2>
    <div class="stats">
        <div class="stat-box">
            <div class="stat-title">分辨率分布</div>
            <div class="stat-value red">$lowResolutionCount <span class="white">($lowResolutionPercent%)</span></div>
            <div class="stat-title">低画质(<1080p)</div>
            <div class="stat-value yellow">$goodResolutionCount <span class="white">($goodResolutionPercent%)</span></div>
            <div class="stat-title">1080p</div>
            <div class="stat-value green">$excellentResolutionCount <span class="white">($excellentResolutionPercent%)</span></div>
            <div class="stat-title">4K</div>
        </div>
        
        <div class="stat-box">
            <div class="stat-title">帧率分布</div>
            <div class="stat-value red">$lowFramerateCount <span class="white">($lowFrameratePercent%)</span></div>
            <div class="stat-title">低帧率(<28fps)</div>
            <div class="stat-value yellow">$normalFramerateCount <span class="white">($normalFrameratePercent%)</span></div>
            <div class="stat-title">30fps</div>
            <div class="stat-value green">$highFramerateCount <span class="white">($highFrameratePercent%)</span></div>
            <div class="stat-title">60fps</div>
        </div>
        
        <div class="stat-box">
            <div class="stat-title">色彩空间分布</div>
            <div class="stat-value blue">$hdrCount <span class="white">($hdrPercent%)</span></div>
            <div class="stat-title">HDR视频</div>
            <div class="stat-value red">$otherColorSpaceCount <span class="white">($otherColorSpacePercent%)</span></div>
            <div class="stat-title">其他非SDR</div>
            <div class="stat-value white">$sdrCount <span class="white">($sdrPercent%)</span></div>
            <div class="stat-title">SDR视频</div>
        </div>
    </div>
    
    <h2>📋 详细分析结果</h2>
    <div class="filter-buttons">
        <button class="filter-btn active" onclick="filterTable('all')">全部</button>
        <button class="filter-btn" onclick="filterTable('red')">需要处理</button>
        <button class="filter-btn" onclick="filterTable('yellow')">建议优化</button>
        <button class="filter-btn" onclick="filterTable('green')">高质量</button>
        <button class="filter-btn" onclick="filterTable('blue')">HDR格式</button>
    </div>
    
    <div class="table-container">
        <table id="videoTable">
            <thead>
                <tr>
                    <th width="30%">目录路径</th>
                    <th width="25%">文件名</th>
                    <th width="15%">分辨率状态</th>
                    <th width="15%">帧率状态</th>
                    <th width="15%">色彩空间</th>
                </tr>
            </thead>
            <tbody>
"@
 
# 如果没有结果，显示相应消息
if ($results.Count -eq 0) {
    $html += @"
                <tr>
                    <td colspan="5" style="text-align: center; padding: 50px; color: #888;">
                        <h3>🎉 恭喜！</h3>
                        <p>没有发现需要警告的视频文件。</p>
                        <p style="margin-top: 20px; opacity: 0.7;">所有视频都符合高标准要求。</p>
                    </td>
                </tr>
"@
} else {
    # 添加数据行
    foreach ($result in $results) {
        # 确定行类别
        $rowClass = ""
        if ($result.ResolutionColor -eq "red" -or $result.FramerateColor -eq "red" -or $result.ColorSpaceColor -eq "red") {
            $rowClass = "red"
        } elseif ($result.ResolutionColor -eq "yellow" -or $result.FramerateColor -eq "yellow") {
            $rowClass = "yellow"
        } elseif ($result.ResolutionColor -eq "green" -or $result.FramerateColor -eq "green") {
            $rowClass = "green"
        }
        if ($result.ColorSpaceColor -eq "blue") {
            $rowClass = "blue"
        }
        
        # 转义特殊字符，防止JavaScript错误
        $escapedDir = $result.Directory.Replace("\","\\").Replace("'", "\\'").Replace('"', '\"')
        $escapedFile = $result.FileName.Replace("\","\\").Replace("'", "\\'").Replace('"', '\"')
        $escapedFullPath = $result.FullPath.Replace("\","\\").Replace("'", "\\'").Replace('"', '\"')
        
        $html += @"
                <tr class="data-row $rowClass">
                    <td class="dir-cell">
    $(if (-not $NoCopyButtons) { 
        "<button class='copy-btn' onclick=""copyToClipboard('$escapedDir')"" title='点击复制目录路径'>$($result.Directory)</button>" 
    } else { 
        $result.Directory 
    })
                    </td>
                    <td class="file-cell">
    $(if (-not $NoCopyButtons) { 
        "<button class='copy-btn' onclick=""copyToClipboard('$escapedFullPath')"" title='点击复制完整文件路径'>$($result.FileName)</button>" 
    } else { 
        $result.FileName 
    })
                    </td>
                    <td class="$($result.ResolutionColor)">$($result.ResolutionStatus)</td>
                    <td class="$($result.FramerateColor)">$($result.FramerateStatus)</td>
                    <td class="$($result.ColorSpaceColor)">$($result.ColorSpace)</td>
                </tr>
"@
    }
}
 
$html += @"
            </tbody>
        </table>
    </div>
    
    <div class="timestamp">
        报告生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | 脚本版本: 5.2
    </div>
 
    <div id="toast" class="toast"></div>
 
    <script>
        // 过滤表格函数
        function filterTable(filter) {
            // 更新按钮状态
            var buttons = document.querySelectorAll('.filter-btn');
            buttons.forEach(function(btn) {
                btn.classList.remove('active');
            });
            event.target.classList.add('active');
            
            // 显示/隐藏行
            var rows = document.querySelectorAll('.data-row');
            rows.forEach(function(row) {
                if (filter === 'all') {
                    row.style.display = '';
                } else if (filter === 'red') {
                    row.style.display = row.classList.contains('red') ? '' : 'none';
                } else if (filter === 'yellow') {
                    row.style.display = row.classList.contains('yellow') ? '' : 'none';
                } else if (filter === 'green') {
                    row.style.display = row.classList.contains('green') ? '' : 'none';
                } else if (filter === 'blue') {
                    row.style.display = row.classList.contains('blue') ? '' : 'none';
                }
            });
        }
        
        // 复制到剪贴板函数
        function copyToClipboard(text) {
            // 创建临时textarea元素
            var textArea = document.createElement("textarea");
            textArea.value = text;
            textArea.style.position = "fixed";
            textArea.style.left = "-999999px";
            textArea.style.top = "-999999px";
            document.body.appendChild(textArea);
            textArea.focus();
            textArea.select();
            
            try {
                var successful = document.execCommand('copy');
                showToast(successful ? '✅ 已复制到剪贴板: ' + (text.length > 50 ? text.substring(0, 50) + '...' : text) : '❌ 复制失败');
            } catch (err) {
                showToast('❌ 复制失败: ' + err);
            }
            
            document.body.removeChild(textArea);
        }
        
        // 显示提示信息
        function showToast(message) {
            var toast = document.getElementById('toast');
            toast.textContent = message;
            toast.classList.add('show');
            
            setTimeout(function() {
                toast.classList.remove('show');
            }, 3000);
        }
        
        // 添加排序功能
        document.querySelectorAll('th').forEach(function(th, index) {
            th.style.cursor = 'pointer';
            th.addEventListener('click', function() {
                sortTable(index);
            });
        });
        
        function sortTable(column) {
            var table = document.getElementById('videoTable');
            var tbody = table.querySelector('tbody');
            var rows = Array.from(tbody.querySelectorAll('tr'));
            
            var isAscending = table.dataset.sortColumn === column.toString() && table.dataset.sortOrder === 'asc';
            
            rows.sort(function(a, b) {
                var aText = a.cells[column].textContent.trim();
                var bText = b.cells[column].textContent.trim();
                
                // 特殊处理数字和状态
                if (column === 2 || column === 3) {
                    var aValue = parseFloat(aText) || 0;
                    var bValue = parseFloat(bText) || 0;
                    return isAscending ? aValue - bValue : bValue - aValue;
                }
                
                return isAscending ? aText.localeCompare(bText) : bText.localeCompare(aText);
            });
            
            // 更新排序状态
            table.dataset.sortColumn = column.toString();
            table.dataset.sortOrder = isAscending ? 'desc' : 'asc';
            
            // 重新添加行
            rows.forEach(function(row) {
                tbody.appendChild(row);
            });
        }
        
        // 页面加载完成后添加打印按钮
        document.addEventListener('DOMContentLoaded', function() {
            var header = document.querySelector('h1');
            var printBtn = document.createElement('button');
            printBtn.innerHTML = '🖨️ 打印报告';
            printBtn.style.cssText = 'margin-left: 20px; padding: 5px 10px; background: #007acc; color: white; border: none; border-radius: 3px; cursor: pointer;';
            printBtn.onclick = function() { window.print(); };
            header.appendChild(printBtn);
        });
    </script>
</body>
</html>
"@
 
# 保存HTML文件
try {
    $html | Out-File -FilePath $htmlFile -Encoding UTF8
    Write-Host "✅ HTML报告已生成: " -NoNewline -ForegroundColor Green
    Write-Host $htmlFile -ForegroundColor Cyan
    
    # 尝试在默认浏览器中打开报告
    try {
        Start-Process $htmlFile
        Write-Host "📄 报告已在浏览器中打开" -ForegroundColor Green
        Write-Host "📋 点击目录/文件名可复制完整路径到剪贴板" -ForegroundColor Cyan
    } catch {
        Write-Host "📄 请手动打开报告文件" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "❌ 生成报告时出错: $_" -ForegroundColor Red
    exit 1
}
 
Write-Host ("=" * 60)
Write-Host "脚本执行完成!" -ForegroundColor Green


ref(APA): Starluo.星洛札记.https://www.starluo.top. Retrieved 2025/12/20.