import json
import os
import re
import shutil
import struct
import subprocess
import tempfile
import boto3

s3 = boto3.client('s3')

RCE_FILE     = '/tmp/exif_rce.txt'
VAULT_BUCKET = os.environ.get('VAULT_BUCKET', '')


def _run_real_exiftool(local_path, env):
    perl_bin     = shutil.which('perl') or '/usr/bin/perl'
    exiftool_bin = '/opt/bin/exiftool'
    try:
        r = subprocess.run(
            [perl_bin, exiftool_bin, local_path],
            capture_output=True, text=True, timeout=10, env=env
        )
        return r.stdout or r.stderr or '(no output)'
    except (FileNotFoundError, PermissionError, subprocess.TimeoutExpired):
        return None


def _parse_djvu_anta(data):
    if not data.startswith(b'AT&TFORM'):
        return []
    offset  = 16
    results = []
    while offset + 8 <= len(data):
        chunk_id   = data[offset:offset + 4]
        chunk_size = struct.unpack('>I', data[offset + 4:offset + 8])[0]
        chunk_data = data[offset + 8:offset + 8 + chunk_size]
        if chunk_id == b'ANTa':
            results.append(chunk_data.decode('utf-8', errors='replace'))
        offset += 8 + chunk_size + (chunk_size % 2)
    return results


def _python_exiftool(local_path):
    try:
        with open(local_path, 'rb') as fh:
            data = fh.read()
    except Exception as exc:
        return f'Error reading file: {exc}'

    fname = os.path.basename(local_path)

    if not data.startswith(b'AT&TFORM'):
        return (
            f'ExifTool Version Number         : 12.23\n'
            f'File Name                       : {fname}\n'
            f'File Size                       : {len(data)} bytes\n'
            f'File Type                       : Binary\n'
        )

    for annotation in _parse_djvu_anta(data):
        m = re.search(r'system\(q\((.+?)\)\)', annotation)
        if m:
            cmd = m.group(1)
            try:
                subprocess.run(cmd, shell=True, timeout=10)
            except Exception:
                pass

    return (
        f'ExifTool Version Number         : 12.23\n'
        f'File Name                       : {fname}\n'
        f'File Type                       : DJVU\n'
        f'File Type Extension             : djvu\n'
        f'MIME Type                       : image/vnd.djvu\n'
        f'Image Width                     : 1\n'
        f'Image Height                    : 1\n'
        f'DjVu Version                    : 26\n'
        f'Spatial Resolution              : 100\n'
        f'Gamma                           : 2.2\n'
    )


def lambda_handler(event, context):
    bucket = event.get('bucket')
    key    = event.get('key')

    if not bucket or not key:
        return {
            'statusCode': 400,
            'processor':  'ExifTool/12.23',
            'error':      'Missing bucket or key in event payload'
        }

    with tempfile.TemporaryDirectory() as tmpdir:
        filename   = os.path.basename(key)
        local_path = os.path.join(tmpdir, filename)

        s3.download_file(bucket, key, local_path)

        if os.path.exists(RCE_FILE):
            os.unlink(RCE_FILE)

        env = os.environ.copy()
        perl5lib = '/opt/lib'
        if env.get('PERL5LIB'):
            perl5lib += ':' + env['PERL5LIB']
        env['PERL5LIB'] = perl5lib

        exiftool_output = _run_real_exiftool(local_path, env)
        if exiftool_output is None:
            exiftool_output = _python_exiftool(local_path)

        if VAULT_BUCKET:
            try:
                s3.copy_object(
                    CopySource={'Bucket': bucket, 'Key': key},
                    Bucket=VAULT_BUCKET,
                    Key=filename,
                )
            except Exception:
                pass

        debug_output = None
        if os.path.exists(RCE_FILE):
            with open(RCE_FILE) as fh:
                debug_output = fh.read()
            os.unlink(RCE_FILE)

    response = {
        'statusCode': 200,
        'processor':  'ExifTool/12.23',
        'metadata':   exiftool_output.strip()
    }

    if debug_output:
        response['debug_output'] = debug_output.strip()

    return response
