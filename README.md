# IT Automation & Infrastructure Portfolio

**Luis Ramirez**  
*Systems Administrator | Infrastructure Engineer*  
10+ Years Enterprise IT Experience

---

## 📌 About This Repository

This repository showcases automation scripts and infrastructure-as-code developed throughout my career in enterprise IT operations. The scripts span **Windows Active Directory, macOS/JAMF Pro, cross-platform Python tools, and AWS cloud infrastructure**.

### Timeline & Evolution

These scripts were written between **2018-2024** during my tenure managing heterogeneous enterprise environments (500-2,000+ endpoints). They have been:

- ✅ **Generalized** - Removed company-specific details to make them organization-agnostic
- ✅ **Modernized** - Updated syntax, error handling, and logging for current best practices
- ✅ **Documented** - Added comprehensive comments and usage instructions
- ✅ **AI-Enhanced** - Used AI tools (GitHub Copilot, ChatGPT) to improve code quality, add documentation, and standardize formatting

> **Note on AI Usage:** While the core logic, architecture, and business requirements in these scripts are from real-world implementations I designed and deployed, I've used AI assistance in 2026 to clean up formatting, enhance documentation, and modernize syntax. This reflects my commitment to continuous improvement and leveraging modern tools to deliver quality work.

---

## 🗂️ Repository Structure

```
automation-portfolio/
├── PowerShell/              # Windows & Active Directory automation (29 scripts)
│   ├── ActiveDirectory/     # User lifecycle, HRIS sync, AD health monitoring
|       └── HRIS-Sync/           # Active Directory user lifecycle automation with CSV inputs
│   ├── Security/            # JIT admin access, lockout investigation, certificate monitoring
│   ├── ComputerManagement/  # Capacity forecasting, backup validation, inventory
│   ├── Registry/            # OS upgrade controls, IPv6 management
│   └── README.md
│
├── Bash/                    # macOS & JAMF Pro automation (7 scripts)
│   ├── Security/            # Temporary admin access, FileVault validation
│   ├── System-Configuration/# NTP/timezone, system setup
│   ├── Updates/             # Application update automation (Zoom, Chrome)
│   ├── Utilities/           # Homebrew installation, system utilities
│   └── README.md
│
├── Python/                  # Cross-platform system management (3 scripts)
│   ├── Management/          # Inventory collection, asset management
│   ├── Security/            # User auditing, security baseline validation
│   └── README.md
│
├── Terraform/               # AWS cloud infrastructure (Black Friday e-commerce)
    ├── modules/             # Reusable IaC modules (networking, security, auto-scaling)
    └── README.md

```

---

## 🎯 Key Projects & Achievements

### 1. **HRIS-to-Active Directory Sync** (PowerShell)
**Business Impact:** Automated user lifecycle for 2,000+ employees, reducing manual errors by 95%

- 5-layer safety system prevents accidental deletions of service accounts
- Validates against HR data before AD changes
- Automatic recovery workflow for separated users
- Compliance reporting for audit requirements

**Files:** `PowerShell/ActiveDirectory/Sync-HRIStoActiveDirectory.ps1`

---

### 2. **Zero-Trust JIT Admin Access** (PowerShell)
**Business Impact:** Eliminated standing admin privileges, improved security posture for SOC2 compliance

- Time-limited admin access (max 8 hours, auto-revoke)
- Approval workflow with help desk verification codes
- CloudWatch-style audit logging
- Email notifications to security team

**Files:** `PowerShell/Security/Request-JITAdminAccess.ps1`, `Grant-AdminAccessCode.ps1`, `Revoke-ExpiredAdminAccess.ps1`

---

### 3. **Black Friday E-Commerce Infrastructure** (Terraform)
**Business Impact:** Handled 2M+ transactions in 24 hours, zero downtime, 60% cost savings

- Auto-scaling web tier (4-50 instances based on load)
- Multi-AZ high availability across 3 availability zones
- WAF protection against DDoS attacks (blocked 15,000+ malicious requests)
- CloudFront CDN + ElastiCache for performance

**Files:** `Terraform/` (complete AWS multi-tier architecture)

---

### 4. **macOS Temporary Admin Access** (Bash/JAMF)
**Business Impact:** Self-service admin access for users with help desk 2FA, auto-revoke after 3 minutes

- User requests via Self Service (JAMF Pro)
- Help desk generates verification code
- Admin rights granted only with valid code
- Automatic revocation for security

**Files:** `Bash/Security/request-temp-admin-access.sh`, `grant-admin-access.sh`

---

### 5. **Predictive Capacity Forecasting** (PowerShell)
**Business Impact:** Proactive disk space management, prevented outages via forecasting

- Linear regression analysis of disk usage trends
- Predicts capacity exhaustion 90 days in advance
- Automated alerting when thresholds exceeded
- Historical data visualization

**Files:** `PowerShell/ComputerManagement/Get-DiskCapacityForecast.ps1`

---

## 💻 Technology Stack

| Platform | Languages | Key Technologies |
|----------|-----------|------------------|
| **Windows** | PowerShell 5.1, PowerShell 7+ | Active Directory, Group Policy, SCCM, WMI, Event Logs |
| **macOS** | Bash | JAMF Pro, system_profiler, dscl, defaults, Homebrew |
| **Cross-Platform** | Python 3.7+ | platform module, subprocess, ldap3, requests |
| **Cloud** | Terraform (HCL) | AWS (VPC, EC2, RDS, ALB, CloudFront, WAF, ElastiCache) |
| **Tools** | Git, VS Code, PowerShell ISE | JSON/CSV parsing, REST APIs, SSH/WinRM |

---

## 📈 Skills Demonstrated

### Enterprise Systems Administration
- **Active Directory**: User lifecycle automation, group management, health monitoring, stale object cleanup
- **Security**: Zero-trust access controls, compliance auditing, certificate management, baseline validation
- **Automation**: Scheduled tasks, event-driven workflows, API integration, error handling
- **Monitoring**: CloudWatch-style logging, capacity forecasting, health checks, alerting

### Infrastructure as Code
- **Terraform**: Modular design, remote state, auto-scaling policies, high availability
- **Cloud Architecture**: Multi-tier applications, load balancing, CDN, database replication
- **Security**: WAF configuration, network segmentation, encryption, IAM least-privilege

### Multi-Platform Expertise
- **Windows**: PowerShell DSC, registry management, WMI queries, SCCM integration
- **macOS**: JAMF Pro policies, package deployment, configuration profiles, shell scripting
- **Linux**: System administration, package management, systemd, cron jobs

---

## 🚀 Usage & Deployment

Each technology folder contains a detailed README with:
- Script descriptions and use cases
- Installation/configuration requirements
- Usage examples and parameters
- Best practices and lessons learned

### Getting Started

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/automation-portfolio.git
   cd automation-portfolio
   ```

2. **Navigate to your area of interest**
   ```bash
   cd PowerShell/Security    # For Windows security scripts
   cd Bash/Updates           # For macOS application updates
   cd Python/Management      # For cross-platform inventory
   cd Terraform/             # For AWS infrastructure
   ```

3. **Read the README** in each folder for specific instructions

### ⚠️ Production Use

These scripts are **portfolio examples** demonstrating real-world automation patterns. Before deploying in production:

- ✅ Review and customize for your environment
- ✅ Test thoroughly in a non-production environment
- ✅ Update variables, credentials, and organizational specifics
- ✅ Implement proper error handling and logging for your needs
- ✅ Follow your organization's change management processes

---

## 📊 Script Statistics

| Category | Script Count | Date Range | Lines of Code |
|----------|--------------|------------|---------------|
| PowerShell | 29 scripts | 2018-2024 | ~4,500 LOC |
| Bash | 7 scripts | 2019-2020 | ~1,200 LOC |
| Python | 3 scripts | 2020-2022 | ~1,800 LOC |
| Terraform | 18 files | 2019 | ~2,000 LOC |
| **Total** | **57 files** | **2018-2024** | **~9,500 LOC** |

---

## 🎓 Lessons Learned

Throughout developing these automation solutions, I've learned:

1. **Safety First**: Always implement dry-run modes, exclusion lists, and approval workflows for destructive operations
2. **Logging is Critical**: Comprehensive logging saved hours of troubleshooting and enabled compliance audits
3. **Modular Design**: Reusable functions and modules reduce technical debt and improve maintainability
4. **Error Handling**: Proper try/catch blocks and validation prevent cascading failures
5. **Documentation**: Well-documented code is future-proof code (for yourself and your team)
6. **Testing**: Automated testing and validation catches issues before production deployment
7. **Business Alignment**: Understanding business requirements is as important as technical implementation

---

## 📝 License & Usage

This portfolio is shared for **educational and demonstration purposes**. The scripts represent real-world automation patterns I've implemented in production environments.

**Usage Terms:**
- ✅ Use as reference for your own automation projects
- ✅ Adapt patterns and approaches to your environment
- ✅ Learn from the architecture and design decisions
- ❌ Do not deploy directly to production without thorough testing
- ❌ Do not claim authorship of the original work

---

## 📞 Contact

**Luis Ramirez**  
*Systems Administrator | Infrastructure Engineer*

- **LinkedIn:** [Your LinkedIn Profile]
- **GitHub:** [Your GitHub Profile]
- **Email:** your.email@example.com

---

## 🙏 Acknowledgments

- **AI Tools Used:** GitHub Copilot, ChatGPT (for code cleanup, documentation enhancement, and modernization)
- **Community:** PowerShell Gallery, Terraform Registry, Stack Overflow, Reddit r/sysadmin
- **Inspiration:** Real-world business problems and the amazing IT community

---

*Last Updated: January 2026*  
*Portfolio represents work completed between 2018-2024, updated and documented in 2026*
