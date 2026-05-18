"""VulnBoard — Beaver Recruit Inc. internal coding evaluation platform.

This service grades Python submissions by piping them into an ephemeral
python:3.11-slim container spawned through the host Docker daemon.

Known TODO carried over from the 0.3 prototype:
    SECURITY-142: migrate `result_cache` cookie from pickle to signed JSON
                  before public-facing recruitment launch.
"""
import base64
import os
import pickle
import subprocess

from flask import Flask, make_response, redirect, render_template_string, request

app = Flask(__name__)


INDEX_HTML = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>VulnBoard - Beaver Recruit Coding Evaluation</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: 'SF Mono', Menlo, Consolas, monospace; background: #0f1419; color: #d4d4d4; margin: 0; }
  .header { background: #1e293b; padding: 20px 40px; border-bottom: 2px solid #334155; }
  .header h1 { margin: 0; color: #38bdf8; font-size: 22px; }
  .header p { margin: 4px 0 0 0; color: #94a3b8; font-size: 13px; }
  .container { max-width: 900px; margin: 30px auto; padding: 30px; background: #1e293b; border-radius: 8px; }
  .meta { color: #94a3b8; font-size: 13px; margin-bottom: 16px; line-height: 1.5; }
  textarea { width: 100%; height: 280px; background: #0f172a; color: #e2e8f0; border: 1px solid #334155; border-radius: 4px; padding: 15px; font-family: inherit; font-size: 13px; resize: vertical; }
  button { background: #38bdf8; color: #0f172a; padding: 12px 32px; border: 0; border-radius: 4px; font-weight: 600; cursor: pointer; margin-top: 14px; font-size: 14px; font-family: inherit; }
  button:hover { background: #0ea5e9; }
  .footer { color: #475569; font-size: 11px; text-align: center; margin-top: 30px; }
</style>
</head>
<body>
<div class="header">
  <h1>VulnBoard</h1>
  <p>Beaver Recruit Inc. - Internal Coding Evaluation Platform v0.4.2</p>
</div>
<div class="container">
  <div class="meta">
    <strong>Problem #1:</strong> Implement <code>solution(a, b)</code> that returns the sum of two integers.<br>
    Your script must print the result of <code>solution(2, 3)</code> to stdout.
  </div>
  <form method="POST" action="/submit">
<textarea name="code">def solution(a, b):
    return a + b

print(solution(2, 3))</textarea>
    <button type="submit">Run &amp; Grade</button>
  </form>
  <div class="footer">VulnBoard internal build. Issues? Ping #vulnboard-support on Slack.</div>
</div>
</body>
</html>'''


RESULT_HTML = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>VulnBoard - Grading Result</title>
<style>
  body { font-family: 'SF Mono', Menlo, Consolas, monospace; background: #0f1419; color: #d4d4d4; margin: 0; }
  .header { background: #1e293b; padding: 20px 40px; border-bottom: 2px solid #334155; }
  .header h1 { margin: 0; color: #38bdf8; font-size: 22px; }
  .container { max-width: 900px; margin: 30px auto; padding: 30px; background: #1e293b; border-radius: 8px; }
  .score { font-size: 36px; color: {{ color }}; margin-bottom: 16px; font-weight: 600; }
  .label { color: #94a3b8; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; margin-top: 18px; margin-bottom: 6px; }
  pre { background: #0f172a; padding: 14px; border-radius: 4px; overflow-x: auto; color: #cbd5e1; font-size: 12px; margin: 0; }
  a { color: #38bdf8; text-decoration: none; }
  a:hover { text-decoration: underline; }
</style>
</head>
<body>
<div class="header"><h1>VulnBoard - Result</h1></div>
<div class="container">
  <div class="score">{{ score }} / 100</div>
  <div class="label">Verdict</div>
  <pre>{{ verdict }}</pre>
  <div class="label">Output</div>
  <pre>{{ output }}</pre>
  <p style="margin-top: 24px;"><a href="/">&larr; Submit another solution</a></p>
</div>
</body>
</html>'''


class GradeResult(object):
    """Result of a single submission graded by the sandboxed runner.

    Serialized into the `result_cache` cookie so the result page can be
    re-rendered without re-running the sandbox (legacy implementation,
    predates the JSON migration plan in SECURITY-142).
    """

    def __init__(self, score, verdict, output):
        self.score = int(score)
        self.verdict = str(verdict)
        self.output = str(output)


def _grade(code):
    """Run user code inside an ephemeral python:3.11-slim container.

    Communication is via stdin so we don't have to bind-mount a host path
    (the Flask container would have to share a directory with the host
    daemon, which we explicitly want to avoid).
    """
    try:
        proc = subprocess.run(
            [
                'docker', 'run', '--rm', '-i',
                '--network', 'none',
                '--memory', '128m',
                '--cpus', '0.5',
                '--read-only',
                '--tmpfs', '/tmp:size=16m',
                'python:3.11-slim',
                'python', '-',
            ],
            input=code,
            capture_output=True,
            text=True,
            timeout=15,
        )
        output = (proc.stdout or '') + (proc.stderr or '')
        if proc.returncode == 0:
            return GradeResult(100, 'PASS', output[:4000])
        return GradeResult(0, 'FAIL', output[:4000])
    except subprocess.TimeoutExpired:
        return GradeResult(0, 'TIMEOUT', 'Execution exceeded the 15s wall-clock limit.')
    except Exception as exc:
        return GradeResult(0, 'RUNNER_ERROR', 'Sandbox runner failed: {0}'.format(exc))


@app.route('/', methods=['GET'])
def index():
    return render_template_string(INDEX_HTML)


@app.route('/submit', methods=['POST'])
def submit():
    code = request.form.get('code', '')
    if not code.strip():
        return redirect('/')

    result = _grade(code)

    # Legacy: pickle the result object into a cookie so /result can re-render
    # without re-running the sandbox. Pending migration in SECURITY-142.
    serialized = base64.b64encode(pickle.dumps(result)).decode('ascii')
    resp = make_response(redirect('/result'))
    resp.set_cookie('result_cache', serialized, max_age=600, httponly=True)
    return resp


@app.route('/result', methods=['GET'])
def result_view():
    cookie = request.cookies.get('result_cache')
    if not cookie:
        return redirect('/')
    try:
        decoded = base64.b64decode(cookie.encode('ascii'))
        result = pickle.loads(decoded)
    except Exception as exc:
        return 'Failed to decode cached result: {0}'.format(exc), 400

    verdict = getattr(result, 'verdict', '?')
    color = '#22c55e' if verdict == 'PASS' else '#ef4444'
    return render_template_string(
        RESULT_HTML,
        score=getattr(result, 'score', 0),
        verdict=verdict,
        output=getattr(result, 'output', ''),
        color=color,
    )


@app.route('/health', methods=['GET'])
def health():
    return 'OK', 200


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
