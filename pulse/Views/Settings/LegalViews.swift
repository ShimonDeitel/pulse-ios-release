import SwiftUI

// MARK: - Terms of Use
// Hardened for multi-jurisdictional defense:
//   • US (federal + state, CA/NY/IL/FL/TX/MA/CO/CT/UT/VA/WA explicitly)
//   • EU (GDPR + DSA + DMA), UK GDPR, EEA
//   • Canada (PIPEDA + Quebec Law 25)
//   • Brazil (LGPD), Mexico
//   • Australia (Privacy Act + Spam Act), New Zealand
//   • India (DPDP 2023), Japan (APPI), South Korea (PIPA)
//   • China (PIPL + Cybersecurity Law), Singapore PDPA, HK PDPO
//   • UAE, KSA (PDPL), South Africa (POPIA), Nigeria (NDPR), Israel (PPL)
// Plus BIPA / Texas CUBI / Washington biometric law for photo features.
// Apple App Store EULA addendum embedded.

/// A link to the canonical legal docs on the marketing website. Every entry
/// point to the legal text (Profile, paywall, sign-in) funnels through
/// `TermsOfServiceView` / `PrivacyPolicyView`, so placing this here surfaces the
/// website link in EVERY place Terms of Use / Privacy Policy appears.
struct LegalWebsiteLink: View {
    enum Kind { case terms, privacy }
    let kind: Kind
    private var url: URL {
        switch kind {
        case .terms:   return URL(string: "https://shimondeitel.github.io/pulse-goals/terms.html")!
        case .privacy: return URL(string: "https://shimondeitel.github.io/pulse-goals/privacy.html")!
        }
    }
    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: "safari").font(.system(size: 12, weight: .semibold))
                Text(kind == .terms ? "View Terms of Use on our website"
                                    : "View Privacy Policy on our website")
                    .font(.system(size: 13, weight: .semibold))
                    .underline()
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                Spacer(minLength: 0)
            }
            .foregroundColor(PulseColors.signal)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseColors.signal.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PulseSpacing.xl) {
                Text("Effective: June 2, 2026 \u{00B7} v2.2")
                    .font(PulseTypography.labelSmall)
                    .foregroundColor(PulseColors.textTertiary)

                LegalWebsiteLink(kind: .terms)

                redBanner(
                    "PLEASE READ. SECTION 18 (BINDING ARBITRATION + CLASS-ACTION WAIVER) AND SECTION 12 (LIABILITY CAP) MATERIALLY LIMIT YOUR RIGHTS. SECTION 7 (HEALTH & WELLNESS) WARNS YOU NOT TO USE THIS APP AS A SUBSTITUTE FOR PROFESSIONAL MEDICAL OR FITNESS ADVICE."
                )

                legalSection("1. Acceptance") {
                    "By downloading, installing, accessing, registering for, or otherwise using the Pulse mobile application, websites, APIs, or any related service (collectively, the \"Service\"), you (\"User,\" \"you,\" \"your\") agree to be legally bound by these Terms of Use (the \"Terms\"). If you do not agree to every provision, do not access or use the Service. If you accept these Terms on behalf of an organization, you represent that you have authority to bind that organization, and \"you\" includes that organization. These Terms incorporate by reference our Privacy Policy, any in-Service notices, and (for paid subscriptions) the applicable order or pricing page in effect at the time of purchase."
                }

                legalSection("2. Eligibility & Account Registration") {
                    "You must be at least 13 years old (or the higher minimum age required by the laws of your country of residence — e.g., 14 in Spain, Italy, Bulgaria; 15 in Czechia, France, Greece, Slovenia; 16 in Germany, Ireland, the Netherlands, Lithuania, Luxembourg, Romania, Croatia, Hungary, Poland, Slovakia; 18 elsewhere if so required) to create an account. To enter a paid subscription you must be 18 (or the age of majority in your jurisdiction). You must provide truthful, current, accurate information and keep it updated. You are responsible for safeguarding your account credentials and for all activity under your account. We may refuse, suspend, or terminate any account at our sole discretion."
                }

                legalSection("3. Description of the Service") {
                    "Pulse is a personal-productivity application that uses third-party large-language models and image-analysis models to generate goal roadmaps (\"Pulses\"), text coaching, and (where you opt in) photo-based progress analysis. The Service is offered for personal, non-commercial use only and is not certified, supervised, or endorsed by any medical, fitness, mental-health, financial, legal, educational, or regulatory body. The Service is provided on a subscription or free-tier basis and may change at any time."
                }

                legalSection("4. AI Output — Informational Only, Not Professional Advice") {
                    "All output generated by the Service — including but not limited to goal roadmaps, individual Pulses, coaching messages, probability scores, AI chat, photo analysis, quizzes, transformation predictions, and recommended habits — is produced algorithmically by third-party AI systems and is provided \"AS-IS\" for general informational, educational, motivational, and entertainment purposes only. AI output may be inaccurate, incomplete, outdated, biased, offensive, or harmful. AI output is NOT, and you must not rely on it as, medical, mental-health, psychiatric, psychological, nutritional, dietary, fitness, athletic-training, legal, tax, accounting, financial, investment, vocational, educational, or other professional advice. Always consult a duly licensed and qualified professional before acting on any AI output. Use of the Service for any health, fitness, financial, legal, or safety-related decision is at your sole risk."
                }

                legalSection("5. Subscriptions, Trials, Auto-Renewal & Cancellation") {
                    "Paid subscriptions auto-renew at the then-current price for the same subscription period unless cancelled at least 24 hours before the end of the current period. Billing is processed exclusively by Apple (via your Apple ID); we do not directly process payments. To manage or cancel your subscription, open your iOS Settings → [your name] → Subscriptions; deleting the App alone does not cancel a subscription. Free trials, if offered, automatically convert to paid subscriptions unless cancelled before trial end. Prices may change for future billing periods; any material price change will be disclosed before it takes effect for your subscription. Refunds are governed by Apple's Media Services Terms — we cannot process refunds directly. CALIFORNIA AUTOMATIC RENEWAL LAW (BPC § 17600 et seq.) NOTICE: You may cancel any auto-renewing subscription at any time through your Apple ID Settings; a renewal reminder is sent by Apple before each billing cycle for annual subscriptions; this entire Section constitutes the required clear and conspicuous disclosure under California, New York GBL § 527-a, Oregon, Vermont, and similar statutes."
                }

                legalSection("6. User Content & License Grant") {
                    "You retain ownership of all content you submit to the Service, including goal titles, descriptions, deadlines, motivation levels, obstacles, free-text notes, photos, and AI-chat messages (\"User Content\"). By submitting User Content you grant Pulse and our service providers a worldwide, non-exclusive, royalty-free, fully paid-up, sublicensable, transferable license to host, store, reproduce, modify, create derivative works of, transmit, distribute, perform, and display that User Content solely for purposes of operating, providing, improving, and securing the Service — including (a) transmitting it to third-party AI inference providers for processing; (b) backing it up to cloud storage; (c) using anonymized and de-identified versions for product improvement and model evaluation; (d) enforcing these Terms. You represent and warrant that you own or have all rights, licenses, and permissions necessary to grant the foregoing license and that your User Content does not infringe, misappropriate, or violate any third-party right or applicable law. This license survives termination of these Terms for any anonymized/de-identified derivatives already created."
                }

                legalSection("7. Health, Wellness & Fitness Disclaimer") {
                    "PULSE IS NOT A MEDICAL DEVICE, NOT A HEALTHCARE PROVIDER, NOT A LICENSED DIETICIAN, AND NOT A FITNESS COACH. We do not diagnose, treat, cure, monitor, mitigate, or prevent any disease, condition, or health concern. Goal roadmaps in any category — including but not limited to fitness, running, weight loss, weightlifting, nutrition, sleep, meditation, mental wellbeing, and substance moderation — are AI-generated suggestions that may be inappropriate for your individual circumstances, medical history, medications, allergies, injuries, or risk factors. Consult a licensed physician before starting, modifying, or stopping any fitness, diet, supplement, sleep, or mental-health regimen. If you experience pain, dizziness, shortness of breath, chest pressure, fainting, persistent fatigue, mood deterioration, suicidal ideation, or any other concerning symptom, stop immediately and seek qualified medical attention. By using the Service you accept all risk of bodily injury, illness, or death arising from acting on AI output. THE PRECEDING SENTENCE IS NOT INTENDED TO EXCLUDE LIABILITY FOR DEATH OR PERSONAL INJURY CAUSED BY OUR GROSS NEGLIGENCE OR WILLFUL MISCONDUCT WHERE SUCH EXCLUSION IS PROHIBITED BY APPLICABLE LAW (e.g., UK CRA 2015, Australian Consumer Law)."
                }

                legalSection("8. Photo, Biometric & Sensitive Data") {
                    "If you use the Photo Transformation feature or attach photos as proof, those images are transmitted to a third-party AI inference provider for processing in transient memory and are not retained on our servers after the response is returned to your device. WE DO NOT KNOWINGLY COLLECT, USE, STORE, OR DISCLOSE BIOMETRIC IDENTIFIERS OR BIOMETRIC INFORMATION as defined under the Illinois Biometric Information Privacy Act (740 ILCS 14), the Texas Capture or Use of Biometric Identifier Act (Bus. & Com. Code § 503.001), the Washington Biometric Privacy Act (RCW 19.375), or analogous laws. We do not extract face geometry, fingerprints, retina or iris scans, voiceprints, or hand or face geometric data for identification. If you reside in Illinois, Texas, or Washington, you may withhold photo features entirely — they are optional. By uploading a photo you separately confirm informed, written consent to such transient AI processing, you authorize the foregoing third-party transmission for that limited purpose, and you waive any right to assert a BIPA, CUBI, or comparable claim against Pulse based solely on transient AI inference processing."
                }

                legalSection("9. Acceptable Use & Prohibited Conduct") {
                    "You agree NOT to: (a) use the Service for any unlawful, fraudulent, deceptive, or harmful purpose; (b) submit content that is defamatory, obscene, hateful, harassing, threatening, sexually explicit involving minors, infringing, or that incites violence, self-harm, or terrorism; (c) attempt to reverse-engineer, decompile, disassemble, decrypt, or otherwise derive the source code of the Service except to the extent expressly permitted by mandatory law (e.g., EU Software Directive 2009/24/EC Art. 5(3)/6); (d) probe, scan, or test the Service for vulnerabilities, except via our published responsible-disclosure channel; (e) access or use the Service via automated means, scrapers, bots, or unauthorized third-party clients; (f) impersonate any person or entity; (g) interfere with, overload, or disrupt the Service or its infrastructure; (h) bypass or attempt to bypass any access control, rate limit, or security feature; (i) resell, sublicense, or commercially exploit the Service; (j) use the Service or its output to train, fine-tune, evaluate, or benchmark a competing AI model or product, or to create a substantially similar product; (k) use the Service in violation of US, EU, UK, or other applicable export-control or sanctions law; (l) send unsolicited commercial messages via the Service, in violation of CAN-SPAM, CASL, Australian Spam Act 2003, EU ePrivacy Directive, or analogous law. Violations may result in immediate suspension, account termination, deletion of User Content, referral to law enforcement, and any other remedy at law or equity."
                }

                legalSection("10. Intellectual Property") {
                    "The Service, including the name \"Pulse,\" the logo, the visual design system, source code, models, prompts, documentation, and all other materials (excluding User Content), is owned by Pulse or its licensors and is protected by US, EU, UK, and international copyright, trademark, trade-secret, patent, and other intellectual-property laws. We grant you a personal, non-exclusive, non-transferable, non-sublicensable, revocable license to install and use one copy of the App on devices you own or control, solely for personal, non-commercial use, subject to these Terms. All rights not expressly granted are reserved."
                }

                legalSection("11. Disclaimer of Warranties") {
                    "EXCEPT AS REQUIRED BY APPLICABLE NON-WAIVABLE LAW, THE SERVICE IS PROVIDED \"AS-IS\" AND \"AS-AVAILABLE,\" WITH ALL FAULTS, AND WITHOUT WARRANTY OF ANY KIND. WE DISCLAIM ALL WARRANTIES, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING WITHOUT LIMITATION WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, ACCURACY, TITLE, QUIET ENJOYMENT, SYSTEM INTEGRATION, AND ANY WARRANTY ARISING FROM COURSE OF DEALING, COURSE OF PERFORMANCE, OR TRADE USAGE. WE DO NOT WARRANT THAT THE SERVICE WILL BE UNINTERRUPTED, TIMELY, SECURE, ERROR-FREE, OR FREE OF VIRUSES OR HARMFUL COMPONENTS, OR THAT AI OUTPUT WILL BE ACCURATE, RELIABLE, OR SUITABLE FOR ANY PARTICULAR PURPOSE. FOR EU/UK/AUSTRALIAN/NEW ZEALAND CONSUMERS: nothing in this Section limits non-excludable consumer guarantees under the EU Consumer Rights Directive 2011/83/EU, UK Consumer Rights Act 2015, Australian Consumer Law (Sch. 2 to the Competition and Consumer Act 2010), or NZ Consumer Guarantees Act 1993 — to the extent those laws apply you have remedies that cannot be excluded by contract."
                }

                legalSection("12. Limitation of Liability") {
                    "TO THE FULLEST EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL PULSE, ITS AFFILIATES, OR ITS OFFICERS, DIRECTORS, EMPLOYEES, CONTRACTORS, OR AGENTS BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, PUNITIVE, EXEMPLARY, OR ENHANCED DAMAGES, OR FOR LOST PROFITS, LOST DATA, LOSS OF GOODWILL, BUSINESS INTERRUPTION, OR PERSONAL INJURY OR ILLNESS RESULTING FROM AI OUTPUT, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES, AND REGARDLESS OF THE LEGAL THEORY (CONTRACT, TORT, NEGLIGENCE, STRICT LIABILITY, STATUTE, OR OTHERWISE). OUR AGGREGATE LIABILITY ARISING OUT OF OR RELATING TO THESE TERMS OR THE SERVICE SHALL NOT EXCEED THE GREATER OF (i) THE TOTAL AMOUNTS YOU PAID US (OR APPLE ON YOUR BEHALF) FOR THE SERVICE IN THE TWELVE (12) MONTHS PRECEDING THE EVENT GIVING RISE TO LIABILITY, OR (ii) FIFTY US DOLLARS (USD $50). THIS CAP APPLIES IN THE AGGREGATE, NOT PER CLAIM. SOME JURISDICTIONS DO NOT ALLOW THE EXCLUSION OR LIMITATION OF CERTAIN DAMAGES; IN THOSE JURISDICTIONS THIS LIMITATION APPLIES ONLY TO THE MAXIMUM EXTENT PERMITTED BY LAW AND DOES NOT EXCLUDE LIABILITY FOR DEATH OR PERSONAL INJURY CAUSED BY GROSS NEGLIGENCE OR INTENTIONAL MISCONDUCT, FOR FRAUD, FOR FRAUDULENT MISREPRESENTATION, OR FOR ANY OTHER LIABILITY THAT CANNOT BE EXCLUDED OR LIMITED BY APPLICABLE LAW."
                }

                legalSection("13. Indemnification") {
                    "You agree to defend, indemnify, and hold harmless Pulse, its affiliates, and their officers, directors, employees, contractors, and agents from and against any and all third-party claims, demands, actions, investigations, damages, losses, liabilities, judgments, settlements, costs, and expenses (including reasonable attorneys' fees and disbursements) arising out of or related to: (a) your use or misuse of the Service; (b) your breach of these Terms or any law; (c) your User Content, including any claim that it infringes or violates a third-party right; (d) your reliance on any AI output; (e) any health, fitness, financial, legal, or other action you take based on the Service. We may assume exclusive control of the defense and settlement of any indemnified claim, and you agree to cooperate fully and not to settle any claim without our prior written consent."
                }

                legalSection("14. Termination") {
                    "We may suspend, restrict, or terminate your access to the Service, with or without notice, at any time, for any reason or no reason, including for breach of these Terms. You may stop using the Service and delete your account at any time via Profile → Your Data → Delete Account. Upon termination: your license to use the Service ends; we may delete your User Content (subject to backup retention windows); Sections 4, 6 (sublicensable license), 7, 8, 10–13, 15, 18–24 survive. Termination does not entitle you to any refund of pre-paid fees except where mandatory consumer law requires otherwise."
                }

                legalSection("15. Modifications to the Service & to These Terms") {
                    "We may modify, suspend, replace, or discontinue all or any part of the Service at any time, with or without notice, and without liability to you. We may revise these Terms from time to time. Material changes will be disclosed in-App with a revised \"Effective\" date; your continued use of the Service after the effective date of revised Terms constitutes acceptance. If you do not agree to revised Terms, you must stop using the Service."
                }

                legalSection("16. Privacy & Data Processing") {
                    "Our collection, use, disclosure, and protection of personal information is described in the Privacy Policy, which forms an integral part of these Terms. By using the Service you also agree to the Privacy Policy."
                }

                legalSection("17. Export Compliance, Sanctions, U.S. Government Users") {
                    "You may not use, export, re-export, transfer, or release the Service in violation of any applicable export-control or sanctions law of the United States (including OFAC regulations), the United Kingdom, the European Union, or any other competent jurisdiction. You represent that you are not located in, organized under the laws of, or ordinarily a resident of, any country or region subject to comprehensive sanctions (currently including Cuba, Iran, North Korea, Syria, the Crimea, Donetsk, and Luhansk regions of Ukraine), and that you are not on any U.S. or EU restricted-party list. The Service is a \"commercial item\" within 48 C.F.R. § 2.101; U.S. Government end-users acquire the Service with only those rights herein."
                }

                legalSection("18. Binding Arbitration & Class-Action Waiver (US & Canada Residents)") {
                    "EXCEPT AS OTHERWISE PROVIDED BELOW, YOU AND PULSE AGREE THAT ANY DISPUTE, CLAIM, OR CONTROVERSY ARISING OUT OF OR RELATING TO THESE TERMS, THE SERVICE, OR THE RELATIONSHIP BETWEEN US (a \"Dispute\") shall be resolved exclusively by FINAL AND BINDING INDIVIDUAL ARBITRATION administered by JAMS pursuant to its Streamlined Arbitration Rules. The seat of arbitration shall be San Francisco County, California. The arbitration shall be conducted in English by a single arbitrator. The arbitrator shall have exclusive authority to resolve any threshold issue of arbitrability, including scope, formation, enforceability, and unconscionability. YOU AND PULSE EACH WAIVE THE RIGHT TO A JURY TRIAL. YOU AND PULSE EACH WAIVE THE RIGHT TO PARTICIPATE IN A CLASS ACTION, COLLECTIVE ACTION, PRIVATE ATTORNEY GENERAL ACTION, MASS ARBITRATION, OR OTHER REPRESENTATIVE PROCEEDING. The arbitrator may not consolidate claims of more than one person and may not preside over any form of representative proceeding. CARVE-OUTS: either party may (a) bring an individual claim in small-claims court, or (b) seek injunctive relief in court for actual or threatened infringement of intellectual-property rights. THIRTY-DAY OPT-OUT: you may opt out of this Section 18 by emailing meir56885@gmail.com within 30 days of first accepting these Terms, including your full name, email used to register, and a clear statement of intent to opt out; opting out does not affect any other provision. If the class-action waiver is found unenforceable as to any claim or remedy, that claim shall proceed in court but the rest of this Section shall remain in effect. NOT APPLICABLE TO EU/UK/SWITZERLAND/AUSTRALIA/NEW ZEALAND RESIDENTS: this Section 18 does not apply to consumers domiciled in the European Economic Area, the United Kingdom, Switzerland, Australia, or New Zealand, who retain access to their local consumer-protection courts and remedies that cannot be waived by contract."
                }

                legalSection("19. Governing Law & Venue") {
                    "These Terms are governed by the substantive laws of the State of California, USA, without regard to its conflict-of-laws principles, except where overridden by mandatory consumer-protection law of your country of residence. The UN Convention on Contracts for the International Sale of Goods does not apply. To the extent any Dispute is not subject to arbitration under Section 18, the parties irrevocably submit to the exclusive jurisdiction of the state and federal courts located in San Francisco County, California — except that (i) EU consumers may bring proceedings in the courts of their EU country of habitual residence, (ii) UK consumers may bring proceedings in the courts of England, Wales, Scotland, or Northern Ireland as applicable to their residence, (iii) Brazilian consumers may bring proceedings in the courts of their domicile under the Brazilian Consumer Defense Code (Law 8,078/90), (iv) Australian consumers may rely on the non-excludable rights of the Australian Consumer Law, and (v) consumers in other jurisdictions may rely on the non-excludable rights of their local consumer-protection law."
                }

                legalSection("20. Force Majeure") {
                    "We shall not be liable for any failure or delay in performance of these Terms to the extent caused by circumstances beyond our reasonable control, including acts of God, war, terrorism, civil unrest, government action, embargo, sanction, pandemic, epidemic, natural disaster, internet or telecommunications outage, hardware failure, third-party service-provider failure, AI inference provider outage, denial-of-service attack, or labor dispute."
                }

                legalSection("21. Severability, Waiver, Headings, and Interpretation") {
                    "If any provision of these Terms is held by a court of competent jurisdiction to be unenforceable, that provision shall be modified to the minimum extent necessary to make it enforceable, and the remaining provisions shall remain in full force and effect. Our failure to enforce any right or provision shall not constitute a waiver. Headings are for convenience only and do not affect interpretation. The words \"include\" and \"including\" are non-exhaustive. These Terms have been drafted in English; any translation is provided for convenience only and the English text controls in the event of conflict."
                }

                legalSection("22. Entire Agreement, Assignment, Notices, and No Third-Party Beneficiaries") {
                    "These Terms, together with the Privacy Policy and any in-Service or order-form notices, constitute the entire agreement between you and Pulse regarding the Service and supersede all prior written or oral agreements. You may not assign or transfer these Terms; any attempted assignment in violation of this Section is void. We may assign these Terms to an affiliate or in connection with a merger, acquisition, sale of substantially all assets, or similar transaction. Notices to you may be delivered via the Service or to the email address on your account. Apple, Inc. and its subsidiaries are third-party beneficiaries of these Terms for the limited purposes set forth in Section 25 (Apple App Store Addendum); otherwise these Terms do not create any third-party beneficiary rights."
                }

                legalSection("23. DMCA — Copyright Complaints") {
                    "If you are a copyright owner or authorized agent and believe that material in the Service infringes your copyright, send a written notice meeting the requirements of 17 U.S.C. § 512(c)(3) to our designated DMCA Agent at meir56885@gmail.com. We have a policy of terminating accounts of repeat infringers in appropriate circumstances. Counter-notices may be sent to the same address."
                }

                legalSection("24. Government & Industry-Specific Compliance") {
                    "If you are subject to HIPAA (US health), GLBA (US finance), FERPA (US education), PCI-DSS, FedRAMP, ITAR, EAR, or any other regulated regime, you are responsible for ensuring your use of the Service complies with those obligations — we are not a HIPAA business associate, are not a PCI-compliant processor, and the Service is not authorized for processing protected health information, federal-tax information, or other regulated data."
                }

                legalSection("25. Apple App Store Addendum (REQUIRED)") {
                    "If you obtained the App through the Apple App Store, the following terms apply between you and Apple, Inc. (\"Apple\"): (a) these Terms are between you and Pulse only, not with Apple; Pulse alone is responsible for the App and its content; (b) the license granted in Section 10 is limited to use of the App on Apple-branded products you own or control, as permitted by Apple's Media Services Terms; (c) Apple has no obligation to provide maintenance or support; (d) in the event of any failure of the App to conform to any applicable warranty, you may notify Apple, and Apple will refund the purchase price; to the maximum extent permitted by law, Apple has no other warranty obligation; any other claims, losses, liabilities, damages, costs, or expenses are the sole responsibility of Pulse; (e) Pulse is responsible for addressing any product or third-party claims relating to the App; (f) in the event of any third-party intellectual-property infringement claim relating to the App, Pulse (not Apple) is solely responsible for the investigation, defense, settlement, and discharge of that claim; (g) you represent that you are not in a U.S.-embargoed country and are not on any U.S. or EU restricted-party list; (h) Apple and its subsidiaries are third-party beneficiaries of these Terms and may enforce them as related to your use of the App."
                }

                legalSection("26. Contact & Legal Notices") {
                    "All inquiries — general questions, legal notices, privacy & data-subject requests, DMCA notices, and arbitration opt-outs — go to a single address: meir56885@gmail.com\n\n\u{00A9} Pulse. All rights reserved."
                }
            }
            .padding(PulseSpacing.screenEdge)
            .padding(.bottom, PulseSpacing.section)
        }
        .pulseScreen()
        .navigationTitle("Terms of Use".localized)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legalSection(_ title: String, content: () -> String) -> some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text(title)
                .font(PulseTypography.labelLargeEmphasized)
                .foregroundColor(PulseColors.textPrimary)
            Text(content())
                .font(PulseTypography.bodySmall)
                .foregroundColor(PulseColors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func redBanner(_ text: String) -> some View {
        Text(text)
            .font(PulseTypography.labelLargeEmphasized)
            .foregroundColor(PulseColors.signal)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseColors.signal.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PulseSpacing.xl) {
                Text("Effective: June 2, 2026 \u{00B7} v2.2")
                    .font(PulseTypography.labelSmall)
                    .foregroundColor(PulseColors.textTertiary)

                LegalWebsiteLink(kind: .privacy)

                legalSection("Summary") {
                    "Your privacy matters. We collect only what we need to operate the Service, we never sell or share personal information for cross-context behavioral advertising, and we give you full control to access, port, correct, or delete your data at any time."
                }

                legalSection("1. Who We Are (Data Controller)") {
                    "The controller of your personal information is Pulse. Contact: meir56885@gmail.com — the same address handles general privacy, EEA/UK, and Brazilian (LGPD) DPO matters."
                }

                legalSection("2. Information We Collect") {
                    """
                    a) Account data — the Apple-provided identifier, the name and email (or Apple private-relay email) you choose to share via Sign in with Apple, and your account creation timestamp. We do not operate passwords or email/password accounts; authentication is handled entirely by Apple.
                    b) Goal data — goal titles, descriptions, categories, deadlines, motivation level, time-per-day, skill level, obstacles, AI-generated pulses and roadmaps, completion timestamps, progress notes, photos and free-text proof you attach.
                    c) AI chat — messages you send to the AI, AI responses, selected personality, and goal context.
                    d) Photos — any image you attach as proof or submit to Photo Transformation. Photos are transmitted to Google LLC (Gemini API) in transient memory for analysis only and are NOT retained on our servers after the response returns to your device. We do not perform biometric identification.
                    e) Device & diagnostic — device model, OS version, App version, time zone, locale, anonymized installation identifier, and aggregated, non-identifying crash diagnostics provided by Apple if you opt in.
                    f) Notification state — your on/off preference and the AI-determined local schedule.
                    g) Subscription state — your free or paid status as reported by Apple StoreKit (we do not see your payment-card data).
                    h) Camera (live workouts) — when you use the live form coach, the camera feed is analyzed entirely on your device using Apple's Vision framework to count reps and offer form hints. This video is never recorded, stored, or transmitted off your device, and no biometric identifiers are extracted from it.
                    """
                }

                legalSection("3. How We Use Information") {
                    """
                    • Operate, secure, and improve the Service.
                    • Generate AI-powered roadmaps, mentor responses, and photo analysis (transient processing).
                    • Send adaptive notifications based on your goals, streak, and deadline.
                    • Sync your data privately across your devices via Apple iCloud / CloudKit.
                    • Detect and prevent fraud, abuse, and violations of the Terms.
                    • Comply with legal obligations and respond to lawful requests.
                    We do NOT sell your personal information. We do NOT "share" personal information for cross-context behavioral advertising as defined under the California Privacy Rights Act. We do NOT use the Service for targeted advertising.
                    """
                }

                legalSection("4. Legal Bases (GDPR, UK GDPR, LGPD, Other)") {
                    """
                    • Performance of a contract — delivering the Service you signed up for.
                    • Your consent — for notifications and for photo-based features.
                    • Our legitimate interests — security, fraud prevention, product improvement (subject to your right to object).
                    • Legal obligation — compliance with applicable law.
                    For LGPD (Brazil): we additionally rely on the hipóteses set out in Art. 7 — execução de contrato, consentimento, legítimo interesse, cumprimento de obrigação legal e regulatória.
                    For India DPDP 2023: we rely on consent and legitimate uses where applicable.
                    """
                }

                legalSection("5. Categories of Recipients & Sub-Processors") {
                    """
                    We share data only with these categories of recipients, each bound to confidentiality:
                    • Google LLC (Gemini API) — AI inference for AI chat, roadmap generation, translation, and image (meal-scan and photo) analysis. Receives the prompt text, roadmap/translation requests, and any photo you submit; processed transiently and not retained by us.
                    • Cerebras, Inc. (api.cerebras.ai) — AI inference for free-tier AI chat, plan/roadmap generation, and related requests. Receives your goal and prompt text and any photo you submit on the free path; processed transiently and not retained by us.
                    • OpenRouter, Inc. (openrouter.ai) — AI inference for free-tier AI chat, plan/roadmap generation, and related requests. Receives your goal and prompt text and any photo you submit on the free path; processed transiently and not retained by us.
                    • Cloudflare, Inc. — operates the secure proxy that relays your AI requests (prompts and photos) to the AI providers above. It transmits these in transient memory and does not store them for us.
                    • Apple, Inc. — iCloud / CloudKit (your private database), App Store payments, Sign in with Apple, push notification routing.
                    • Our hosting and infrastructure providers (subject to confidentiality).
                    • Law-enforcement / government — only when legally required (with notice to you where lawful).
                    A current list of named sub-processors and their roles is available on request at meir56885@gmail.com.
                    """
                }

                legalSection("6. Sensitive / Special-Category Data") {
                    "We do not solicit sensitive personal information under CCPA/CPRA, special-category data under GDPR Art. 9, sensitive personal data under LGPD Art. 5(II), or sensitive data under India's DPDP Act 2023. If you voluntarily submit such information in free-text goals, notes, or AI chat, you do so at your own discretion; we will treat it confidentially but you should avoid disclosing more than necessary. We do not knowingly collect biometric identifiers."
                }

                legalSection("7. International Data Transfers") {
                    "Your information may be processed in the United States and other countries where our providers operate. For transfers from the EEA, UK, or Switzerland to the United States or other countries lacking an adequacy decision, we rely on the EU Standard Contractual Clauses (Commission Implementing Decision (EU) 2021/914) and equivalent UK and Swiss addenda. For transfers from Brazil we rely on the safeguards set out in LGPD Art. 33. We perform transfer-impact assessments where required."
                }

                legalSection("8. Retention") {
                    """
                    • Account data — until you delete your account (then deleted within 30 days, except where legal retention applies).
                    • Goal & mentor data — until you delete the goal or your account.
                    • Photos — discarded immediately after the AI response returns.
                    • Diagnostic logs — up to 90 days, then deleted.
                    • Backups — purged within 30 days of deletion request.
                    • Legal holds — we may retain data longer where required to comply with law or to defend legal claims.
                    """
                }

                legalSection("9. Security") {
                    "We use industry-standard technical and organizational measures: TLS 1.2+ in transit; iOS Data Protection at rest on your device; Keychain (Secure Enclave where available) for credentials; least-privilege access controls on the backend. Despite these measures, no internet transmission or storage is 100% secure. You are responsible for choosing a strong, unique password and securing your device."
                }

                legalSection("10. Your Rights — Universal Summary") {
                    """
                    Depending on your jurisdiction, you have one or more of the following rights:
                    • Access — copy of your personal information.
                    • Rectification — correct inaccurate or incomplete data.
                    • Deletion / erasure — request we erase your data.
                    • Portability — receive your data in a structured, commonly-used, machine-readable format.
                    • Object — to processing based on our legitimate interests, or to direct marketing.
                    • Restrict — request restriction of processing.
                    • Withdraw consent — for any processing based on consent.
                    • Non-discrimination — we will not retaliate for exercising any right.
                    Exercise any right via Profile → Your Data or by emailing meir56885@gmail.com. We respond within 30 days (extendable to 60 in complex cases under GDPR). You also have the right to complain to your data-protection authority (e.g., ICO in the UK, CNIL in France, AEPD in Spain, Garante in Italy, ANPD in Brazil, OAIC in Australia, OPC in Canada, PIPC in South Korea, PPC in Japan).
                    """
                }

                legalSection("11. California (CCPA / CPRA) Notice at Collection") {
                    """
                    Categories of personal information collected in the past 12 months: identifiers (email, account ID); internet activity (App usage); inferences (goal progress patterns); user-generated content (goals, notes, photos). Purpose: providing and improving the Service.
                    We do NOT sell personal information and do NOT share for cross-context behavioral advertising. There is therefore no "Do Not Sell or Share My Personal Information" link required — but you may still request access, deletion, correction, or limitation of sensitive PI use via meir56885@gmail.com.
                    Sensitive personal information collected: none. We do not retain or use sensitive PI for purposes other than those permitted by 11 CCR § 7027(m).
                    Retention periods: see Section 8.
                    Right to limit: as we do not use sensitive PI for inferring characteristics, no limitation right applies.
                    Authorized agents may submit requests on your behalf with proof of authorization.
                    """
                }

                legalSection("12. EEA / UK / Switzerland (GDPR)") {
                    "If you are in the EEA, the UK, or Switzerland: you have rights under GDPR, UK GDPR, and the Swiss FADP. Lawful bases are listed in Section 4. The controller is Pulse. The Service does not engage in automated decision-making producing legal or similarly significant effects on you. You may lodge a complaint with your supervisory authority. Our EU representative under GDPR Art. 27 (if and when designated) can be requested at meir56885@gmail.com."
                }

                legalSection("13. United Kingdom") {
                    "UK GDPR + Data Protection Act 2018 apply. Our UK representative (if designated) can be requested at meir56885@gmail.com. You may complain to the Information Commissioner's Office (ico.org.uk)."
                }

                legalSection("14. Canada (PIPEDA + Quebec Law 25)") {
                    "Pulse complies with the Personal Information Protection and Electronic Documents Act and Quebec's Act Respecting the Protection of Personal Information in the Private Sector (Law 25). Quebec residents have rights to data portability, deindexation, and notification of automated decision-making (we do not engage in qualifying ADM)."
                }

                legalSection("15. Brazil (LGPD)") {
                    "Pulse processes personal data of Brazilian residents in accordance with the Lei Geral de Proteção de Dados (Lei 13,709/2018). Lawful bases are described above. You may exercise LGPD rights (Art. 18) via meir56885@gmail.com. Brazilian DPO contact: meir56885@gmail.com. You may file a complaint with the Autoridade Nacional de Proteção de Dados (ANPD)."
                }

                legalSection("16. Other Jurisdictions") {
                    """
                    We respect, and process data in accordance with, applicable data-protection laws including:
                    • Australia — Privacy Act 1988 and Australian Privacy Principles.
                    • New Zealand — Privacy Act 2020.
                    • India — Digital Personal Data Protection Act 2023.
                    • Japan — Act on the Protection of Personal Information (APPI).
                    • South Korea — Personal Information Protection Act (PIPA).
                    • China — Personal Information Protection Law (PIPL) — note that Service availability in mainland China may be limited.
                    • Singapore — Personal Data Protection Act (PDPA).
                    • Hong Kong — Personal Data (Privacy) Ordinance (PDPO).
                    • UAE — Federal Decree-Law 45/2021.
                    • Saudi Arabia — Personal Data Protection Law.
                    • South Africa — Protection of Personal Information Act (POPIA).
                    • Nigeria — Nigeria Data Protection Regulation (NDPR).
                    • Israel — Protection of Privacy Law 5741-1981.
                    Local rights provided by these laws are available to residents of the respective jurisdictions; contact meir56885@gmail.com to exercise them.
                    """
                }

                legalSection("17. Children's Privacy (COPPA, GDPR-K, etc.)") {
                    "The Service is not directed to children under 13 (or under 16 in the EEA Member States that have set 16 as the digital-services consent age). We do not knowingly collect personal information from children below the applicable age. If you believe a child has provided us personal information, contact meir56885@gmail.com and we will delete it without undue delay."
                }

                legalSection("18. Marketing & Anti-Spam") {
                    "We do not currently send marketing emails. If we do in future, you will be able to unsubscribe via a link in every message. We comply with CAN-SPAM (US), CASL (Canada), the Spam Act 2003 (Australia), the ePrivacy Directive (EU), and applicable laws."
                }

                legalSection("19. Cookies / Tracking Technologies") {
                    "The mobile App does not use cookies. We do not embed any analytics SDKs, advertising SDKs, fingerprinting libraries, or cross-app tracking technologies. We do not engage in tracking as defined by the Apple App Tracking Transparency framework. Live-workout pose detection runs on-device via Apple's Vision framework; that video is never uploaded."
                }

                legalSection("20. Automated Decision-Making") {
                    "AI output (roadmaps, probabilities, coach messages) is generated automatically but does NOT produce legal or similarly significant effects on you within the meaning of GDPR Art. 22 or analogous laws. You may disregard, modify, or delete any AI output at any time. We do not engage in solely-automated profiling that has legal effect."
                }

                legalSection("21. Data Breach Notification") {
                    "In the event of a personal-data breach likely to result in a risk to your rights or freedoms, we will notify the competent supervisory authority within the timeframes required by applicable law (e.g., 72 hours under GDPR Art. 33) and will notify affected individuals where required."
                }

                legalSection("22. Changes to This Policy") {
                    "We may update this Privacy Policy from time to time. Material changes will be disclosed in-App with a revised \"Effective\" date. Continued use of the Service after the effective date constitutes acceptance of the revised Policy."
                }

                legalSection("23. Contact") {
                    "All privacy questions, complaints, and rights requests — including EEA/UK/Swiss and Brazilian (LGPD) Data Protection Officer matters and US legal notices — go to a single address: meir56885@gmail.com"
                }
            }
            .padding(PulseSpacing.screenEdge)
            .padding(.bottom, PulseSpacing.section)
        }
        .pulseScreen()
        .navigationTitle("Privacy Policy".localized)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legalSection(_ title: String, content: () -> String) -> some View {
        VStack(alignment: .leading, spacing: PulseSpacing.sm) {
            Text(title)
                .font(PulseTypography.labelLargeEmphasized)
                .foregroundColor(PulseColors.textPrimary)
            Text(content())
                .font(PulseTypography.bodySmall)
                .foregroundColor(PulseColors.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
