# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

# External tools path
external_macos = 'external/macos'

a = Analysis(
    ['gui_app.py'],
    pathex=[],
    binaries=[
        (f'{external_macos}/ffprobe', '.'),
        (f'{external_macos}/exiftool', '.')
    ],
    datas=[('templates', 'templates')],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='Video Meta Report',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    # target_arch='x86_64',  # Removed to allow native build (arm64 on Apple Silicon)
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='Video Meta Report',
)

app = BUNDLE(
    coll,
    name='Video Meta Report.app',
    icon=None,
    bundle_identifier='com.ibobby.videometa',
    info_plist={
        'CFBundleShortVersionString': '1.0.0',
        'NSHighResolutionCapable': 'True'
    },
)
