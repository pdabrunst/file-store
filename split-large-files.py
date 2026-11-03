#!/usr/bin/env python3
"""Split large files in files/ into GitHub-friendly multi-part ZIP chunks."""

import os
import sys
import subprocess
import shutil

MAX_SIZE = 95 * 1024 * 1024  # 95 MB

def get_file_type(filename):
    ext = filename.split('.')[-1].lower() if '.' in filename else ''
    types = {
        'image': ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico'],
        'document': ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'odt'],
        'video': ['mp4', 'avi', 'mov', 'wmv', 'flv', 'mkv', 'webm'],
        'audio': ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma'],
        'archive': ['zip', 'rar', '7z', 'tar', 'gz', 'bz2'],
        'code': ['js', 'html', 'css', 'py', 'java', 'cpp', 'c', 'php', 'json', 'xml']
    }
    for type_name, exts in types.items():
        if ext in exts:
            return type_name
    return 'other'

def split_file(filepath):
    """Split a large file into a multi-part ZIP archive using the zip command."""
    base = os.path.basename(filepath)
    name, ext = os.path.splitext(base)
    folder = os.path.join(os.path.dirname(filepath), name)
    
    # Create output paths
    os.makedirs(folder, exist_ok=True)
    output_zip = os.path.join(folder, base)
    
    print(f"Splitting {base} ({os.path.getsize(filepath) / (1024*1024):.1f} MB) into {folder}/")
    
    # Use zip command to create split archive
    # -r = recursive (not needed for single files but safe)
    # -s 95m = split into 95MB volumes
    # The zip command creates: output.zip, output.z01, output.z02, ...
    cmd = ['zip', '-s', '95m', output_zip, filepath]
    
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        print(f"Error splitting {base}: {e.stderr}", file=sys.stderr)
        return False
    
    # Remove original file
    os.remove(filepath)
    
    # Rename .z01, .z02, etc. to .zip.001, .zip.002 for clarity
    for item in os.listdir(folder):
        if item.startswith(os.path.basename(output_zip) + '.z') and len(item) == len(os.path.basename(output_zip)) + 4:
            # e.g., "archive.z01" -> "archive.zip.001"
            part_num = item.split('.z')[-1]  # "01"
            new_name = f"{base}.{part_num}"  # "archive.zip.001"
            old_path = os.path.join(folder, item)
            new_path = os.path.join(folder, new_name)
            shutil.move(old_path, new_path)
    
    return True

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    files_dir = os.path.join(script_dir, 'files')
    
    if not os.path.isdir(files_dir):
        print(f"Error: 'files' directory not found at {files_dir}", file=sys.stderr)
        sys.exit(1)
    
    split = False
    
    for entry in sorted(os.listdir(files_dir)):
        full_path = os.path.join(files_dir, entry)
        
        # Skip directories and the manifest
        if os.path.isdir(full_path) or entry == 'files.json':
            continue
        
        # Check if file exceeds max size
        if os.path.getsize(full_path) > MAX_SIZE:
            if split_file(full_path):
                split = True
    
    if split:
        print("Split complete. Run generate-manifest.py to update files.json.")
    else:
        print("No files needed splitting.")

if __name__ == '__main__':
    main()
