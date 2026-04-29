### Scenario Name: supply_chain_eic_pivot

---

|  **Size** | Medium |
| --- | --- |
| **Difficulty** | Hard |
| **Command** | scenario create supply_chain_eic_pivot |

### Overview

---

This scenario is a realistic AWS wargame designed to simulate CI/CD pipeline exploitation and internal network pivoting. While many organizations adopt automation tools like GitLab and Atlantis to accelerate deployment, they often suffer from governance failures by granting excessive IAM permissions to pipeline compute resources. 

Players will start with a compromised developer account, escalate their privileges by poisoning the pipeline, and eventually penetrate deep into a production environment that is isolated from the external internet.

### Scenario Resources

---

- **Application & VCS**
    - 1 GitLab Account (000_ops)
    - 1 Repository (infra-repo)
    - 1 CI/CD Tool (Atlantis)
    - 1 Configs file (atlantis.yaml)
- **Network & Routing**
    - 1 VPC (Public / Private Subnets, Security Groups)
- **Compute (EC2)**
    - 1 GitLab Server (Public)
    - 1 Atlantis Runner
    - 1 Bastion Host (Public)
    - 1 Target Server (Private)
- **Identity & Access Management (IAM)**
    - 4 IAM Roles
    - 1 IAM Instance Profile

### Scenario Start

---

- **Start Identity:** GitLab Developer Account
- **Provided Credentials:** `gitlab_credentials.txt` (Contains GitLab URL, ID, and Password)

### Scenario Goal

---

- Gain access to the Target Server in the private subnet and retrieve the flag located in `flag.txt`.

### Summary

---

BeaverCorp operates its own GitLab-based CI/CD pipeline for rapid infrastructure deployment. Their critical production servers are hosted within a private network, completely isolated from the public internet.

You have acquired a standard developer account of BeaverCorp through an underground forum. This account has limited access to certain GitLab repositories but does not possess any direct AWS credentials.

Your mission is to leverage this limited access to compromise the pipeline, pivot through the infrastructure, and ultimately capture the flag inside the isolated target server.

---

*Note: If you are truly stuck, a hint or solution can be found in the `CHEAT_SHEET.md` file (strictly for educational purposes).*
