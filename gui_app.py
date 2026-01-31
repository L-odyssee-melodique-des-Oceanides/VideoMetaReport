#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
视频批量分析工具 - Tkinter GUI 版本
"""
import os
import json
import subprocess
import threading
import webbrowser
from datetime import datetime
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import queue


# Supported video extensions
VIDEO_EXTENSIONS = ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.m4v', 
                    '.mpg', '.mpeg', '.ts', '.mts', '.m2ts', '.hevc', '.h264', '.264', 
                    '.265', '.rmvb', '.rm', '.3gp', '.f4v', '.m2v', '.mp2', '.mpe', 
                    '.mpv', '.ogv', '.qt', '.vob',
                    '.crm', '.mxf', '.nev', '.r3d']  # Added RAW formats

# RAW video extensions that should always show RAW warning
RAW_EXTENSIONS = ['.crm', '.nev', '.r3d']


import sys

# Define subprocess flags for Windows to suppress console window
if sys.platform == 'win32':
    SUBPROCESS_FLAGS = subprocess.CREATE_NO_WINDOW
else:
    SUBPROCESS_FLAGS = 0

# ... existing imports ...

def get_external_tool_path(tool_name):
    """
    Get the absolute path for an external tool (ffprobe/exiftool)
    based on the OS and whether we are running in a frozen bundle.
    """
    system = sys.platform
    
    # Determine the executable name
    if system == 'win32':
        filename = f"{tool_name}.exe"
    else:
        filename = tool_name

    # 1. Determine base path
    if getattr(sys, 'frozen', False):
        # FROZEN (PyInstaller)
        if system == 'darwin':
             # macOS .app bundle
             # sys.executable is inside /Contents/MacOS/
             # Resources are usually in /Contents/Resources/
             # However, simple one-file or one-dir builds might behave differently.
             # We check standard bundle structure first:
             bundle_dir = os.path.dirname(os.path.abspath(sys.executable))
             
             # Case A: Standard .app bundle (Contents/MacOS/ -> Contents/Resources/)
             # Path to Resources from executable
             resources_path = os.path.join(bundle_dir, '..', 'Resources')
             possible_path = os.path.join(resources_path, filename)
             if os.path.exists(possible_path):
                 return os.path.abspath(possible_path)
             
             # Case B: Sys._MEIPASS (One-file temporary directory)
             if hasattr(sys, '_MEIPASS'):
                 possible_path = os.path.join(sys._MEIPASS, filename)
                 if os.path.exists(possible_path):
                     return os.path.abspath(possible_path)
                     
        elif system == 'win32':
            # Windows Frozen
            # Tools should be next to the executable OR in _internal (PyInstaller 6+)
            base_dir = os.path.dirname(os.path.abspath(sys.executable))
            
            # Check next to executable (legacy / one-dir custom)
            possible_path = os.path.join(base_dir, filename)
            if os.path.exists(possible_path):
                return os.path.abspath(possible_path)
            
            # Check in _internal (PyInstaller 6+ default)
            possible_path_internal = os.path.join(base_dir, '_internal', filename)
            if os.path.exists(possible_path_internal):
                return os.path.abspath(possible_path_internal)
                
    else:
        # DEV MODE (Running from source)
        project_root = Path(__file__).parent.absolute()
        if system == 'win32':
            # external/windows_x86/
            tool_path = project_root / 'external' / 'windows_x86' / filename
        elif system == 'darwin':
            # external/macos/
            tool_path = project_root / 'external' / 'macos' / filename
        else:
            # Linux or other? Assume system path.
            return tool_name
            
        if tool_path.exists():
            return str(tool_path)

    # Fallback to system PATH
    return tool_name


def check_ffprobe():
    """Check if ffprobe is available"""
    tool_path = get_external_tool_path('ffprobe')
    try:
        # Increased timeout to 30s as 5s was causing issues on some Windows systems
        # likely due to antivirus scanning or slow disk I/O on first run
        subprocess.run([tool_path, '-version'], 
                      capture_output=True, check=True, timeout=30, creationflags=SUBPROCESS_FLAGS)
        return True, None
    except Exception as e:
        return False, f"Path: {tool_path}\nError: {str(e)}"


def check_exiftool():
    """Check if exiftool is available"""
    tool_path = get_external_tool_path('exiftool')
    try:
        subprocess.run([tool_path, '-ver'], 
                      capture_output=True, check=True, timeout=30, creationflags=SUBPROCESS_FLAGS)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return False


def get_iso_from_exiftool(file_path):
    """Get ISO value from video file using exiftool"""
    tool_path = get_external_tool_path('exiftool')
    try:
        cmd = [
            tool_path, '-json',
            '-ISO', '-ISOSensitivity', '-RecommendedExposureIndex',
            '-ISO', '-ISOSensitivity', '-RecommendedExposureIndex',
            str(file_path)
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30, creationflags=SUBPROCESS_FLAGS)
        
        if result.returncode != 0:
            return None
        
        data = json.loads(result.stdout)
        if not data:
            return None
        
        metadata = data[0]
        
        # Try different ISO keys in order of preference
        iso_keys = ['ISO', 'ISOSensitivity', 'RecommendedExposureIndex']
        for key in iso_keys:
            if key in metadata and metadata[key]:
                iso_value = metadata[key]
                # Handle if it's a number or string
                if isinstance(iso_value, (int, float)):
                    return str(int(iso_value))
                return str(iso_value)
        
        return None
    except Exception as e:
        print(f"Warning: Failed to get ISO from {file_path}: {e}")
        return None


def get_video_files(path):
    """Get all video files recursively from path"""
    video_files = []
    path_obj = Path(path)
    
    if not path_obj.exists():
        return video_files
    
    for ext in VIDEO_EXTENSIONS:
        video_files.extend(path_obj.rglob(f'*{ext}'))
        video_files.extend(path_obj.rglob(f'*{ext.upper()}'))
    
    return sorted(set(video_files))


def analyze_video_file(file_path):
    """Analyze a single video file using ffprobe"""
    tool_path = get_external_tool_path('ffprobe')
    try:
        # First call: get basic stream info (added codec_name for ProRes RAW detection)
        cmd = [
            tool_path, '-v', 'error',
            '-select_streams', 'v:0',
            '-show_entries', 'stream=width,height,r_frame_rate,color_transfer,color_primaries,color_space,pix_fmt,codec_name,codec_tag_string',
            '-of', 'json',
            str(file_path)
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30, creationflags=SUBPROCESS_FLAGS)
        
        if result.returncode != 0:
            return None
        
        video_info = json.loads(result.stdout)
        
        if not video_info.get('streams'):
            return None
        
        stream = video_info['streams'][0]
        
        # Second call: check for Dolby Vision (DOVI) side data
        is_dolby_vision = False
        try:
            dovi_cmd = [
                tool_path, '-v', 'error',
                '-select_streams', 'v:0',
                '-show_entries', 'stream_side_data=side_data_type,dv_version_major,dv_version_minor,dv_profile,dv_level,rpu_present_flag,el_present_flag,bl_present_flag,dv_bl_signal_compatibility_id,dv_md_compression',
                '-of', 'json',
                str(file_path)
            ]
            
            dovi_result = subprocess.run(dovi_cmd, capture_output=True, text=True, timeout=30, creationflags=SUBPROCESS_FLAGS)
            
            if dovi_result.returncode == 0:
                dovi_info = json.loads(dovi_result.stdout)
                if dovi_info.get('streams') and len(dovi_info['streams']) > 0:
                    stream_dovi = dovi_info['streams'][0]
                    side_data_list = stream_dovi.get('side_data_list', [])
                    
                    for side_data in side_data_list:
                        side_data_type = side_data.get('side_data_type', '')
                        dv_version_major = side_data.get('dv_version_major', 0)
                        dv_profile = side_data.get('dv_profile', 0)
                        rpu_present_flag = side_data.get('rpu_present_flag', 0)
                        
                        # Check DOVI conditions (OR logic)
                        if (('DOVI' in side_data_type or 'Dolby' in side_data_type) or
                            dv_version_major > 0 or
                            dv_profile > 0 or
                            rpu_present_flag == 1):
                            is_dolby_vision = True
                            break
        except Exception as e:
            # If DOVI detection fails, continue without it
            print(f"Warning: Failed to detect DOVI for {file_path}: {e}")
            pass
        
        # Get width and height
        width = int(stream.get('width', 0))
        height = int(stream.get('height', 0))
        
        # Handle portrait videos
        effective_width = max(width, height)
        effective_height = min(width, height)
        
        # Determine resolution
        resolution = f"{width}x{height}"
        
        if effective_width < 1920 or effective_height < 1080:
            resolution_status = "低画质(<1080p)"
            resolution_color = "red"
            resolution_category = "Low"
            resolution_label = "low"
        elif effective_width >= 3840 and effective_height >= 2160:
            resolution_status = "4K ✓"
            resolution_color = "green"
            resolution_category = "4K"
            resolution_label = "excellent"
        else:
            resolution_status = "1080p"
            resolution_color = "yellow"
            resolution_category = "1080p"
            resolution_label = "good"
        
        # Determine framerate
        framerate_text = stream.get('r_frame_rate', '0/1')
        framerate = 0
        
        if '/' in framerate_text:
            try:
                num, den = map(float, framerate_text.split('/'))
                if den != 0:
                    framerate = num / den
            except:
                pass
        else:
            try:
                framerate = float(framerate_text)
            except:
                pass
        
        if framerate == 0:
            framerate_display = "未知"
            framerate_status = "未知"
            framerate_color = "gray"
            framerate_category = "Unknown"
        elif framerate < 28:
            framerate_display = f"{framerate:.1f} fps"
            framerate_status = "低帧率"
            framerate_color = "red"
            framerate_category = "Low"
        elif 55 <= framerate <= 65:
            framerate_display = "60 fps"
            framerate_status = "高帧率 ✓"
            framerate_color = "green"
            framerate_category = "High"
        elif (29 <= framerate <= 31) or (29.9 <= framerate <= 30.1):
            framerate_display = "30 fps"
            framerate_status = "标准帧率"
            framerate_color = "yellow"
            framerate_category = "Normal"
        else:
            framerate_display = f"{framerate:.1f} fps"
            framerate_status = framerate_display
            framerate_color = "white"
            framerate_category = "Other"
        
        # Determine color space
        color_info_array = []
        color_display_array = []
        color_space_color = "white"
        color_category = "SDR"
        is_hdr = False
        is_other_color_space = False
        is_raw_video = False
        
        # Check if file extension indicates RAW format
        file_ext = Path(file_path).suffix.lower()
        if file_ext in RAW_EXTENSIONS:
            is_raw_video = True
        
        # Check for ProRes RAW in .mov files
        codec_name = stream.get('codec_name', '').lower()
        codec_tag = stream.get('codec_tag_string', '').lower()
        if file_ext == '.mov':
            # ProRes RAW codecs: prores_raw, ap4h (ProRes 4444), etc.
            if 'prores' in codec_name and 'raw' in codec_name:
                is_raw_video = True
            elif codec_tag in ['aprh', 'aprn']:  # ProRes RAW HQ and ProRes RAW
                is_raw_video = True
        
        # Check color transfer
        color_transfer = stream.get('color_transfer')
        if color_transfer:
            if color_transfer == "smpte2084":
                color_info_array.append("PQ (SMPTE 2084)")
                color_display_array.append("HDR10")
                is_hdr = True
                color_space_color = "blue"
                color_category = "HDR"
            elif color_transfer == "arib-std-b67":
                color_info_array.append("HLG (ARIB STD-B67)")
                color_display_array.append("HDR HLG")
                is_hdr = True
                color_space_color = "blue"
                color_category = "HDR"
            elif color_transfer == "bt2020-10":
                color_info_array.append("BT.2020-10bit")
                color_display_array.append("HDR10")
                is_hdr = True
                color_space_color = "blue"
                color_category = "HDR"
            elif color_transfer == "bt2020":
                color_info_array.append("BT.2020")
                color_display_array.append("宽色域")
                is_other_color_space = True
                color_space_color = "red"
                color_category = "WideGamut"
            elif color_transfer == "bt709":
                color_info_array.append("Rec.709")
                color_category = "SDR"
            elif color_transfer == "smpte170m":
                color_info_array.append("BT.601")
                color_category = "SDR"
            elif color_transfer in ["gamma22", "gamma28"]:
                color_info_array.append(f"Gamma {color_transfer[5:]}")
                color_category = "SDR"
            else:
                color_info_array.append(color_transfer)
                color_display_array.append("非SDR")
                is_other_color_space = True
                color_space_color = "red"
                color_category = "Other"
        
        # Check color primaries (gamut)
        color_primaries = stream.get('color_primaries')
        if color_primaries and not is_hdr:
            if color_primaries == "bt2020" and color_category == "SDR":
                color_info_array.append("BT.2020色域")
                color_display_array.append("宽色域")
                is_other_color_space = True
                color_space_color = "red"
                color_category = "WideGamut"
            elif color_primaries == "p3":
                color_info_array.append("DCI-P3色域")
                color_display_array.append("广色域")
                is_other_color_space = True
                color_space_color = "red"
                color_category = "WideGamut"
            elif color_primaries not in ["bt709", "smpte170m"] and color_category == "SDR":
                color_info_array.append(f"{color_primaries}色域")
                color_display_array.append("非标准色域")
                is_other_color_space = True
                color_space_color = "red"
                color_category = "Other"
        
        # Check color space parameter
        color_space = stream.get('color_space')
        if color_space:
            if color_space == "bt2020nc":
                color_info_array.append("BT.2020非恒定亮度")
                color_display_array.append("BT.2020 NC")
            elif color_space == "bt2020c":
                color_info_array.append("BT.2020恒定亮度")
                color_display_array.append("BT.2020 CL")
            elif color_space == "bt709":
                color_info_array.append("BT.709色彩空间")
                color_display_array.append("Rec.709")
            else:
                color_info_array.append(f"{color_space}色彩空间")
                color_display_array.append(color_space)
        
        # Check pixel format
        pix_fmt = stream.get('pix_fmt')
        if pix_fmt and not is_hdr and color_category == "SDR":
            if 'p10' in pix_fmt or 'p12' in pix_fmt:
                color_info_array.append(f"10/12-bit色深: {pix_fmt}")
                color_display_array.append("高色深")
                is_other_color_space = True
                color_space_color = "red"
                color_category = "HighBitDepth"
            elif 'yuva' in pix_fmt:
                color_info_array.append(f"带Alpha通道: {pix_fmt}")
                color_display_array.append("带透明通道")
                is_other_color_space = True
                color_space_color = "red"
                color_category = "Advanced"
            elif 'yuv444' in pix_fmt:
                color_info_array.append(f"4:4:4色度抽样: {pix_fmt}")
                color_display_array.append("4:4:4格式")
                is_other_color_space = True
                color_space_color = "red"
                color_category = "Advanced"
            elif 'rgb' in pix_fmt or 'bgr' in pix_fmt:
                color_info_array.append(f"RGB格式: {pix_fmt}")
                color_display_array.append("RGB格式")
                is_other_color_space = True
                color_space_color = "red"
                color_category = "Advanced"
            else:
                color_info_array.append(f"像素格式: {pix_fmt}")
                color_display_array.append(pix_fmt)
        
        # Default values if no color info detected
        if not color_info_array:
            color_info_array.append("SDR")
            color_display_array.append("SDR")
        
        color_info = ", ".join(color_info_array)
        color_display = ", ".join(color_display_array) if color_display_array else "SDR"
        
        # Add RAW video warning if detected
        if is_raw_video:
            color_display = 'RAW视频'
            color_category = "RAW"
            is_other_color_space = True
        
        # Add Dolby Vision label if detected
        if is_dolby_vision:
            dolby_label = '杜比视界'
            color_display = dolby_label + ' ' + color_display if color_display else dolby_label
        
        if is_hdr:
            color_space_color = "blue"
        
        # Get ISO from exiftool
        iso_value = get_iso_from_exiftool(file_path)
        iso_display = iso_value if iso_value else "-"
        
        file_path_obj = Path(file_path)
        
        return {
            'directory': str(file_path_obj.parent),
            'fileName': file_path_obj.name,
            'fullPath': str(file_path_obj),
            'iso': iso_display,
            'resolution': resolution,
            'resolutionStatus': resolution_status,
            'resolutionColor': resolution_color,
            'resolutionCategory': resolution_category,
            'framerate': framerate_display,
            'framerateStatus': framerate_status,
            'framerateColor': framerate_color,
            'framerateCategory': framerate_category,
            'colorSpace': color_display,
            'colorInfo': color_info,
            'colorSpaceColor': color_space_color,
            'colorCategory': color_category,
            'resolutionLabel': resolution_label,
            'isDolbyVision': is_dolby_vision,
            'isRawVideo': is_raw_video
        }
    except Exception as e:
        print(f"Error analyzing {file_path}: {e}")
        return None


def generate_html_report(results, statistics, input_path):
    """Generate HTML report using external template file"""
    # Load template file
    # Load template file
    if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
        # Frozen (PyInstaller)
        base_path = Path(sys._MEIPASS)
        template_path = base_path / 'templates' / 'report_template.html'
    else:
        # Dev mode
        template_path = Path(__file__).parent / 'templates' / 'report_template.html'
    
    try:
        with open(template_path, 'r', encoding='utf-8') as f:
            html_template = f.read()
    except FileNotFoundError:
        return f"<html><body><h1>错误</h1><p>找不到模板文件: {template_path}</p></body></html>"
    
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    # Calculate percentages
    total = statistics['totalFiles']
    low_res_pct = round(statistics['lowResolutionCount'] / total * 100, 1) if total > 0 else 0
    good_res_pct = round(statistics['goodResolutionCount'] / total * 100, 1) if total > 0 else 0
    excellent_res_pct = round(statistics['excellentResolutionCount'] / total * 100, 1) if total > 0 else 0
    low_fps_pct = round(statistics['lowFramerateCount'] / total * 100, 1) if total > 0 else 0
    normal_fps_pct = round(statistics['normalFramerateCount'] / total * 100, 1) if total > 0 else 0
    high_fps_pct = round(statistics['highFramerateCount'] / total * 100, 1) if total > 0 else 0
    hdr_pct = round(statistics['hdrCount'] / total * 100, 1) if total > 0 else 0
    other_color_pct = round(statistics['otherColorSpaceCount'] / total * 100, 1) if total > 0 else 0
    sdr_pct = round(statistics['sdrCount'] / total * 100, 1) if total > 0 else 0
    
    # Generate table rows
    table_rows = ""
    if not results:
        table_rows = '''
            <tr>
                <td colspan="5" style="text-align: center; padding: 50px; color: #888;">
                    <h3>🎉 恭喜！</h3>
                    <p>没有发现需要警告的视频文件。</p>
                </td>
            </tr>
'''
    else:
        for result in results:
            # Determine row class
            row_class = ""
            if result['resolutionColor'] == 'red' or result['framerateColor'] == 'red' or result['colorSpaceColor'] == 'red':
                row_class = "red"
            elif result['resolutionColor'] == 'yellow' or result['framerateColor'] == 'yellow':
                row_class = "yellow"
            elif result['resolutionColor'] == 'green' or result['framerateColor'] == 'green':
                row_class = "green"
            if result['colorSpaceColor'] == 'blue':
                row_class = "blue"
            
            # Escape special characters for JavaScript
            escaped_dir = result['directory'].replace('\\', '\\\\').replace("'", "\\'").replace('"', '\\"').replace('\n', '\\n')
            escaped_file = result['fileName'].replace('\\', '\\\\').replace("'", "\\'").replace('"', '\\"').replace('\n', '\\n')
            escaped_full = result['fullPath'].replace('\\', '\\\\').replace("'", "\\'").replace('"', '\\"').replace('\n', '\\n')
            
            # Escape HTML characters for display
            display_dir = result['directory'].replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            display_file = result['fileName'].replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            display_res_status = result['resolutionStatus'].replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            display_fps_status = result['framerateStatus'].replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            
            # colorSpace may contain HTML (for Dolby Vision warning), so don't escape it
            display_color_space = result['colorSpace']
            
            # Build notes column based on conditions
            notes_content = ""
            iso_str = result.get('iso', '-')
            is_raw = result.get('isRawVideo', False)
            is_dolby = result.get('isDolbyVision', False)
            
            if is_dolby:
                notes_content = "杜比视界需要提前调色再导入"
            elif iso_str != '-':
                try:
                    iso_num = int(iso_str)
                    if is_raw and iso_num > 800:
                        notes_content = f"ISO为{iso_num}，考虑提前降噪"
                    elif not is_raw and iso_num > 4000:
                        notes_content = f"ISO为{iso_num}，考虑提前降噪"
                    else:
                        notes_content = "-"
                except ValueError:
                    notes_content = iso_str
            else:
                notes_content = "-"
            
            table_rows += f'''
            <tr class="data-row {row_class}">
                <td>
                    <button class="copy-btn" onclick="copyToClipboard('{escaped_dir}')" title="点击复制目录路径">{display_dir}</button>
                </td>
                <td>
                    <button class="copy-btn" onclick="copyToClipboard('{escaped_full}')" title="点击复制完整文件路径">{display_file}</button>
                </td>
                <td class="{result['resolutionColor']}">{display_res_status}</td>
                <td class="{result['framerateColor']}">{display_fps_status}</td>
                <td class="{result['colorSpaceColor']}">{display_color_space}</td>
                <td class="white">{notes_content}</td>
            </tr>
'''
    
    # Replace placeholders in template
    replacements = {
        '{{timestamp}}': timestamp,
        '{{input_path}}': str(input_path).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;'),
        '{{total_files}}': str(total),
        '{{low_resolution_count}}': str(statistics['lowResolutionCount']),
        '{{low_resolution_percent}}': str(low_res_pct),
        '{{good_resolution_count}}': str(statistics['goodResolutionCount']),
        '{{good_resolution_percent}}': str(good_res_pct),
        '{{excellent_resolution_count}}': str(statistics['excellentResolutionCount']),
        '{{excellent_resolution_percent}}': str(excellent_res_pct),
        '{{low_framerate_count}}': str(statistics['lowFramerateCount']),
        '{{low_framerate_percent}}': str(low_fps_pct),
        '{{normal_framerate_count}}': str(statistics['normalFramerateCount']),
        '{{normal_framerate_percent}}': str(normal_fps_pct),
        '{{high_framerate_count}}': str(statistics['highFramerateCount']),
        '{{high_framerate_percent}}': str(high_fps_pct),
        '{{hdr_count}}': str(statistics['hdrCount']),
        '{{hdr_percent}}': str(hdr_pct),
        '{{other_color_space_count}}': str(statistics['otherColorSpaceCount']),
        '{{other_color_space_percent}}': str(other_color_pct),
        '{{sdr_count}}': str(statistics['sdrCount']),
        '{{sdr_percent}}': str(sdr_pct),
        '{{table_rows}}': table_rows
    }
    
    # Apply all replacements
    html = html_template
    for placeholder, value in replacements.items():
        html = html.replace(placeholder, value)
    
    return html


class VideoAnalysisApp:
    def __init__(self, root):
        self.root = root
        self.root.title("🎬 视频批量分析工具")
        self.root.geometry("600x400")
        
        # Queue for thread communication
        self.queue = queue.Queue()
        
        # Main frame
        main_frame = ttk.Frame(root, padding="20")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        root.columnconfigure(0, weight=1)
        root.rowconfigure(0, weight=1)
        
        # Title
        title_label = ttk.Label(main_frame, text="🎬 视频批量分析工具", 
                                font=('Arial', 16, 'bold'))
        title_label.grid(row=0, column=0, columnspan=2, pady=(0, 20))
        
        # Folder selection
        folder_frame = ttk.Frame(main_frame)
        folder_frame.grid(row=1, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(0, 20))
        folder_frame.columnconfigure(0, weight=1)
        
        ttk.Label(folder_frame, text="选择要分析的文件夹:").grid(row=0, column=0, sticky=tk.W, pady=(0, 5))
        
        folder_select_frame = ttk.Frame(folder_frame)
        folder_select_frame.grid(row=1, column=0, sticky=(tk.W, tk.E))
        folder_select_frame.columnconfigure(0, weight=1)
        
        self.folder_path_var = tk.StringVar()
        folder_entry = ttk.Entry(folder_select_frame, textvariable=self.folder_path_var, state='readonly')
        folder_entry.grid(row=0, column=0, sticky=(tk.W, tk.E), padx=(0, 10))
        
        select_btn = ttk.Button(folder_select_frame, text="📁 选择文件夹", command=self.select_folder)
        select_btn.grid(row=0, column=1)
        
        # Analyze button (changed to "重新分析")
        self.analyze_btn = ttk.Button(main_frame, text="重新分析", command=self.start_analysis, state='disabled')
        self.analyze_btn.grid(row=2, column=0, columnspan=2, pady=(0, 20))
        
        # Progress frame
        progress_frame = ttk.LabelFrame(main_frame, text="分析进度", padding="10")
        progress_frame.grid(row=3, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=(0, 10))
        progress_frame.columnconfigure(0, weight=1)
        
        self.progress_var = tk.StringVar(value="等待开始分析...")
        self.progress_label = ttk.Label(progress_frame, textvariable=self.progress_var)
        self.progress_label.grid(row=0, column=0, sticky=tk.W, pady=(0, 5))
        
        self.progress_bar = ttk.Progressbar(progress_frame, mode='determinate')
        self.progress_bar.grid(row=1, column=0, sticky=(tk.W, tk.E))
        
        self.current_file_var = tk.StringVar()
        self.current_file_label = ttk.Label(progress_frame, textvariable=self.current_file_var, 
                                             font=('Arial', 9), foreground='gray')
        self.current_file_label.grid(row=2, column=0, sticky=tk.W, pady=(5, 0))
        
        # Status text
        self.status_text = tk.Text(main_frame, height=8, wrap=tk.WORD, state='disabled')
        self.status_text.grid(row=4, column=0, columnspan=2, sticky=(tk.W, tk.E, tk.N, tk.S), pady=(10, 0))
        main_frame.rowconfigure(4, weight=1)
        
        # Scrollbar for status text
        scrollbar = ttk.Scrollbar(main_frame, orient=tk.VERTICAL, command=self.status_text.yview)
        scrollbar.grid(row=4, column=2, sticky=(tk.N, tk.S))
        self.status_text.configure(yscrollcommand=scrollbar.set)
        
        # Check for queue updates
        self.root.after(100, self.check_queue)
    
    def log(self, message):
        """Add message to status text"""
        self.status_text.config(state='normal')
        self.status_text.insert(tk.END, message + '\n')
        self.status_text.see(tk.END)
        self.status_text.config(state='disabled')
    
    def select_folder(self):
        """Open folder selection dialog"""
        folder = filedialog.askdirectory(title="选择要分析的文件夹")
        if folder:
            self.folder_path_var.set(folder)
            self.log(f"已选择文件夹: {folder}")
            # Automatically start analysis after folder selection
            self.start_analysis()
    
    def start_analysis(self):
        """Start video analysis in background thread"""
        folder_path = self.folder_path_var.get()
        if not folder_path:
            messagebox.showerror("错误", "请先选择文件夹")
            return
        
        is_valid, error_msg = check_ffprobe()
        if not is_valid:
            messagebox.showerror("错误 - 未检测到 ffprobe", 
                               f"请确保已安装 FFmpeg。\n\n调试信息:\n{error_msg}")
            return
        
        # Disable button during analysis
        self.analyze_btn.config(state='disabled')
        self.progress_bar['value'] = 0
        self.progress_var.set("准备开始分析...")
        self.current_file_var.set("")
        self.status_text.config(state='normal')
        self.status_text.delete(1.0, tk.END)
        self.status_text.config(state='disabled')
        
        # Start analysis thread
        thread = threading.Thread(target=self.analyze_videos, args=(folder_path,), daemon=True)
        thread.start()
    
    def analyze_videos(self, path):
        """Analyze videos in background thread"""
        try:
            # Get video files
            video_files = get_video_files(path)
            total_files = len(video_files)
            
            if total_files == 0:
                self.queue.put(('error', '未找到视频文件'))
                return
            
            self.queue.put(('progress', 0, total_files, f'找到 {total_files} 个视频文件，开始分析...', ''))
            
            # Counters
            low_resolution_count = 0
            good_resolution_count = 0
            excellent_resolution_count = 0
            low_framerate_count = 0
            normal_framerate_count = 0
            high_framerate_count = 0
            hdr_count = 0
            other_color_space_count = 0
            results = []
            
            # Process each file
            for idx, file_path in enumerate(video_files, 1):
                # Analyze file
                result = analyze_video_file(file_path)
                
                if result:
                    # Update counters
                    if result['resolutionLabel'] == 'low':
                        low_resolution_count += 1
                    elif result['resolutionLabel'] == 'excellent':
                        excellent_resolution_count += 1
                    else:
                        good_resolution_count += 1
                    
                    if result['framerateCategory'] == 'Low':
                        low_framerate_count += 1
                    elif result['framerateCategory'] == 'High':
                        high_framerate_count += 1
                    elif result['framerateCategory'] == 'Normal':
                        normal_framerate_count += 1
                    
                    if result['colorCategory'] == 'HDR':
                        hdr_count += 1
                    elif result['colorCategory'] not in ['SDR']:
                        other_color_space_count += 1
                    
                    results.append(result)
                
                # Update progress
                percent = (idx / total_files) * 100
                self.queue.put(('progress', idx, total_files, 
                              f'正在分析: {idx}/{total_files} ({percent:.1f}%)',
                              file_path.name))
            
            # Calculate statistics
            sdr_count = total_files - hdr_count - other_color_space_count
            
            statistics = {
                'totalFiles': total_files,
                'lowResolutionCount': low_resolution_count,
                'goodResolutionCount': good_resolution_count,
                'excellentResolutionCount': excellent_resolution_count,
                'lowFramerateCount': low_framerate_count,
                'normalFramerateCount': normal_framerate_count,
                'highFramerateCount': high_framerate_count,
                'hdrCount': hdr_count,
                'otherColorSpaceCount': other_color_space_count,
                'sdrCount': sdr_count
            }
            
            # Generate HTML report
            html_content = generate_html_report(results, statistics, path)
            report_path = Path(path) / '视频报告.html'
            report_path.write_text(html_content, encoding='utf-8')
            
            self.queue.put(('completed', str(report_path), statistics))
            
        except Exception as e:
            self.queue.put(('error', f'分析过程中出错: {str(e)}'))
    
    def check_queue(self):
        """Check for messages from analysis thread"""
        try:
            while True:
                msg = self.queue.get_nowait()
                
                if msg[0] == 'progress':
                    current, total, message, current_file = msg[1], msg[2], msg[3], msg[4]
                    percent = (current / total) * 100 if total > 0 else 0
                    self.progress_bar['value'] = percent
                    self.progress_var.set(message)
                    self.current_file_var.set(current_file if current_file else "")
                    self.log(message + (f" - {current_file}" if current_file else ""))
                
                elif msg[0] == 'completed':
                    report_path, statistics = msg[1], msg[2]
                    self.progress_bar['value'] = 100
                    self.progress_var.set("分析完成！")
                    self.current_file_var.set("")
                    
                    self.log(f"分析完成！共分析 {statistics['totalFiles']} 个文件")
                    self.log(f"报告已保存到: {report_path}")
                    
                    # Open report in browser
                    report_url = Path(report_path).as_uri()
                    webbrowser.open(report_url)
                    self.log(f"已在浏览器中打开报告")
                    
                    self.analyze_btn.config(state='normal')
                    messagebox.showinfo("完成", f"分析完成！\n\n报告已保存并自动打开。\n\n路径: {report_path}")
                
                elif msg[0] == 'error':
                    error_msg = msg[1]
                    self.progress_var.set("错误")
                    self.current_file_var.set("")
                    self.log(f"错误: {error_msg}")
                    self.analyze_btn.config(state='normal')
                    messagebox.showerror("错误", error_msg)
        
        except queue.Empty:
            pass
        
        # Schedule next check
        self.root.after(100, self.check_queue)


def main():
    """Main entry point"""
    if not check_ffprobe():
        print("警告: 未检测到 ffprobe，请确保已安装 FFmpeg 并添加到系统 PATH")
        response = input("是否继续? (y/n): ").strip().lower()
        if response != 'y':
            return
    
    root = tk.Tk()
    app = VideoAnalysisApp(root)
    root.mainloop()


if __name__ == '__main__':
    main()

