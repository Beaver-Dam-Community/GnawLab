resource "random_string" "scenario_id" {
  length  = 8
  special = false
  upper   = false
}

locals {
  scenario_id   = random_string.scenario_id.result
  scenario_name = "gnawlab-golden"

  # Resource naming
  vpc_name              = "${local.scenario_name}-vpc-${local.scenario_id}"
  alb_name              = "${local.scenario_name}-alb-${local.scenario_id}"
  asg_name              = "${local.scenario_name}-asg-${local.scenario_id}"
  launch_template_name  = "${local.scenario_name}-lt-${local.scenario_id}"
  attacker_user_name    = "${local.scenario_name}-attacker-${local.scenario_id}"
  attacker_policy_name  = "${local.scenario_name}-attacker-policy-${local.scenario_id}"
  instance_role_name    = "${local.scenario_name}-instance-role-${local.scenario_id}"
  instance_profile_name = "${local.scenario_name}-instance-profile-${local.scenario_id}"
  lambda_role_name      = "${local.scenario_name}-updater-role-${local.scenario_id}"
  lambda_name           = "${local.scenario_name}-updater-${local.scenario_id}"
  eventbridge_rule      = "${local.scenario_name}-updater-schedule-${local.scenario_id}"
  secret_name           = "${local.scenario_name}-flag-${local.scenario_id}"

  # AMI naming — used by both the baked golden AMI and the vulnerable Lambda's name filter.
  # The scenario_id is the cross-pollution guard: each deployment gets a unique prefix so
  # malicious AMIs uploaded by one participant cannot be picked up by another participant's Lambda.
  ami_name_prefix = "${local.scenario_name}-ticketing-${local.scenario_id}-"
  golden_ami_name = "${local.ami_name_prefix}${formatdate("YYYYMMDD", timestamp())}"

  # SSM parameter that the Launch Template's resolve:ssm: reference points at
  ssm_parameter_name = "/gnawlab/golden/${local.scenario_id}/golden-ami/web"

  # IP whitelist: use provided or auto-detected
  whitelist_cidr = var.whitelist_ip != "" ? var.whitelist_ip : "${chomp(data.http.my_ip.response_body)}/32"

  # Common tags
  common_tags = {
    Scenario    = "golden-drift"
    Project     = "GnawLab"
    Environment = "training"
    ManagedBy   = "terraform"
    ScenarioID  = local.scenario_id
  }

  # user_data for baking the legitimate ("golden") AMI.
  # Installs a normal Flask ticketing app — no intentional CPU-heavy code.
  # Scale-out is driven by external HTTP load, not by the app's own logic.
  golden_ami_user_data = <<-BASH
#!/bin/bash
set -eux

dnf update -y
dnf install -y python3 python3-pip

# Application code
mkdir -p /opt/ticketing
cat > /opt/ticketing/app.py <<'PYAPP'
from flask import Flask, jsonify, request

app = Flask(__name__)

EVENTS = [
    {
        "id": 1,
        "name": "BeaverCon 2026",
        "date": "June 18",
        "venue": "Riverfront Hall",
        "price": 49,
        "seats": 128,
        "status": "On sale",
    },
    {
        "id": 2,
        "name": "Cloud Security Summit",
        "date": "July 9",
        "venue": "North Pier Center",
        "price": 79,
        "seats": 42,
        "status": "Limited",
    },
    {
        "id": 3,
        "name": "WhoAMI Workshop",
        "date": "August 2",
        "venue": "Training Studio B",
        "price": 29,
        "seats": 64,
        "status": "New",
    },
]

@app.route('/')
def home():
    event_cards = ""
    for event in EVENTS:
        event_cards += f"""
        <article class="event-card">
          <div class="event-topline">
            <span class="event-date">{event['date']}</span>
            <span class="badge">{event['status']}</span>
          </div>
          <h3>{event['name']}</h3>
          <p class="venue">{event['venue']}</p>
          <div class="event-meta">
            <span>$${event['price']}</span>
            <span>{event['seats']} seats left</span>
          </div>
          <button type="button">Reserve</button>
        </article>
        """

    return f"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>BeaverDam Ticketing</title>
  <style>
    :root {{
      color-scheme: light;
      --ink: #172033;
      --muted: #5b6578;
      --line: #d8dee8;
      --panel: #ffffff;
      --page: #f4f6f9;
      --brand: #185adb;
      --brand-dark: #0f3f9d;
      --accent: #0b8f77;
    }}

    * {{
      box-sizing: border-box;
    }}

    body {{
      margin: 0;
      font-family: Arial, Helvetica, sans-serif;
      color: var(--ink);
      background: var(--page);
    }}

    header {{
      background: #ffffff;
      border-bottom: 1px solid var(--line);
    }}

    .nav {{
      width: min(1120px, calc(100% - 32px));
      min-height: 68px;
      margin: 0 auto;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 20px;
    }}

    .brand {{
      font-size: 20px;
      font-weight: 800;
      letter-spacing: 0;
    }}

    .status {{
      display: flex;
      align-items: center;
      gap: 8px;
      color: var(--muted);
      font-size: 14px;
    }}

    .status-dot {{
      width: 9px;
      height: 9px;
      border-radius: 50%;
      background: var(--accent);
    }}

    main {{
      width: min(1120px, calc(100% - 32px));
      margin: 0 auto;
      padding: 42px 0;
    }}

    .hero {{
      display: grid;
      grid-template-columns: minmax(0, 1.2fr) minmax(280px, 0.8fr);
      gap: 28px;
      align-items: stretch;
      margin-bottom: 28px;
    }}

    .hero-copy {{
      padding: 36px;
      background: #10213f;
      color: #ffffff;
      border-radius: 8px;
    }}

    .eyebrow {{
      margin: 0 0 12px;
      color: #9fc5ff;
      font-size: 13px;
      font-weight: 700;
      text-transform: uppercase;
    }}

    h1 {{
      max-width: 720px;
      margin: 0;
      font-size: 44px;
      line-height: 1.05;
      letter-spacing: 0;
    }}

    .hero-copy p {{
      max-width: 620px;
      margin: 18px 0 0;
      color: #d9e5f6;
      font-size: 17px;
      line-height: 1.6;
    }}

    .hero-panel {{
      display: grid;
      gap: 14px;
      padding: 24px;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
    }}

    .metric {{
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 12px;
      padding-bottom: 14px;
      border-bottom: 1px solid var(--line);
    }}

    .metric:last-child {{
      padding-bottom: 0;
      border-bottom: 0;
    }}

    .metric strong {{
      font-size: 24px;
    }}

    .metric span {{
      color: var(--muted);
      font-size: 14px;
    }}

    .section-title {{
      display: flex;
      align-items: end;
      justify-content: space-between;
      gap: 18px;
      margin: 0 0 16px;
    }}

    h2 {{
      margin: 0;
      font-size: 24px;
      letter-spacing: 0;
    }}

    .section-title p {{
      margin: 0;
      color: var(--muted);
      font-size: 14px;
    }}

    .events {{
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 18px;
    }}

    .event-card {{
      min-height: 260px;
      display: flex;
      flex-direction: column;
      padding: 22px;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: 0 10px 28px rgba(20, 31, 52, 0.08);
    }}

    .event-topline,
    .event-meta {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }}

    .event-date {{
      color: var(--brand-dark);
      font-size: 14px;
      font-weight: 800;
    }}

    .badge {{
      padding: 5px 9px;
      border-radius: 999px;
      background: #e8f3ff;
      color: var(--brand-dark);
      font-size: 12px;
      font-weight: 700;
    }}

    h3 {{
      margin: 24px 0 8px;
      font-size: 22px;
      line-height: 1.2;
      letter-spacing: 0;
    }}

    .venue {{
      margin: 0;
      color: var(--muted);
      line-height: 1.5;
    }}

    .event-meta {{
      margin-top: auto;
      padding-top: 22px;
      color: var(--ink);
      font-weight: 700;
    }}

    .event-meta span:last-child {{
      color: var(--muted);
      font-size: 14px;
      font-weight: 600;
    }}

    button {{
      width: 100%;
      min-height: 42px;
      margin-top: 18px;
      border: 0;
      border-radius: 6px;
      background: var(--brand);
      color: #ffffff;
      font-size: 15px;
      font-weight: 800;
      cursor: pointer;
    }}

    button:hover {{
      background: var(--brand-dark);
    }}

    footer {{
      margin-top: 32px;
      padding-top: 20px;
      border-top: 1px solid var(--line);
      color: var(--muted);
      font-size: 13px;
    }}

    @media (max-width: 780px) {{
      .nav {{
        align-items: flex-start;
        flex-direction: column;
        padding: 16px 0;
      }}

      main {{
        padding-top: 24px;
      }}

      .hero,
      .events {{
        grid-template-columns: 1fr;
      }}

      .hero-copy {{
        padding: 28px;
      }}

      h1 {{
        font-size: 34px;
      }}

      .section-title {{
        align-items: flex-start;
        flex-direction: column;
      }}
    }}
  </style>
</head>
<body>
  <header>
    <div class="nav">
      <div class="brand">BeaverDam Ticketing</div>
      <div class="status"><span class="status-dot"></span> All ticketing systems operational</div>
    </div>
  </header>

  <main>
    <section class="hero">
      <div class="hero-copy">
        <p class="eyebrow">Official event reservations</p>
        <h1>Live events, secure reservations, instant confirmation.</h1>
        <p>Browse upcoming BeaverDam events and reserve your seat through the production ticketing platform.</p>
      </div>
      <aside class="hero-panel" aria-label="Ticketing summary">
        <div class="metric"><span>Upcoming events</span><strong>3</strong></div>
        <div class="metric"><span>Available seats</span><strong>234</strong></div>
        <div class="metric"><span>Average confirmation</span><strong>2s</strong></div>
      </aside>
    </section>

    <section>
      <div class="section-title">
        <h2>Featured Events</h2>
        <p>Simple reservations for training, conferences, and internal programs.</p>
      </div>
      <div class="events">
        {event_cards}
      </div>
    </section>

    <footer>
      BeaverDam Ticketing processes reservations through the active web tier.
    </footer>
  </main>
</body>
</html>
"""

@app.route('/events')
def events():
    return jsonify(EVENTS)

@app.route('/book', methods=['POST'])
def book():
    event_id = request.form.get('event_id', '1')
    selected = next((event for event in EVENTS if str(event["id"]) == str(event_id)), EVENTS[0])
    return jsonify({
        "booking_id": f"BK-{selected['id']}-XYZ",
        "event": selected["name"],
        "status": "confirmed",
    })

@app.route('/health')
def health():
    return "OK", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
PYAPP

pip3 install flask

# systemd service for the ticketing app
cat > /etc/systemd/system/ticketing.service <<'UNIT'
[Unit]
Description=BeaverDam Ticketing
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/ticketing/app.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable ticketing.service
systemctl start ticketing.service
BASH

  # Vulnerable Lambda source code.
  # The bug: describe_images is called without an `Owners` filter,
  # so any public AMI matching the name prefix is returned alongside
  # the legitimate one. The Lambda then picks "most recent" and writes
  # the result to SSM, which the Launch Template resolves at ASG launch.
  #
  # Fix would be a single line:  Owners = [account_id_str]
  golden_updater_lambda_code = <<-PYTHON
import boto3
import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')
ssm = boto3.client('ssm')

AMI_NAME_PREFIX    = os.environ['AMI_NAME_PREFIX']
SSM_PARAMETER_NAME = os.environ['SSM_PARAMETER_NAME']


def lambda_handler(event, context):
    # VULNERABLE: no `Owners` filter. Any public AMI whose name matches the
    # configured prefix will be returned, including AMIs registered by an
    # attacker in a different AWS account.
    resp = ec2.describe_images(
        Filters=[
            {'Name': 'name',  'Values': [f'{AMI_NAME_PREFIX}*']},
            {'Name': 'state', 'Values': ['available']},
        ]
    )

    images = resp.get('Images', [])
    if not images:
        logger.info('No matching images found.')
        return {'status': 'no_images'}

    # Pick the image with the latest CreationDate
    latest = sorted(images, key=lambda x: x['CreationDate'])[-1]

    logger.info(
        f"Selected image: id={latest['ImageId']} "
        f"name={latest['Name']} "
        f"created={latest['CreationDate']}"
    )

    ssm.put_parameter(
        Name=SSM_PARAMETER_NAME,
        Value=latest['ImageId'],
        Type='String',
        DataType='aws:ec2:image',
        Overwrite=True,
    )

    return {
        'status': 'updated',
        'image_id': latest['ImageId'],
        'image_name': latest['Name'],
    }
PYTHON
}
