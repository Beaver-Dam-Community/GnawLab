#!/bin/bash
set -e

dnf install -y python3 python3-pip
pip3 install flask boto3

cat > /home/ec2-user/app.py << 'PYEOF'
import sqlite3, hashlib, boto3, json, os, uuid
from flask import Flask, request, render_template_string, redirect, url_for, session, make_response

app = Flask(__name__)
app.secret_key = 'beaversound-dev-2024-portal'

REGION         = os.environ.get('AWS_DEFAULT_REGION', 'us-east-1')
UPLOADS_BUCKET = os.environ.get('UPLOADS_BUCKET', '')
LAMBDA_FUNC    = os.environ.get('LAMBDA_FUNCTION', '')
DB_PATH        = '/home/ec2-user/portal.db'

s3_client  = boto3.client('s3',     region_name=REGION)
lam_client = boto3.client('lambda', region_name=REGION)

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    with get_db() as c:
        c.execute('''CREATE TABLE IF NOT EXISTS users
                    (id INTEGER PRIMARY KEY, email TEXT UNIQUE NOT NULL,
                     name TEXT NOT NULL, password TEXT NOT NULL)''')
        c.commit()

init_db()

def hash_pw(pw):
    return hashlib.sha256(pw.encode()).hexdigest()

# ── CSS ──────────────────────────────────────────────────────────────────────
CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, sans-serif; background: #12121f; color: #ccc; }
.nav { background: #1a1a30; padding: 14px 28px; display: flex; align-items: center;
       gap: 28px; border-bottom: 1px solid #2d2d50; }
.logo { color: #f5a623; font-weight: 700; font-size: 18px; text-decoration: none; }
.nav-link { color: #888; text-decoration: none; font-size: 13px; }
.nav-link:hover { color: #fff; }
.nav-right { margin-left: auto; display: flex; gap: 16px; align-items: center; }
.main { max-width: 760px; margin: 40px auto; padding: 0 20px; }
.card { background: #1a1a30; border: 1px solid #2d2d50; border-radius: 10px;
        padding: 24px; margin-bottom: 20px; }
h1 { color: #fff; font-size: 22px; margin-bottom: 6px; }
h2 { color: #f5a623; font-size: 15px; margin-bottom: 14px; font-weight: 600; }
p  { color: #999; font-size: 13px; line-height: 1.6; margin-bottom: 10px; }
label { display: block; color: #aaa; font-size: 12px; margin-bottom: 4px; }
input[type=text], input[type=email], input[type=password] {
  width: 100%; padding: 9px 12px; background: #0d0d1a; border: 1px solid #3d3d65;
  border-radius: 6px; color: #e0e0e0; font-size: 13px; margin-bottom: 12px; outline: none; }
input:focus { border-color: #f5a623; }
.btn { padding: 9px 22px; background: #f5a623; color: #12121f; border: none;
       border-radius: 6px; font-size: 13px; font-weight: 600; cursor: pointer; }
.btn:hover { background: #d99020; }
.btn-outline { background: transparent; border: 1px solid #f5a623; color: #f5a623; }
.btn-sm { padding: 6px 14px; font-size: 12px; }
.alert-error { background: #2d1010; border: 1px solid #6b2020; color: #ff9090;
               padding: 10px 14px; border-radius: 6px; margin-bottom: 14px; font-size: 13px; }
.alert-ok { background: #102d1a; border: 1px solid #206b3a; color: #90ffa0;
             padding: 10px 14px; border-radius: 6px; margin-bottom: 14px; font-size: 13px; }
.code-box { background: #0a0a14; border: 1px solid #2d2d50; border-radius: 6px;
            padding: 14px; font-family: monospace; font-size: 11px; white-space: pre-wrap;
            word-break: break-all; color: #90d090; max-height: 360px; overflow-y: auto;
            margin-top: 10px; }
.rce-box  { background: #1a0a0a; border: 1px solid #8b2020; border-radius: 6px;
            padding: 14px; font-family: monospace; font-size: 11px; white-space: pre-wrap;
            word-break: break-all; color: #ff9090; max-height: 360px; overflow-y: auto;
            margin-top: 10px; }
.badge { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 11px;
         background: #f5a623; color: #12121f; font-weight: 600; }
.badge-red { background: #8b2020; color: #ffaaaa; }
.info-row { display: flex; justify-content: space-between; padding: 6px 0;
            border-bottom: 1px solid #23233a; font-size: 13px; }
.info-row:last-child { border-bottom: none; }
.muted { color: #555; font-size: 11px; }
a { color: #f5a623; text-decoration: none; }
"""

# ── TEMPLATES ─────────────────────────────────────────────────────────────────
HOME_HTML = """<!DOCTYPE html><html lang='en'><head><title>BeaverSound — Artist Portal</title>
<meta charset='utf-8'><style>""" + CSS + """</style></head><body>
<nav class='nav'>
  <a class='logo' href='/'>&#127925; BeaverSound</a>
  <a class='nav-link' href='/news'>News</a>
  <div class='nav-right'>
    {% if user %}
      <span class='muted'>{{ user }}</span>
      <a class='nav-link' href='/logout'>Sign out</a>
    {% else %}
      <a class='btn btn-sm btn-outline' href='/register'>Sign up</a>
    {% endif %}
  </div>
</nav>
<div class='main'>
{% if user %}
  <div class='card'>
    <h1>Artist Dashboard</h1>
    <p>Welcome back, <strong style='color:#f5a623'>{{ user }}</strong>.
       Submit your master recordings for distribution to Spotify, Apple Music, and more.</p>
  </div>
  <div class='card'>
    <h2>Upload Master Recording</h2>
    <p>Accepted formats: MP3, WAV, FLAC, MP4, AIFF. Files are processed by our metadata
       pipeline before being queued for distribution.</p>
    {% if upload_error %}<div class='alert-error'>{{ upload_error }}</div>{% endif %}
    <form method='POST' action='/upload' enctype='multipart/form-data'>
      <label for='f' class='btn btn-outline btn-sm' style='cursor:pointer;margin-bottom:14px'>Choose File — <span id='fn' style='font-weight:normal;color:#888'>No file selected</span></label>
      <input type='file' name='file' id='f' style='display:none' onchange="document.getElementById('fn').textContent=this.files[0].name">
      <button class='btn' type='submit'>Upload &amp; Process</button>
    </form>
  </div>
  <div class='card'>
    <h2>Platform Info</h2>
    <div class='info-row'><span>Metadata Pipeline</span><span class='badge'>Active</span></div>
    <div class='info-row'><span>Distribution</span><span style='color:#999'>Spotify · Apple Music · Tidal</span></div>
    <div class='info-row'><span>Processor</span><span style='color:#888; font-family:monospace; font-size:12px'>ExifTool/12.23</span></div>
    <div class='info-row'><span>Malware Scanning</span><span style='color:#90ffa0; font-size:12px'>GuardDuty Enabled</span></div>
  </div>
{% else %}
  <div class='card' style='max-width:400px; margin:0 auto'>
    <h1>Sign In</h1>
    <p style='margin-bottom:20px'>Access your BeaverSound artist account.</p>
    {% if error %}<div class='alert-error'>{{ error }}</div>{% endif %}
    <form method='POST' action='/login' novalidate>
      <label>Email</label>
      <input type='email' name='email' placeholder='artist@example.com' required>
      <label>Password</label>
      <input type='password' name='password' placeholder='••••••••' required>
      <button class='btn' type='submit' style='width:100%'>Log In</button>
    </form>
    <p style='margin-top:16px; text-align:center'>
      Don't have an account? <a href='/register'>Sign up free</a>
    </p>
  </div>
{% endif %}
</div></body></html>"""

REGISTER_HTML = """<!DOCTYPE html><html lang='en'><head><title>BeaverSound — Sign Up</title>
<meta charset='utf-8'><style>""" + CSS + """</style></head><body>
<nav class='nav'>
  <a class='logo' href='/'>&#127925; BeaverSound</a>
  <a class='nav-link' href='/news'>News</a>
  <div class='nav-right'><a class='nav-link' href='/'>Sign in</a></div>
</nav>
<div class='main'>
  <div class='card' style='max-width:440px; margin:0 auto'>
    <h1>Create Artist Account</h1>
    <p style='margin-bottom:20px'>Free to join. Distribute your music globally.</p>
    {% if error %}<div class='alert-error'>{{ error }}</div>{% endif %}
    <form method='POST' novalidate>
      <label>Display Name</label>
      <input type='text' name='name' placeholder='Your artist name' required>
      <label>Email</label>
      <input type='email' name='email' placeholder='you@example.com' required>
      <label>Password</label>
      <input type='password' name='password' placeholder='At least 8 characters' required>
      <button class='btn' type='submit' style='width:100%'>Create Account</button>
    </form>
    <p style='margin-top:16px; text-align:center'>Already have an account? <a href='/'>Sign in</a></p>
  </div>
</div></body></html>"""

RESULT_HTML = """<!DOCTYPE html><html lang='en'><head><title>BeaverSound — Processing Result</title>
<meta charset='utf-8'><style>""" + CSS + """</style></head><body>
<nav class='nav'>
  <a class='logo' href='/'>&#127925; BeaverSound</a>
  <a class='nav-link' href='/news'>News</a>
  <div class='nav-right'><a class='nav-link' href='/logout'>Sign out</a></div>
</nav>
<div class='main'>
  <div class='card'>
    <h1>Processing Result</h1>
    {% if filename %}<p>File: <code style='color:#f5a623'>{{ filename }}</code></p>{% endif %}
    <div class='info-row'>
      <span>Processor</span>
      <span style='font-family:monospace; font-size:12px; color:#f5a623'>{{ processor }}</span>
    </div>
    <div class='info-row'>
      <span>GuardDuty Malware Scan</span>
      <span style='color:#90ffa0; font-size:12px'>NO_THREATS_FOUND</span>
    </div>
  </div>
  {% if error %}
  <div class='card'>
    <h2>Error</h2>
    <div class='code-box'>{{ error }}</div>
  </div>
  {% endif %}
  {% if metadata %}
  <div class='card'>
    <h2>Extracted Metadata</h2>
    <div class='code-box'>{{ metadata }}</div>
  </div>
  {% endif %}
  {% if debug_output %}
  <div class='card'>
    <h2 style='color:#ff9090'>&#9888; Debug Output <span class='badge badge-red'>RCE</span></h2>
    <p style='color:#888'>Content captured from the metadata pipeline execution environment:</p>
    <div class='rce-box'>{{ debug_output }}</div>
  </div>
  {% endif %}
  <p style='margin-top:10px'><a href='/'>&#8592; Back to dashboard</a></p>
</div></body></html>"""

NEWS_HTML = """<!DOCTYPE html><html lang='en'><head><title>BeaverSound News</title>
<meta charset='utf-8'><style>""" + CSS + """</style></head><body>
<nav class='nav'>
  <a class='logo' href='/'>&#127925; BeaverSound</a>
  <a class='nav-link' href='/news'>News</a>
  <div class='nav-right'><a class='nav-link' href='/'>Portal</a></div>
</nav>
<div class='main'>
  <div class='card'>
    <p class='muted' style='margin-bottom:8px'>BeaverSound Editorial &nbsp;·&nbsp; May 9, 2026</p>
    <h1 style='font-size:20px; line-height:1.4; margin-bottom:16px'>
      BeaverSound Removes Unreleased Maya Arden Tracklist Following Label Dispute
    </h1>
    <p>Following a formal takedown request from Stellar Records, BeaverSound has removed
       an unauthorized distribution submission for Maya Arden's upcoming album
       <em style='color:#f5a623'>Neon Fault Line</em>.</p>
    <p>The file — a tracklist for the unannounced album — was submitted through the
       BeaverSound platform by an unknown party and held in the distribution vault
       awaiting processing. Stellar Records, which holds exclusive rights to Maya Arden's
       catalog, confirmed that the tracklist had not been authorized for public release
       and demanded its immediate removal.</p>
    <p>"We take intellectual property disputes seriously," said a BeaverSound spokesperson.
       "The file has been permanently removed from our systems and we are cooperating
       fully with Stellar Records to prevent future unauthorized submissions."</p>
    <p>Maya Arden's management declined to comment. The album's official release date
       has not been announced.</p>
    <p class='muted' style='margin-top:16px'>— BeaverSound Editorial Team</p>
  </div>
</div></body></html>"""

# ── ROUTES ────────────────────────────────────────────────────────────────────
@app.route('/')
def index():
    user = session.get('user_name')
    return render_template_string(HOME_HTML, user=user)

@app.route('/login', methods=['POST'])
def login():
    email = request.form.get('email', '').strip()
    password = request.form.get('password', '')
    with get_db() as c:
        row = c.execute('SELECT * FROM users WHERE email=?', (email,)).fetchone()
    if row and row['password'] == hash_pw(password):
        session['user_id']   = row['id']
        session['user_name'] = row['name']
        return redirect(url_for('index'))
    return render_template_string(HOME_HTML, user=None, error='Invalid email or password.')

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'GET':
        return render_template_string(REGISTER_HTML)
    name     = request.form.get('name', '').strip()
    email    = request.form.get('email', '').strip().lower()
    password = request.form.get('password', '')
    if not name or not email or len(password) < 8:
        return render_template_string(REGISTER_HTML, error='All fields required; password min 8 chars.')
    try:
        with get_db() as c:
            c.execute('INSERT INTO users (email, name, password) VALUES (?,?,?)',
                      (email, name, hash_pw(password)))
            c.commit()
    except sqlite3.IntegrityError:
        return render_template_string(REGISTER_HTML, error='Email already registered.')
    session['user_name'] = name
    session['user_id']   = get_db().execute('SELECT id FROM users WHERE email=?', (email,)).fetchone()['id']
    return redirect(url_for('index'))

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('index'))

@app.route('/upload', methods=['POST'])
def upload():
    if 'user_id' not in session:
        return redirect(url_for('index'))
    f = request.files.get('file')
    if not f or not f.filename:
        return render_template_string(HOME_HTML, user=session.get('user_name'), upload_error='No file selected.')
    key = 'uploads/{}/{}'.format(uuid.uuid4().hex, f.filename)
    try:
        s3_client.put_object(Bucket=UPLOADS_BUCKET, Key=key, Body=f.read())
    except Exception as e:
        r = make_response(render_template_string(RESULT_HTML, processor='ExifTool/12.23',
                          error='S3 upload failed: {}'.format(str(e)), filename=f.filename))
        r.headers['X-Processor'] = 'ExifTool/12.23'
        return r
    try:
        resp = lam_client.invoke(FunctionName=LAMBDA_FUNC, InvocationType='RequestResponse',
                                 Payload=json.dumps({'bucket': UPLOADS_BUCKET, 'key': key}))
        result = json.loads(resp['Payload'].read())
    except Exception as e:
        r = make_response(render_template_string(RESULT_HTML, processor='ExifTool/12.23',
                          error='Pipeline error: {}'.format(str(e)), filename=f.filename))
        r.headers['X-Processor'] = 'ExifTool/12.23'
        return r
    processor    = result.get('processor', 'ExifTool/12.23')
    metadata     = result.get('metadata', '')
    debug_output = result.get('debug_output', '')
    r = make_response(render_template_string(RESULT_HTML, processor=processor,
                      metadata=metadata, debug_output=debug_output, filename=f.filename))
    r.headers['X-Processor'] = processor
    return r

@app.route('/news')
def news():
    return render_template_string(NEWS_HTML)

@app.route('/health')
def health():
    return 'OK'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, threaded=True)
PYEOF

cat > /etc/systemd/system/beaversound.service << 'SVCEOF'
[Unit]
Description=BeaverSound Artist Portal
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/python3 /home/ec2-user/app.py
Restart=always
RestartSec=5
Environment=UPLOADS_BUCKET=${uploads_bucket}
Environment=LAMBDA_FUNCTION=${lambda_function}
Environment=AWS_DEFAULT_REGION=${aws_region}

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable beaversound
systemctl start beaversound
