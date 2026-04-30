# ── JSN Incident Report Generator (webapp) ───────────────────────────────────
# Sole external entry point. No IAM Instance Profile. Exposed externally via EIP.
# [Intentional Vulnerability] Server-Side Template Injection (SSTI) — Summary field

resource "aws_instance" "webapp" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.security.id
  vpc_security_group_ids      = [aws_security_group.webapp.id]
  user_data_replace_on_change = true
  # no key_name — SSH not needed, SSM also absent (intentional design: no instance profile attached)
  # no iam_instance_profile — intentional design

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -e

    dnf update -y
    dnf install -y python3 python3-pip

    pip3 install flask

    useradd -m -s /bin/bash webapp
    mkdir -p /opt/jsn-report

    cat > /opt/jsn-report/app.py << 'PYEOF'
    from flask import Flask, request, render_template_string

    app = Flask(__name__)

    HTML = """<!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <title>JSN Incident Report Generator</title>
      <style>
        body{font-family:monospace;background:#0d1117;color:#c9d1d9;margin:0;padding:2rem}
        h2{color:#58a6ff}
        input[type=text]{background:#161b22;border:1px solid #30363d;color:#c9d1d9;
                         padding:.5rem;border-radius:4px;width:320px;font-family:monospace}
        textarea{background:#161b22;border:1px solid #30363d;color:#c9d1d9;
                 padding:.5rem;border-radius:4px;width:320px;font-family:monospace;height:80px}
        button{margin-top:.5rem;padding:.5rem 1rem;background:#238636;color:white;
               border:none;border-radius:4px;cursor:pointer;display:block}
        .result{background:#161b22;border:1px solid #30363d;border-radius:4px;
                padding:1rem;margin-top:1rem;white-space:pre-wrap;font-size:.85rem;min-height:40px}
        label{display:block;color:#8b949e;font-size:.85rem;margin-bottom:.3rem;margin-top:.8rem}
      </style>
    </head>
    <body>
      <h2>JSN Incident Report Generator</h2>
      <p style="color:#8b949e;font-size:.85rem">Generates internal incident reports for sharing during outages.</p>
      <form method="post">
        <label>Service Name</label>
        <input type="text" name="service" placeholder="e.g. jsn-payment-api">
        <label>Incident Time</label>
        <input type="text" name="incident_time" placeholder="e.g. 2026-04-30 14:23">
        <label>Owner</label>
        <input type="text" name="owner" placeholder="e.g. kim.devops">
        <label>Summary</label>
        <textarea name="summary" placeholder="Describe the incident"></textarea>
        <button type="submit">Generate Report</button>
      </form>
      {% if result %}<div class="result">{{ result }}</div>{% endif %}
    </body>
    </html>"""

    @app.route('/', methods=['GET', 'POST'])
    def index():
        result = ''
        if request.method == 'POST':
            service       = request.form.get('service', '')
            incident_time = request.form.get('incident_time', '')
            owner         = request.form.get('owner', '')
            summary       = request.form.get('summary', '')

            # ──────────────────────────────────────────────────────────
            # [Intentional Vulnerability] Server-Side Template Injection
            # The Summary input is concatenated directly into the template source before calling render_template_string()
            # All other fields are safely handled as Jinja2 variables
            # ──────────────────────────────────────────────────────────
            report_template = (
                "[JSN Incident Report]\n"
                "Service  : {{ service }}\n"
                "Time     : {{ incident_time }}\n"
                "Owner    : {{ owner }}\n"
                "Summary  : " + summary
            )
            result = render_template_string(
                report_template,
                service=service,
                incident_time=incident_time,
                owner=owner,
            )
        return render_template_string(HTML, result=result)

    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=80)
    PYEOF

    chown -R webapp:webapp /opt/jsn-report

    tee /etc/systemd/system/jsn-report.service > /dev/null << 'SERVICE'
    [Unit]
    Description=JSN Incident Report Generator
    After=network.target

    [Service]
    Type=simple
    User=webapp
    WorkingDirectory=/opt/jsn-report
    AmbientCapabilities=CAP_NET_BIND_SERVICE
    CapabilityBoundingSet=CAP_NET_BIND_SERVICE
    ExecStart=/usr/bin/python3 /opt/jsn-report/app.py
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable jsn-report
    systemctl start jsn-report
  USERDATA
  )

  tags = {
    Name     = "${var.project_name}-webapp"
    Scenario = "${var.project_name}-watchdog-trap"
  }
}

# EIP — webapp is the only instance exposed externally
resource "aws_eip" "webapp" {
  instance = aws_instance.webapp.id
  domain   = "vpc"

  tags = { Name = "${var.project_name}-webapp-eip" }
}

# ── Prowler Dashboard ──────────────────────────────────────────────────────────
# Internal network only — no public IP. Port 9090 accessible from webapp-sg only via dashboard-sg.
# No authentication — trust-based internal network design
# Role: provides the KMS FAIL clue → confirms the log group target for Steampipe queries

resource "aws_instance" "prowler" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.tools.id # NAT route — package installation possible without a public IP
  vpc_security_group_ids      = [aws_security_group.dashboard.id]
  iam_instance_profile        = aws_iam_instance_profile.prowler_ec2.name
  user_data_replace_on_change = true

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -u

    dnf update -y || true
    dnf install -y python3 python3-pip nginx git || true
    mkdir -p /var/prowler/output

    # Scenario stability: the clue page is served first, regardless of Prowler installation or scan status.
    cat > /var/prowler/output/prowler-output.html << 'HTMLEOF'
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>Prowler Security Report - JSN AWS Environment</title>
      <style>
        body{font-family:monospace;background:#111827;color:#d1d5db;padding:2rem}
        h1{color:#60a5fa}
        .summary,.finding{border:1px solid #374151;background:#1f2937;padding:1rem;margin:1rem 0}
        .fail{color:#f87171;font-weight:bold}
        code{color:#facc15}
      </style>
    </head>
    <body>
      <h1>Prowler Security Report - JSN AWS Environment</h1>
      <div class="summary">SUMMARY: PASS 142 / FAIL 7 / WARNING 3</div>
      <div class="finding">
        <div class="fail">[MEDIUM] cloudwatch_log_group_kms_encryption_enabled</div>
        <p>Resource: <code>arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/corp/deploy-pipeline</code></p>
        <p>CloudWatch Log Group does not use a customer managed KMS key.</p>
      </div>
    </body>
    </html>
    HTMLEOF

    # Nginx configuration (no authentication)
    cat > /etc/nginx/conf.d/prowler.conf << 'NGINXEOF'
    server {
        listen 9090;
        server_name _;
        root /var/prowler/output;
        index prowler-output.html;
        location / {
            try_files $uri $uri/ =404;
            autoindex on;
        }
    }
    NGINXEOF

    rm -f /etc/nginx/conf.d/default.conf

    systemctl enable nginx
    systemctl restart nginx

    # The actual Prowler scan runs on a best-effort basis. The clue page remains available even if the scan fails.
    pip3 install prowler || true
    mkdir -p /var/prowler/scan
    if command -v prowler >/dev/null 2>&1; then
      prowler aws \
        --services cloudwatch logs iam \
        --output-formats html json \
        --output-directory /var/prowler/scan \
        --region ${var.aws_region} \
        --ignore-exit-code-3 || true
    fi
  USERDATA
  )

  tags = {
    Name     = "${var.project_name}-prowler-dashboard"
    Scenario = "${var.project_name}-watchdog-trap"
  }
}

# ── Steampipe Query Console ────────────────────────────────────────────────────
# Internal network only — no public IP. Port 9194 accessible from webapp-sg only via dashboard-sg.
# No authentication — trust-based internal network design
# Role: queries /corp/deploy-pipeline logs → discovers IAM Git credentials

resource "aws_instance" "steampipe" {
  ami                    = data.aws_ami.ubuntu2204.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.tools.id # NAT route — package installation possible without a public IP
  vpc_security_group_ids = [aws_security_group.dashboard.id]
  iam_instance_profile   = aws_iam_instance_profile.steampipe_ec2.name

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -e

    apt-get update -y
    apt-get install -y curl python3 python3-pip

    # Install Steampipe
    /bin/sh -c "$(curl -fsSL https://steampipe.io/install/steampipe.sh)"

    # Install AWS plugin (as the ubuntu user)
    sudo -u ubuntu /usr/local/bin/steampipe plugin install aws

    # Configure AWS plugin (auto-authenticated via Instance Profile)
    sudo -u ubuntu mkdir -p /home/ubuntu/.steampipe/config
    sudo -u ubuntu tee /home/ubuntu/.steampipe/config/aws.spc > /dev/null << 'AWSCONF'
    connection "aws" {
      plugin  = "aws"
      regions = ["${var.aws_region}"]
    }
    AWSCONF

    # Install Flask web app
    pip3 install flask psycopg2-binary

    mkdir -p /opt/jsn-query
    cat > /opt/jsn-query/app.py << 'PYEOF'
    import re
    from flask import Flask, request, jsonify, render_template_string
    import psycopg2

    app = Flask(__name__)

    STEAMPIPE_CONN = {
        "host": "127.0.0.1",
        "port": 9193,
        "dbname": "steampipe",
        "user": "steampipe",
        "connect_timeout": 10,
        "options": "-c statement_timeout=10000"
    }

    CONSOLE_HTML = """<!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <title>JSN Security Analysis</title>
      <style>
        body{font-family:monospace;background:#1e1e1e;color:#d4d4d4;padding:2rem}
        h2{color:#569cd6}
        textarea{width:100%;height:120px;background:#252526;color:#d4d4d4;
                 border:1px solid #3c3c3c;padding:.5rem;font-family:monospace;font-size:14px}
        button{margin-top:.5rem;padding:.5rem 1.5rem;background:#0e639c;color:white;
               border:none;cursor:pointer;font-size:14px}
        #error{color:#f44747;margin-top:1rem}
        table{border-collapse:collapse;margin-top:1rem;width:100%}
        th{background:#37373d;padding:6px 12px;border:1px solid #3c3c3c;text-align:left}
        td{padding:6px 12px;border:1px solid #3c3c3c}
        tr:nth-child(even){background:#252526}
      </style>
    </head>
    <body>
      <h2>JSN Security Analysis - SQL Query Console</h2>
      <textarea id="sql" placeholder="-- Enter SQL here
    select * from aws_cloudwatch_log_group limit 10;"></textarea><br>
      <button onclick="runQuery()">Run Query &#9654;</button>
      <div id="error"></div>
      <div id="results"></div>
      <script>
        async function runQuery() {
          const sql = document.getElementById('sql').value;
          document.getElementById('error').innerText = '';
          document.getElementById('results').innerHTML = '';
          const resp = await fetch('/query', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({sql})
          });
          const data = await resp.json();
          if (data.error) { document.getElementById('error').innerText = data.error; return; }
          if (!data.rows.length) { document.getElementById('results').innerText = '(No results)'; return; }
          let html = '<table><tr>' + data.columns.map(c => '<th>'+c+'</th>').join('') + '</tr>';
          data.rows.forEach(r => { html += '<tr>' + r.map(v => '<td>'+(v??'')+'</td>').join('') + '</tr>'; });
          document.getElementById('results').innerHTML = html + '</table>';
        }
      </script>
    </body>
    </html>"""

    @app.route('/')
    def console():
        return render_template_string(CONSOLE_HTML)

    @app.route('/query', methods=['POST'])
    def query():
        sql = request.json.get('sql', '').strip()
        if not re.match(r'^\s*select\b', sql, re.IGNORECASE):
            return jsonify({'error': 'Only SELECT statements are allowed.'}), 400
        if sql.rstrip(';').count(';') > 0:
            return jsonify({'error': 'Only one query can be executed at a time.'}), 400
        try:
            conn = psycopg2.connect(**STEAMPIPE_CONN)
            cur = conn.cursor()
            cur.execute(sql)
            columns = [desc[0] for desc in cur.description]
            rows = [list(row) for row in cur.fetchall()]
            cur.close()
            conn.close()
            return jsonify({'columns': columns, 'rows': rows})
        except Exception as e:
            return jsonify({'error': str(e)}), 500

    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=9194)
    PYEOF

    chown -R ubuntu:ubuntu /opt/jsn-query

    # Steampipe service (systemd unit)
    tee /etc/systemd/system/steampipe-service.service > /dev/null << 'SERVICE'
    [Unit]
    Description=Steampipe Service (PostgreSQL endpoint)
    After=network.target

    [Service]
    Type=simple
    User=ubuntu
    ExecStart=/usr/local/bin/steampipe service start --foreground
    Restart=on-failure
    RestartSec=10

    [Install]
    WantedBy=multi-user.target
    SERVICE

    # Flask web app (systemd unit)
    tee /etc/systemd/system/jsn-query-web.service > /dev/null << 'SERVICE'
    [Unit]
    Description=JSN SQL Query Web App
    After=network.target steampipe-service.service

    [Service]
    Type=simple
    User=ubuntu
    WorkingDirectory=/opt/jsn-query
    ExecStart=/usr/bin/python3 /opt/jsn-query/app.py
    Restart=on-failure
    RestartSec=10

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable steampipe-service jsn-query-web
    systemctl start steampipe-service
    # Flask starts after the steampipe service is up
    sleep 15
    systemctl start jsn-query-web
  USERDATA
  )

  tags = {
    Name     = "${var.project_name}-steampipe-dashboard"
    Scenario = "${var.project_name}-watchdog-trap"
  }
}
