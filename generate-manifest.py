#!/usr/bin/env python3
"""Generate files.json manifest for the File Storage website."""

import os
import json
import sys

def get_file_type(filename):
    ext = filename.split('.')[-1].lower() if '.' in filename else ''
    # Handle multi-part files: name.zip.001, name.rar.002, etc.
    parts = filename.lower().split('.')
    if len(parts) >= 3 and parts[-2] in ('zip', 'rar', '7z', 'tar', 'gz') and parts[-1].isdigit():
        return 'archive'
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

def main():
    # Determine the project root (directory containing this script)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = script_dir
    
    files_dir = os.path.join(project_root, 'files')
    output_path = os.path.join(files_dir, 'files.json')
    
    if not os.path.isdir(files_dir):
        print(f"Error: 'files' directory not found at {files_dir}", file=sys.stderr)
        sys.exit(1)
    
    manifest = []
    
    def scan_directory(directory, base_path=''):
        entries = sorted(os.listdir(directory))
        for entry in entries:
            if entry == 'files.json':
                continue
            
            full_path = os.path.join(directory, entry)
            rel_path = os.path.join(base_path, entry) if base_path else entry
            
            if os.path.isfile(full_path):
                size = os.path.getsize(full_path)
                file_type = get_file_type(entry)
                manifest.append({
                    'name': rel_path,
                    'size': size,
                    'type': file_type
                })
            elif os.path.isdir(full_path):
                scan_directory(full_path, rel_path)
    
    scan_directory(files_dir)
    
    with open(output_path, 'w') as f:
        json.dump(manifest, f, indent=2)
    
    print(f"Generated {output_path} with {len(manifest)} file(s).")

if __name__ == '__main__':
    main()
