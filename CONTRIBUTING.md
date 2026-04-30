# Contributing to GnawLab

Thank you for your interest in contributing to GnawLab!

## How to Contribute

- **Report bugs / Request features**: Open an issue
- **Add new scenarios**: Submit a Pull Request

## Adding a New Scenario

### 1. Use Templates

Copy templates from `scenarios/_templates/`:

```bash
cp scenarios/_templates/README.template.md scenarios/aws/01-beginner/access-key/single-hop/your-scenario/README.md
cp scenarios/_templates/walkthrough.template.md scenarios/aws/01-beginner/access-key/single-hop/your-scenario/walkthrough.md
cp scenarios/_templates/setup.template.md scenarios/aws/01-beginner/access-key/single-hop/your-scenario/setup.md
cp scenarios/_templates/cleanup.template.md scenarios/aws/01-beginner/access-key/single-hop/your-scenario/cleanup.md
```

### 2. Follow Directory Structure

```
your-scenario/
├── README.md
├── walkthrough.md
├── manifest.yaml
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── provider.tf
```

### 3. Test Your Scenario

```bash
cd your-scenario/terraform
terraform init
terraform plan
terraform apply
# verify scenario works
terraform destroy
```

## Scenario Guidelines

- All content must be in **English**
- Difficulty levels: `Easy`, `Medium`, `Hard`, `Expert`
- Include real-world reference with source
- `Learning Objectives` section: only for `01-beginner` category

## Walkthrough Writing Guidelines

Walkthroughs must follow the **real attacker workflow**. Include every command an attacker would actually execute, not just the exploit commands.

### Required Steps (Access Key Based Scenarios)

1. **Identity Confirmation** - Verify who you are with the compromised credentials
2. **Permission Enumeration** - Enumerate ALL permissions (user inline, user attached, group membership, group inline, group attached policies)
3. **Exploit** - Execute the attack based on discovered permissions
4. **Capture the Flag** - Verify goal achieved and retrieve the flag

### Why This Matters

- Learners should understand the **complete attack chain**, not just the final exploit
- Real attackers always enumerate permissions before acting
- Skipping enumeration steps creates unrealistic expectations

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Add/modify scenario
4. Test locally with `terraform apply/destroy`
5. Submit PR with description

## Questions?

Open an issue if you have any questions.
