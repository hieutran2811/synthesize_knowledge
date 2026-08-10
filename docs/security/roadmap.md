---
title: "Roadmap Tổng Hợp Kiến Thức Bảo Mật & Tấn Công"
topic: security
level: mixed
review_status: needs_review
content_updated: 2026-08-03
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Roadmap Tổng Hợp Kiến Thức Bảo Mật & Tấn Công

> Thuật ngữ: [Glossary](glossary.md).

**Trạng thái chuẩn hóa (2026-08-04): đã hoàn thành các mục 1–58.1.**

## Cấu trúc thư mục
```
security/
├── roadmap.md                          ← file này
├── security_knowledge.md              ← overview tổng quan (50 topics)
├── network/                            ← Network Security deep dive
│   ├── network_attacks.md             ← ARP/DNS spoofing, Wireshark, MITM lab
│   └── network_defense.md            ← Firewall rules, IDS/IPS, network hardening
├── web/                                ← Web Security deep dive
│   ├── owasp_top10.md                 ← OWASP Top 10 chi tiết từng loại
│   ├── web_testing.md                 ← Burp Suite, manual testing methodology
│   └── api_security.md               ← REST API, GraphQL, JWT, OAuth 2.0 attacks
├── crypto/                             ← Cryptography deep dive
│   ├── crypto_fundamentals.md        ← Symmetric, Asymmetric, Hashing, TLS
│   └── pki_tls.md                    ← PKI, Certificate Authority, TLS handshake
├── secrets/                            ← Secrets & Key Management
│   └── secrets_key_management.md     ← lifecycle, KMS/HSM, envelope encryption, rotation
├── architecture/                       ← Secure Architecture
│   ├── threat_modeling_secure_architecture.md ← DFD, STRIDE, risk, requirements, verification
│   ├── enterprise_security_architecture_zero_trust.md ← capabilities, PDP/PEP, trust zones, roadmap
│   └── security_architecture_review_design_governance.md ← review tiers, ADR, patterns, fitness functions
├── resilience/                         ← Business Continuity, DR & Cyber Resilience
│   └── business_continuity_disaster_recovery_cyber_resilience.md ← BIA, RTO/RPO, clean recovery, exercise
├── third_party/                        ← Third-Party & SaaS Security Assurance
│   └── third_party_saas_security_assurance.md ← due diligence, shared responsibility, assurance, exit
├── metrics/                            ← Security Measurement & Reporting
│   └── security_metrics_measurement_executive_reporting.md ← semantics, quality, uncertainty, aggregation, reporting
├── program/                            ← Security Program Operating Model
│   ├── security_program_operating_model_capability_management.md ← capabilities, services, capacity, workforce, portfolio
│   ├── security_strategy_investment_portfolio_prioritization.md ← strategy, business case, investment, sequencing, benefits
│   ├── security_culture_human_risk_behavior_engineering.md ← culture, behavior, learning, phishing, human-centered controls
│   ├── security_transformation_change_management.md ← transition state, adoption, migration waves, cutover, retirement
│   ├── insider_risk_trusted_workforce_operations.md ← prevention, privacy, signals, investigation, response, trusted workforce
│   ├── security_policy_standards_exception_lifecycle_engineering.md ← hierarchy, requirements, enforcement, exception, retirement
│   ├── security_compliance_engineering_continuous_control_assurance.md ← obligations, assessment, evidence, findings, audit readiness
│   ├── security_control_library_common_control_inheritance.md ← control semantics, providers, inheritance, dependencies, assurance
│   ├── regulatory_change_obligation_management.md ← horizon scanning, interpretation, applicability, impact, implementation
│   ├── security_authorization_ongoing_risk_decision_engineering.md ← boundary, decision package, conditions, monitoring, reauthorization
│   ├── security_governance_forums_committees_decision_records.md ← mandate, routing, quorum, dissent, escalation, decision traceability
│   ├── security_risk_quantification_scenario_analysis_decision_uncertainty.md ← scenarios, ranges, calibration, sensitivity, decisions
│   ├── cybersecurity_mergers_acquisitions_divestitures_engineering.md ← diligence, Day 1, integration, carve-out, TSA, separation
│   ├── security_risk_transfer_cyber_insurance_contractual_allocation.md ← coverage, retention, exclusions, contracts, claims
│   ├── cybersecurity_economics_business_cases_control_value_realization.md ← marginal value, cost, causality, evaluation, learning
│   ├── security_service_management_catalogs_internal_customer_experience.md ← catalog, request flow, SLO, support, experience, lifecycle
│   ├── security_product_management_platform_adoption_economics.md ← discovery, product fit, adoption funnel, experiments, economics
│   ├── security_knowledge_management_standards_enablement_decision_support.md ← authority, findability, decision aids, lifecycle, reuse
│   ├── security_developer_relations_champions_community_enablement.md ← DevRel, champions, community, contributions, feedback
│   ├── security_engineering_enablement_secure_delivery_coaching.md ← coaching, pairing, clinics, capability transfer, independence
│   ├── security_research_innovation_emerging_technology_governance.md ← horizon, research, readiness, sandbox, evidence gates, transition
│   ├── security_capability_academies_mentoring_technical_career_development.md ← competency, practice, mentoring, assessment, career pathways
│   └── security_talent_acquisition_workforce_analytics_succession_resilience.md ← hiring, analytics, mobility, coverage, succession
├── data/                               ← Data Security & Privacy Engineering
│   └── data_security_privacy_engineering.md ← classification, lineage, retention, privacy controls
├── supply_chain/                       ← Software Supply Chain Security
│   └── software_supply_chain_security.md ← dependencies, SBOM, SLSA, signing, provenance
├── runtime/                            ← Container & Kubernetes Runtime Security
│   └── container_kubernetes_runtime_security.md ← pod, kernel, network, node, detection, response
├── detection/                          ← Cloud-Native Detection & Incident Response
│   └── cloud_native_detection_incident_response.md ← audit, correlation, triage, forensics, containment
├── platform/                           ← Platform Engineering Security
│   └── platform_engineering_security.md ← golden path, self-service, GitOps, policy, fleet governance
├── validation/                         ← Security Testing & Validation Engineering
│   └── security_testing_validation_engineering.md ← requirements, regression, emulation, control evidence
├── vulnerability/                      ← Vulnerability Management & Exposure Prioritization
│   └── vulnerability_management_exposure_prioritization.md ← CVSS, EPSS, KEV, attack path, remediation
├── governance/                         ← Security Governance & Risk Engineering
│   └── security_governance_risk_engineering.md ← risk scenario, controls, assurance, acceptance, ERM
├── identity/                           ← Identity & Access Management
│   └── iam_authentication_authorization.md ← password/passkey, OAuth/OIDC, session, AuthZ
├── active_directory/                   ← Active Directory Security
│   └── ad_attacks.md                 ← Kerberoasting, Pass-the-Hash, BloodHound
├── cloud/                              ← Cloud Security deep dive
│   ├── aws_security.md               ← IAM, S3, EC2, Lambda security
│   ├── cloud_misconfig.md            ← Common misconfigurations, tools
│   └── cloud_iam_governance_at_scale.md ← hierarchy, federation, JIT, effective access
├── malware/                            ← Malware & Forensics
│   ├── malware_analysis.md           ← Static/Dynamic analysis, sandbox
│   └── incident_response.md         ← IR playbook, forensics, DFIR
├── devsecops/                          ← DevSecOps
│   └── devsecops_pipeline.md        ← SAST, DAST, SCA, secret scanning
└── ctf/                                ← CTF Techniques
    └── ctf_techniques.md             ← CTF categories, common patterns, tools
```

---

## Mục lục đã hoàn thành ✅

### Tổng quan (Overview)
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Security Fundamentals – CIA Triad, STRIDE, Threat Modeling, Hacker Taxonomy, Pentest Phases | security_knowledge.md | ✅ |
| 2 | Network Attacks – Nmap recon, ARP poisoning MITM, DNS attacks, DoS/DDoS | security_knowledge.md | ✅ |
| 3 | Web Attacks (OWASP Top 10) – SQLi, XSS, IDOR, SSRF, Auth failures, Injection | security_knowledge.md | ✅ |
| 4 | Authentication & Session Security – JWT attacks, OAuth 2.0 attacks, brute force | security_knowledge.md | ✅ |
| 5 | Cryptography – Symmetric/Asymmetric, Hashing, TLS vulnerabilities, Certificate Pinning | security_knowledge.md | ✅ |
| 6 | Privilege Escalation – Linux (SUID, sudo, cron), Windows (service, token impersonation) | security_knowledge.md | ✅ |
| 7 | Web Application Pentesting – Burp Suite workflow, Command Injection, LFI/RFI, directory brute force | security_knowledge.md | ✅ |
| 8 | Infrastructure & Cloud Security – Linux hardening, AWS IAM, S3, GuardDuty | security_knowledge.md | ✅ |
| 9 | Defensive Security – SOC/SIEM, MITRE ATT&CK, Incident Response, Forensics | security_knowledge.md | ✅ |
| 10 | DevSecOps Pipeline – SAST/DAST/SCA, secret scanning, container scanning | security_knowledge.md | ✅ |

---

## Các chủ đề chuyên sâu

### Network Security Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 11.1 | Network Attacks Deep – Wireshark analysis, Responder (LLMNR), WPA2 cracking, Metasploit, port scan evasion | network/network_attacks.md | ✅ |
| 11.2 | Network Defense Deep – iptables/nftables rules, Snort/Suricata IDS, network segmentation, Zero Trust | network/network_defense.md | ✅ |

### Web Security Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 12.1 | OWASP Top 10 Deep – SQLi types, NoSQL injection, SSTI, Race Condition, Mass Assignment, deserialization | web/owasp_top10.md | ✅ |
| 12.2 | Web Pentesting Deep – Burp Suite advanced, CSRF deep, deserialization, SSTI, WebSockets | web/web_testing.md | ✅ |
| 12.3 | API Security – REST API attacks, GraphQL introspection/injection, JWT/OAuth2 deep, API rate limiting | web/api_security.md | ✅ |

### Cryptography Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 13.1 | Crypto Fundamentals – Block/stream ciphers, padding oracle, ECB mode attacks, Diffie-Hellman | crypto/crypto_fundamentals.md | ✅ |
| 13.2 | PKI & TLS – Certificate chain, CA attacks, HSTS, certificate transparency, mutual TLS | crypto/pki_tls.md | ✅ |

### Active Directory Security
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 14.1 | AD Attacks – Kerberoasting, AS-REP Roasting, Pass-the-Hash, DCSync, Golden/Silver Ticket, BloodHound | active_directory/ad_attacks.md | ✅ |

### Cloud Security Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 15.1 | AWS Security Deep – IAM privilege escalation, IMDS attack, Lambda security, GuardDuty, ScoutSuite | cloud/aws_security.md | ✅ |
| 15.2 | Cloud Misconfigurations – S3 public buckets, exposed metadata service, insecure SGs, GCP/Azure | cloud/cloud_misconfig.md | ✅ |

### Malware & Forensics
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 16.1 | Malware Analysis – Static (strings, PE headers), Dynamic (sandbox), Reverse engineering basics | malware/malware_analysis.md | ✅ |
| 16.2 | Incident Response – IR playbook, memory forensics (Volatility), disk forensics, log analysis | malware/incident_response.md | ✅ |

### DevSecOps Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 17.1 | DevSecOps Pipeline – Semgrep custom rules, OWASP ZAP, SBOM, secret scanning, IaC security | devsecops/devsecops_pipeline.md | ✅ |

### CTF Techniques
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 18.1 | CTF Techniques – Web, Crypto, Forensics, Pwn (Buffer Overflow), Reverse Engineering patterns | ctf/ctf_techniques.md | ✅ |

### Identity & Access Management
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 19.1 | IAM Defensive Deep Dive – identity lifecycle, password/passkey/MFA, session, OAuth/OIDC, JWT, RBAC/ABAC/ReBAC, SCIM, workload identity và incident runbook | [identity/iam_authentication_authorization.md](identity/iam_authentication_authorization.md) | ✅ |

### Secrets & Key Management
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 20.1 | Secrets & Key Management – inventory, secret lifecycle, dynamic credential, KMS/HSM, envelope encryption, rotation, revoke, CI/CD, Kubernetes và incident runbook | [secrets/secrets_key_management.md](secrets/secrets_key_management.md) | ✅ |

### Threat Modeling & Secure Architecture
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 21.1 | Threat Modeling & Secure Architecture – scope, asset, DFD, trust boundary, STRIDE, abuse case, risk treatment, security requirements và verification | [architecture/threat_modeling_secure_architecture.md](architecture/threat_modeling_secure_architecture.md) | ✅ |

### Data Security & Privacy Engineering
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 22.1 | Data Security & Privacy Engineering – inventory, classification, purpose, lineage, encryption, pseudonymization, tokenization, de-identification, retention, deletion và data rights | [data/data_security_privacy_engineering.md](data/data_security_privacy_engineering.md) | ✅ |

### Software Supply Chain Security
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 23.1 | Software Supply Chain Security – dependency policy, build isolation, SBOM/VEX, SLSA provenance, artifact signing, admission verification và compromise runbook | [supply_chain/software_supply_chain_security.md](supply_chain/software_supply_chain_security.md) | ✅ |

### Container & Kubernetes Runtime Security
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 24.1 | Container & Kubernetes Runtime Security – Pod Security, SecurityContext, ServiceAccount, NetworkPolicy, sandbox runtime, node hardening, detection và incident runbook | [runtime/container_kubernetes_runtime_security.md](runtime/container_kubernetes_runtime_security.md) | ✅ |

### Cloud-Native Detection & Incident Response
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 25.1 | Cloud-Native Detection & Incident Response – cloud/Kubernetes/runtime audit, correlation, detection engineering, triage, forensics, containment và recovery | [detection/cloud_native_detection_incident_response.md](detection/cloud_native_detection_incident_response.md) | ✅ |

### Platform Engineering Security
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 26.1 | Platform Engineering Security – product/trust model, self-service authorization, templates/plugins, resource vending, policy exception, GitOps và multi-cluster governance | [platform/platform_engineering_security.md](platform/platform_engineering_security.md) | ✅ |

### Security Testing & Validation Engineering
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 27.1 | Security Testing & Validation Engineering – assurance model, requirement traceability, negative/regression test, adversary emulation, production-safe validation và control evidence | [validation/security_testing_validation_engineering.md](validation/security_testing_validation_engineering.md) | ✅ |

### Cloud IAM Governance at Scale
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 28.1 | Cloud IAM Governance at Scale – organization hierarchy, federation, delegated administration, effective permission, JIT/PIM, access review, workload identity và incident response | [cloud/cloud_iam_governance_at_scale.md](cloud/cloud_iam_governance_at_scale.md) | ✅ |

### Vulnerability Management & Exposure Prioritization
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 29.1 | Vulnerability Management & Exposure Prioritization – asset coverage, CVSS v4, EPSS, KEV/SSVC, VEX/reachability, attack path, emergency remediation, SLA và risk acceptance | [vulnerability/vulnerability_management_exposure_prioritization.md](vulnerability/vulnerability_management_exposure_prioritization.md) | ✅ |

### Security Governance & Risk Engineering
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 30.1 | Security Governance & Risk Engineering – mission/objective, appetite/tolerance, risk scenario/register, control catalog, common/inherited controls, assurance, treatment, acceptance và enterprise aggregation | [governance/security_governance_risk_engineering.md](governance/security_governance_risk_engineering.md) | ✅ |

### Enterprise Security Architecture & Zero Trust
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 31.1 | Enterprise Security Architecture & Zero Trust – capability map, principles, trust model, CISA pillars, PDP/PIP/PEP, identity-aware enforcement, resilience và transformation roadmap | [architecture/enterprise_security_architecture_zero_trust.md](architecture/enterprise_security_architecture_zero_trust.md) | ✅ |

### Business Continuity, Disaster Recovery & Cyber Resilience
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 32.1 | Business Continuity, Disaster Recovery & Cyber Resilience – BIA, MBCO/MTPD, RTO/RPO, dependency graph, recovery strategy, protected backup, clean room, crisis coordination và exercise | [resilience/business_continuity_disaster_recovery_cyber_resilience.md](resilience/business_continuity_disaster_recovery_cyber_resilience.md) | ✅ |

### Third-Party & SaaS Security Assurance
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 33.1 | Third-Party & SaaS Security Assurance – inventory/tiering, scenario-based due diligence, shared responsibility, product/tenant security, evidence, contract, continuous assurance, incident và exit | [third_party/third_party_saas_security_assurance.md](third_party/third_party_saas_security_assurance.md) | ✅ |

### Security Architecture Review & Design Governance
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 34.1 | Security Architecture Review & Design Governance – risk triage, review tiers, traceable requirements, reference patterns, ADR, decision rights, exceptions, fitness functions và continuous conformance | [architecture/security_architecture_review_design_governance.md](architecture/security_architecture_review_design_governance.md) | ✅ |

### Security Metrics, Measurement & Executive Reporting
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 35.1 | Security Metrics, Measurement & Executive Reporting – decision-first measures, semantics, denominator, data quality, uncertainty, KPI/KRI/KCI, aggregation, dashboards và board reporting | [metrics/security_metrics_measurement_executive_reporting.md](metrics/security_metrics_measurement_executive_reporting.md) | ✅ |

### Security Program Operating Model & Capability Management
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 36.1 | Security Program Operating Model & Capability Management – capability map, delivery model, service catalog, ownership, demand/capacity, workforce, funding, sourcing, portfolio và capability health | [program/security_program_operating_model_capability_management.md](program/security_program_operating_model_capability_management.md) | ✅ |

### Security Strategy, Investment & Portfolio Prioritization
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 37.1 | Security Strategy, Investment & Portfolio Prioritization – strategic choices, current/target profile, business case, lifecycle cost, benefit, dependency, capacity-constrained portfolio và stop/pivot/continue | [program/security_strategy_investment_portfolio_prioritization.md](program/security_strategy_investment_portfolio_prioritization.md) | ✅ |

### Security Culture, Human Risk & Behavior Engineering
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 38.1 | Security Culture, Human Risk & Behavior Engineering – human-centered security, target behavior, friction/default/incentive, learning lifecycle, phishing context, reporting, insider risk, behavioral data và outcome measurement | [program/security_culture_human_risk_behavior_engineering.md](program/security_culture_human_risk_behavior_engineering.md) | ✅ |

### Security Transformation & Change Management
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 39.1 | Security Transformation & Change Management – current/target/transition profile, stakeholder impact, readiness, adoption, pilot, migration waves, coexistence, cutover/rollback, legacy retirement và institutionalization | [program/security_transformation_change_management.md](program/security_transformation_change_management.md) | ✅ |

### Insider Risk Program & Trusted Workforce Operations
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 40.1 | Insider Risk Program & Trusted Workforce Operations – multidisciplinary governance, critical assets, JML/least privilege, supportive prevention, lawful signals, privacy/fairness, triage, investigation, containment và due process | [program/insider_risk_trusted_workforce_operations.md](program/insider_risk_trusted_workforce_operations.md) | ✅ |

### Security Policy, Standards & Exception Lifecycle Engineering
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 41.1 | Security Policy, Standards & Exception Lifecycle Engineering – artifact hierarchy, normative requirements, baseline/tailoring, policy as code, evidence, exception/waiver/risk acceptance, version migration và retirement | [program/security_policy_standards_exception_lifecycle_engineering.md](program/security_policy_standards_exception_lifecycle_engineering.md) | ✅ |

### Security Compliance Engineering & Continuous Control Assurance
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 42.1 | Security Compliance Engineering & Continuous Control Assurance – obligation/applicability, control mapping, assessment plans, evidence provenance, continuous monitoring, findings, remediation/retest và audit readiness | [program/security_compliance_engineering_continuous_control_assurance.md](program/security_compliance_engineering_continuous_control_assurance.md) | ✅ |

### Security Control Library & Common Control Inheritance
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 43.1 | Security Control Library & Common Control Inheritance – canonical control semantics, common/hybrid/system-specific controls, provider–consumer contracts, dependency/concentration, inherited evidence, finding propagation và retirement | [program/security_control_library_common_control_inheritance.md](program/security_control_library_common_control_inheritance.md) | ✅ |

### Regulatory Change & Obligation Management
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 44.1 | Regulatory Change & Obligation Management – authoritative-source monitoring, interpretation, applicability, jurisdiction/entity/product scope, semantic diff, impact graph, implementation, assurance và regulatory reporting | [program/regulatory_change_obligation_management.md](program/regulatory_change_obligation_management.md) | ✅ |

### Security Authorization & Ongoing Risk Decision Engineering
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 45.1 | Security Authorization & Ongoing Risk Decision Engineering – authorization boundary, delegated authority, decision package, residual/aggregate risk, conditions, significant change, ongoing monitoring, suspend/revoke và reauthorization | [program/security_authorization_ongoing_risk_decision_engineering.md](program/security_authorization_ongoing_risk_decision_engineering.md) | ✅ |

### Security Governance Forums, Committees & Decision Records
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 46.1 | Security Governance Forums, Committees & Decision Records – decision inventory, forum charter/authority, routing, pre-read, quorum/recusal, challenge/dissent, escalation, board oversight, action và decision traceability | [program/security_governance_forums_committees_decision_records.md](program/security_governance_forums_committees_decision_records.md) | ✅ |

### Security Risk Quantification, Scenario Analysis & Decision Uncertainty
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 47.1 | Security Risk Quantification, Scenario Analysis & Decision Uncertainty – decision framing, scenario grammar, frequency/magnitude ranges, calibration, tail/correlation, sensitivity, value of information và model governance | [program/security_risk_quantification_scenario_analysis_decision_uncertainty.md](program/security_risk_quantification_scenario_analysis_decision_uncertainty.md) | ✅ |

### Cybersecurity Mergers, Acquisitions & Divestitures Engineering
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 48.1 | Cybersecurity Mergers, Acquisitions & Divestitures Engineering – deal governance, clean-team diligence, inherited exposure, purchase-agreement inputs, Day-1 controls, integration, carve-out/TSA và separation assurance | [program/cybersecurity_mergers_acquisitions_divestitures_engineering.md](program/cybersecurity_mergers_acquisitions_divestitures_engineering.md) | ✅ |

### Security Risk Transfer, Cyber Insurance & Contractual Allocation
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 49.1 | Security Risk Transfer, Cyber Insurance & Contractual Allocation – scenario-to-coverage mapping, first/third-party loss, limits/retentions/exclusions, contractual allocation, claims readiness và residual accountability | [program/security_risk_transfer_cyber_insurance_contractual_allocation.md](program/security_risk_transfer_cyber_insurance_contractual_allocation.md) | ✅ |

### Cybersecurity Economics, Business Cases & Control Value Realization
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 50.1 | Cybersecurity Economics, Business Cases & Control Value Realization – BAU/counterfactual, lifecycle/opportunity cost, marginal risk reduction, causal evaluation, NPV/sensitivity, option value và forecast-vs-actual learning | [program/cybersecurity_economics_business_cases_control_value_realization.md](program/cybersecurity_economics_business_cases_control_value_realization.md) | ✅ |

### Security Service Management, Catalogs & Internal Customer Experience
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 51.1 | Security Service Management, Catalogs & Internal Customer Experience – service portfolio/catalog/contracts, request state machine, demand/capacity, SLO/XLO, support/problem/knowledge, versioning và retirement | [program/security_service_management_catalogs_internal_customer_experience.md](program/security_service_management_catalogs_internal_customer_experience.md) | ✅ |

### Security Product Management & Platform Adoption Economics
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 52.1 | Security Product Management & Platform Adoption Economics – product discovery/thesis/fit, secure defaults, activation/correct use/retention, cohort experiments, roadmap, switching cost và adoption economics | [program/security_product_management_platform_adoption_economics.md](program/security_product_management_platform_adoption_economics.md) | ✅ |

### Security Knowledge Management, Standards Enablement & Decision Support
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 53.1 | Security Knowledge Management, Standards Enablement & Decision Support – canonical sources, content contracts/taxonomy, findability, decision aids, expert routing, knowledge lifecycle, AI/RAG assurance và reuse economics | [program/security_knowledge_management_standards_enablement_decision_support.md](program/security_knowledge_management_standards_enablement_decision_support.md) | ✅ |

### Security Developer Relations, Champions & Community Enablement
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 54.1 | Security Developer Relations, Champions & Community Enablement – two-way advocacy, champion charter/coverage/capability, community channels, contributor governance, feedback closure, network health và sustainable scale | [program/security_developer_relations_champions_community_enablement.md](program/security_developer_relations_champions_community_enablement.md) | ✅ |

### Security Engineering Enablement & Secure Delivery Coaching
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 55.1 | Security Engineering Enablement & Secure Delivery Coaching – coaching contracts/modes, Task–Knowledge–Skill analysis, pairing/clinics, work-product transfer, fading support, time-to-independence, capacity và coaching assurance | [program/security_engineering_enablement_secure_delivery_coaching.md](program/security_engineering_enablement_secure_delivery_coaching.md) | ✅ |

### Security Research, Innovation & Emerging Technology Governance
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 56.1 | Security Research, Innovation & Emerging Technology Governance – horizon signals, falsifiable hypotheses, readiness vectors, safe sandboxes, research integrity, dual-use, evidence gates, technology transfer và responsible retirement | [program/security_research_innovation_emerging_technology_governance.md](program/security_research_innovation_emerging_technology_governance.md) | ✅ |

### Security Capability Academies, Mentoring & Technical Career Development
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 57.1 | Security Capability Academies, Mentoring & Technical Career Development – work-to-capability mapping, NICE/TKS, proficiency evidence, deliberate practice, assessment calibration, mentoring/apprenticeship, career mobility và succession pipeline | [program/security_capability_academies_mentoring_technical_career_development.md](program/security_capability_academies_mentoring_technical_career_development.md) | ✅ |

### Security Talent Acquisition, Workforce Analytics & Succession Resilience
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 58.1 | Security Talent Acquisition, Workforce Analytics & Succession Resilience – work-based demand/capacity, role design, structured selection, candidate/workforce data governance, internal mobility, critical-role coverage, transition và succession | [program/security_talent_acquisition_workforce_analytics_succession_resilience.md](program/security_talent_acquisition_workforce_analytics_succession_resilience.md) | ✅ |

---

## Chú thích trạng thái
- ✅ Hoàn thành – đã có nội dung
- 🔄 Đang làm
- ⬜ Chưa làm

## Certifications Reference
| Cert | Level | Focus |
|------|-------|-------|
| CompTIA Security+ | Entry | General security fundamentals |
| CEH (Certified Ethical Hacker) | Intermediate | Hacking methodology |
| OSCP (Offensive Security) | Advanced | Hands-on penetration testing |
| GPEN / GWAPT | Advanced | GIAC pentest / web app |
| CISSP | Management | Security management, governance |
| AWS Security Specialty | Cloud | AWS-specific security |

---

*Cập nhật lần cuối: 2026-08-03.*

---

<!-- AUTO-GENERATED-DOC-INDEX:START -->

## Tài liệu trong chủ đề

- [Active Directory Security Deep Dive](active_directory/ad_attacks.md)
- [Enterprise Security Architecture & Zero Trust – Từ năng lực đến thực thi chính sách](architecture/enterprise_security_architecture_zero_trust.md)
- [Security Architecture Review & Design Governance – Review để ra quyết định, không để tạo hàng đợi](architecture/security_architecture_review_design_governance.md)
- [Threat Modeling & Secure Architecture – Mô hình hóa mối đe dọa và kiến trúc an toàn](architecture/threat_modeling_secure_architecture.md)
- [Cloud Security Deep Dive – AWS](cloud/aws_security.md)
- [Cloud IAM Governance at Scale – Quản trị quyền trên quy mô organization](cloud/cloud_iam_governance_at_scale.md)
- [Cloud Misconfigurations Deep Dive](cloud/cloud_misconfig.md)
- [Cryptography Fundamentals Deep Dive](crypto/crypto_fundamentals.md)
- [PKI & TLS Deep Dive](crypto/pki_tls.md)
- [CTF Techniques Deep Dive](ctf/ctf_techniques.md)
- [Data Security & Privacy Engineering – Bảo vệ dữ liệu xuyên suốt vòng đời](data/data_security_privacy_engineering.md)
- [Cloud-Native Detection & Incident Response – Phát hiện và ứng phó xuyên control plane](detection/cloud_native_detection_incident_response.md)
- [DevSecOps Pipeline Deep Dive](devsecops/devsecops_pipeline.md)
- [Glossary Security](glossary.md)
- [Security Governance & Risk Engineering – Biến risk thành quyết định có trách nhiệm](governance/security_governance_risk_engineering.md)
- [Identity & Access Management – Authentication, Session và Authorization](identity/iam_authentication_authorization.md)
- [Incident Response Deep Dive](malware/incident_response.md)
- [Malware Analysis Deep Dive](malware/malware_analysis.md)
- [Security Metrics, Measurement & Executive Reporting – Đo để ra quyết định](metrics/security_metrics_measurement_executive_reporting.md)
- [Network Attacks Deep Dive](network/network_attacks.md)
- [Network Defense Deep Dive](network/network_defense.md)
- [Platform Engineering Security – Golden path, guardrail và self-service an toàn](platform/platform_engineering_security.md)
- [Cybersecurity Economics, Business Cases & Control Value Realization](program/cybersecurity_economics_business_cases_control_value_realization.md)
- [Cybersecurity Mergers, Acquisitions & Divestitures Engineering](program/cybersecurity_mergers_acquisitions_divestitures_engineering.md)
- [Insider Risk Program & Trusted Workforce Operations](program/insider_risk_trusted_workforce_operations.md)
- [Regulatory Change & Obligation Management](program/regulatory_change_obligation_management.md)
- [Security Authorization & Ongoing Risk Decision Engineering](program/security_authorization_ongoing_risk_decision_engineering.md)
- [Security Capability Academies, Mentoring & Technical Career Development](program/security_capability_academies_mentoring_technical_career_development.md)
- [Security Compliance Engineering & Continuous Control Assurance](program/security_compliance_engineering_continuous_control_assurance.md)
- [Security Control Library & Common Control Inheritance](program/security_control_library_common_control_inheritance.md)
- [Security Culture, Human Risk & Behavior Engineering](program/security_culture_human_risk_behavior_engineering.md)
- [Security Developer Relations, Champions & Community Enablement](program/security_developer_relations_champions_community_enablement.md)
- [Security Engineering Enablement & Secure Delivery Coaching](program/security_engineering_enablement_secure_delivery_coaching.md)
- [Security Governance Forums, Committees & Decision Records](program/security_governance_forums_committees_decision_records.md)
- [Security Knowledge Management, Standards Enablement & Decision Support](program/security_knowledge_management_standards_enablement_decision_support.md)
- [Security Policy, Standards & Exception Lifecycle Engineering](program/security_policy_standards_exception_lifecycle_engineering.md)
- [Security Product Management & Platform Adoption Economics](program/security_product_management_platform_adoption_economics.md)
- [Security Program Operating Model & Capability Management](program/security_program_operating_model_capability_management.md)
- [Security Research, Innovation & Emerging Technology Governance](program/security_research_innovation_emerging_technology_governance.md)
- [Security Risk Quantification, Scenario Analysis & Decision Uncertainty](program/security_risk_quantification_scenario_analysis_decision_uncertainty.md)
- [Security Risk Transfer, Cyber Insurance & Contractual Allocation](program/security_risk_transfer_cyber_insurance_contractual_allocation.md)
- [Security Service Management, Catalogs & Internal Customer Experience](program/security_service_management_catalogs_internal_customer_experience.md)
- [Security Strategy, Investment & Portfolio Prioritization](program/security_strategy_investment_portfolio_prioritization.md)
- [Security Talent Acquisition, Workforce Analytics & Succession Resilience](program/security_talent_acquisition_workforce_analytics_succession_resilience.md)
- [Security Transformation & Change Management](program/security_transformation_change_management.md)
- [Business Continuity, Disaster Recovery & Cyber Resilience – Duy trì mission khi hệ thống bị gián đoạn](resilience/business_continuity_disaster_recovery_cyber_resilience.md)
- [Container & Kubernetes Runtime Security – Bảo vệ workload khi đang chạy](runtime/container_kubernetes_runtime_security.md)
- [Secrets & Key Management – Quản lý bí mật và khóa mật mã trong production](secrets/secrets_key_management.md)
- [Tổng Hợp Kiến Thức Bảo Mật & Tấn Công](security_knowledge.md)
- [Software Supply Chain Security – Bảo vệ chuỗi cung ứng phần mềm](supply_chain/software_supply_chain_security.md)
- [Third-Party & SaaS Security Assurance – Quản trị niềm tin ngoài ranh giới tổ chức](third_party/third_party_saas_security_assurance.md)
- [Security Testing & Validation Engineering – Chứng minh control thực sự hoạt động](validation/security_testing_validation_engineering.md)
- [Vulnerability Management & Exposure Prioritization – Giảm risk, không chỉ đóng CVE](vulnerability/vulnerability_management_exposure_prioritization.md)
- [API Security Deep Dive](web/api_security.md)
- [OWASP Top 10 Deep Dive](web/owasp_top10.md)
- [Web Pentesting Deep Dive](web/web_testing.md)

<!-- AUTO-GENERATED-DOC-INDEX:END -->
