import os
import re
import base64
import subprocess
import markdown

WORKSPACE = r"G:\gdownloads\FairMetaChain-Pilot (1)\FairMetaChain-Pilot"
BOOK_MD_PATH = os.path.join(WORKSPACE, "FAIRMETACHAIN_THESIS_BOOK.md")
GRAPHS_DIR = os.path.join(WORKSPACE, "graphs")
HTML_OUT = os.path.join(WORKSPACE, "thesis_dissertation.html")
PDF_OUT = os.path.join(WORKSPACE, "FairMetaChain_Thesis_Dissertation.pdf")
CHROME_PATH = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

def load_image_b64(filename):
    path = os.path.join(GRAPHS_DIR, filename)
    if os.path.exists(path):
        with open(path, "rb") as f:
            data = base64.b64encode(f.read()).decode("utf-8")
            return f"data:image/png;base64,{data}"
    return ""

def format_math(text):
    # Inline math $...$
    text = re.sub(r'(?<!\\)\$([^\$\n]+?)\$', r'<span class="inline-math"><i>\1</i></span>', text)
    # Display math $$...$$
    text = re.sub(r'\$\$([^\$]+?)\$\$', r'<div class="display-math">\1</div>', text)
    # LaTeX replacements
    replacements = [
        (r'\\phi', '&phi;'),
        (r'\\alpha', '&alpha;'),
        (r'\\cdot', '&middot;'),
        (r'\\sum', '&sum;'),
        (r'\\in', '&isin;'),
        (r'\\le', '&le;'),
        (r'\\ge', '&ge;'),
        (r'\\times', '&times;'),
        (r'\\approx', '&asymp;'),
        (r'\\nabla', '&nabla;'),
        (r'\\frac\{([^}]+)\}\{([^}]+)\}', r'(\1 / \2)'),
        (r'_\{([^}]+)\}', r'<sub>\1</sub>'),
        (r'\^\{([^}]+)\}', r'<sup>\1</sup>'),
        (r'_([a-zA-Z0-9])', r'<sub>\1</sub>'),
        (r'\^([a-zA-Z0-9])', r'<sup>\1</sup>'),
    ]
    for pattern, repl in replacements:
        text = re.sub(pattern, repl, text)
    return text

def main():
    print("Reading markdown thesis book...")
    with open(BOOK_MD_PATH, "r", encoding="utf-8") as f:
        md_text = f.read()

    # Pre-process math
    md_text = format_math(md_text)

    # Encode all 6 thesis graphs
    img1 = load_image_b64("01_thesis_fairness_comparison.png")
    img2 = load_image_b64("02_thesis_sybil_comparison.png")
    img3 = load_image_b64("03_thesis_gas_comparison.png")
    img4 = load_image_b64("04_thesis_rebate_sybil_defense.png")
    img5 = load_image_b64("05_thesis_3d_reward_surface.png")
    img6 = load_image_b64("06_thesis_comprehensive_proof_dashboard.png")

    # Define sequential figure blocks
    fig1_html = f'''
<div class="figure-box">
    <img src="{img5}" alt="Figure 1: 3D Equilibrium Reward Surface" />
    <div class="figure-caption"><strong>Figure 1: 3D Follower Equilibrium Reward Surface.</strong> Node equilibrium payoff manifold plotted as a function of contributed computing units ($R_n$) and dynamic reputation multiplier (&phi; &isin; [0.2, 1.0]) under a 35% fairness ceiling. The non-linear surface proves that excessive whale allocation is flattened, while preserving marginal incentives for edge devices with high historical reliability.</div>
</div>
'''

    fig2_html = f'''
<div class="figure-box">
    <img src="{img6}" alt="Figure 2: Master Comprehensive Proof Dashboard" />
    <div class="figure-caption"><strong>Figure 2: Master Comprehensive Proof & Empirical Dashboard.</strong> Multi-metric empirical validation across six core dimensions: (a) Jain's Fairness Index progression across contract iterations (V1 to V6), (b) identity splitting net utility proving that Sybils incur a net financial loss, (c) EVM execution gas benchmarks for state packing and batch claims, (d) 1-wei dust transaction rebate denial, (e) 3D Stackelberg reward equilibrium surface, and (f) decentralized TEE remote attestation work receipt validation.</div>
</div>
'''

    fig3_html = f'''
<div class="figure-box">
    <img src="{img1}" alt="Figure 3: Fairness & Wealth Distribution Across Generations" />
    <div class="figure-caption"><strong>Figure 3: Fairness & Wealth Distribution Across System Generations.</strong> Comparison of reward distribution among heterogeneous nodes ($U_1$ to $U_4$) across V1, V2, V3, and V6. Under the baseline MetaChain pay-per-share model, whale node $U_4$ monopolized 57.14% of rewards. FairMetaChain V6 redistributes excess capacity to edge nodes, elevating Jain's Fairness Index from 0.648 to 0.852 (+31.4% improvement).</div>
</div>
'''

    fig4_html = f'''
<div class="figure-box">
    <img src="{img2}" alt="Figure 4: Sybil Attack Net Utility & Identity Splitting Penalty" />
    <div class="figure-caption"><strong>Figure 4: Sybil Attack Net Utility & Identity Splitting Penalty.</strong> Empirical proof of Dual-Mode Sybil Neutrality. A single honest node earns +8.34 FMC net profit, while an attacker splitting the identical compute capacity into 4 distinct accounts incurs -1.20 FMC net loss due to recycled entry fees and reputation warm-up haircuts (net penalty of -9.54 FMC).</div>
</div>
'''

    fig5_html = f'''
<div class="figure-box">
    <img src="{img3}" alt="Figure 5: EVM Gas Efficiency Profiling & Storage Optimization" />
    <div class="figure-caption"><strong>Figure 5: EVM Gas Consumption & Storage Slot Optimization Profiling.</strong> Execution gas breakdown across core contract functions. EVM storage slot packing cuts contribution gas by 28.2% (208,402 vs 290,140 gas), while multi-shard multi-epoch batch claims reduce settlement overhead by 39.2% (256,036 gas for 3 shards vs 421,260 gas for individual claims).</div>
</div>
'''

    fig6_html = f'''
<div class="figure-box">
    <img src="{img4}" alt="Figure 6: Proportional Gas Rebate Allocation & Dust Attack Neutralization" />
    <div class="figure-caption"><strong>Figure 6: Proportional Gas Rebate Allocation & Dust Attack Neutralization.</strong> Distribution of the 40% progressive gas rebate pool. Under FairMetaChain V6's proportional weighting ($R_n = R_{{pool}} \cdot g_n / G_{{total}}$), honest nodes paying legitimate transaction gas receive 100% of the rebate, while 1-wei dust Sybil transactions receive strictly 0 FMC rebate.</div>
</div>
'''

    # Insert figures into corresponding sections in sequential reading order
    if "#### 3.6.1 Continuous EMA Reputation Dynamics" in md_text:
        md_text = md_text.replace("#### 3.6.1 Continuous EMA Reputation Dynamics", "#### 3.6.1 Continuous EMA Reputation Dynamics\n\n" + fig1_html)
    if "### 5.1 Experimental Setup" in md_text:
        md_text = md_text.replace("### 5.1 Experimental Setup", fig2_html + "\n\n### 5.1 Experimental Setup")
    if "### 5.2 Fairness & Wealth Distribution Evaluation" in md_text:
        md_text = md_text.replace("### 5.2 Fairness & Wealth Distribution Evaluation", "### 5.2 Fairness & Wealth Distribution Evaluation\n\n" + fig3_html)
    if "### 5.3 Sybil Attack Profitability & Economic Security Analysis" in md_text:
        md_text = md_text.replace("### 5.3 Sybil Attack Profitability & Economic Security Analysis", "### 5.3 Sybil Attack Profitability & Economic Security Analysis\n\n" + fig4_html)
    if "### 5.4 Gas Consumption & EVM Storage Efficiency Profiling" in md_text:
        md_text = md_text.replace("### 5.4 Gas Consumption & EVM Storage Efficiency Profiling", "### 5.4 Gas Consumption & EVM Storage Efficiency Profiling\n\n" + fig5_html)
    if "### 5.5 Proportional Gas Rebate Pool Defense Against Dust Exploits" in md_text:
        md_text = md_text.replace("### 5.5 Proportional Gas Rebate Pool Defense Against Dust Exploits", "### 5.5 Proportional Gas Rebate Pool Defense Against Dust Exploits\n\n" + fig6_html)

    # Convert Markdown to HTML
    print("Converting Markdown to HTML...")
    html_body = markdown.markdown(
        md_text,
        extensions=['tables', 'fenced_code', 'toc', 'nl2br']
    )

    full_html = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>FairMetaChain: A Blockchain-Based Fair Resource Allocation Framework for Metaverse Applications</title>
<style>
    @page {{
        size: A4 portrait;
        margin: 22mm 18mm 22mm 18mm;
        @top-right {{
            content: "FairMetaChain: A Fair Resource Allocation Framework";
            font-family: 'Times New Roman', Times, serif;
            font-size: 8pt;
            color: #64748b;
            font-style: italic;
        }}
        @bottom-center {{
            content: "- " counter(page) " -";
            font-family: 'Times New Roman', Times, serif;
            font-size: 9pt;
            color: #334155;
        }}
    }}

    @page :first {{
        @top-right {{ content: normal; }}
        @bottom-center {{ content: normal; }}
    }}

    body {{
        font-family: 'Times New Roman', Times, 'Nimbus Roman No9 L', serif;
        font-size: 11pt;
        line-height: 1.55;
        color: #1e293b;
        margin: 0;
        padding: 0;
        text-align: justify;
    }}

    /* Title Page */
    .title-page {{
        text-align: center;
        page-break-after: always;
        padding-top: 60px;
    }}
    .thesis-pretitle {{
        font-size: 12pt;
        letter-spacing: 2.5px;
        color: #475569;
        margin-bottom: 25px;
        text-transform: uppercase;
        font-weight: 600;
    }}
    .thesis-title {{
        font-size: 23pt;
        font-weight: bold;
        line-height: 1.25;
        margin-bottom: 22px;
        color: #0f172a;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }}
    .thesis-subtitle {{
        font-size: 13pt;
        font-style: italic;
        color: #334155;
        margin-bottom: 40px;
        line-height: 1.45;
        max-width: 85%;
        margin-left: auto;
        margin-right: auto;
    }}
    .divider-rule {{
        width: 60%;
        border: 0;
        border-top: 1.5px solid #0f172a;
        margin: 40px auto;
    }}
    .thesis-meta {{
        font-size: 11.5pt;
        line-height: 1.8;
    }}
    .thesis-author {{
        font-size: 15pt;
        font-weight: bold;
        color: #0f172a;
        margin-bottom: 5px;
    }}
    .thesis-affiliation {{
        font-size: 11pt;
        color: #475569;
        margin-bottom: 40px;
    }}
    .thesis-badge {{
        display: inline-block;
        padding: 8px 18px;
        background: #f1f5f9;
        border: 1px solid #cbd5e1;
        border-radius: 4px;
        font-family: 'Consolas', monospace;
        font-size: 10pt;
        color: #0f172a;
        margin-top: 40px;
    }}

    /* Abstract Block */
    .abstract-box {{
        margin: 25px 0 35px 0;
        padding: 24px 28px;
        background-color: #f8fafc;
        border-left: 4.5px solid #1e3a8a;
        border-right: 1px solid #cbd5e1;
        border-top: 1px solid #cbd5e1;
        border-bottom: 1px solid #cbd5e1;
        page-break-after: always;
    }}
    .abstract-title {{
        text-align: center;
        font-weight: bold;
        font-size: 14pt;
        margin-bottom: 16px;
        letter-spacing: 1.5px;
        color: #0f172a;
    }}
    .keywords {{
        margin-top: 18px;
        font-size: 10pt;
        line-height: 1.4;
        color: #1e293b;
    }}

    /* Headings */
    h1 {{
        font-size: 18pt;
        font-weight: bold;
        color: #0f172a;
        margin-top: 35px;
        margin-bottom: 15px;
        border-bottom: 2px solid #0f172a;
        padding-bottom: 6px;
        page-break-before: always;
    }}
    h2 {{
        font-size: 13.5pt;
        font-weight: bold;
        color: #1e293b;
        margin-top: 25px;
        margin-bottom: 10px;
        border-bottom: 1px solid #cbd5e1;
        padding-bottom: 3px;
    }}
    h3 {{
        font-size: 12pt;
        font-weight: bold;
        color: #334155;
        margin-top: 18px;
        margin-bottom: 8px;
    }}
    h4 {{
        font-size: 11pt;
        font-weight: bold;
        font-style: italic;
        color: #475569;
        margin-top: 14px;
        margin-bottom: 6px;
    }}

    p {{
        margin-top: 0;
        margin-bottom: 11px;
    }}
    ul, ol {{
        margin-top: 0;
        margin-bottom: 12px;
        padding-left: 24px;
    }}
    li {{
        margin-bottom: 4px;
    }}

    /* Publication Table Styling */
    table {{
        width: 100%;
        border-collapse: collapse;
        margin: 18px 0;
        font-size: 9.5pt;
        page-break-inside: avoid;
    }}
    th {{
        background-color: #0f172a;
        color: #ffffff;
        font-weight: bold;
        padding: 8px 10px;
        text-align: left;
        border: 1px solid #0f172a;
    }}
    td {{
        padding: 7px 10px;
        border: 1px solid #cbd5e1;
        color: #1e293b;
    }}
    tr:nth-child(even) td {{
        background-color: #f8fafc;
    }}

    /* Figures */
    .figure-box {{
        margin: 22px auto;
        text-align: center;
        page-break-inside: avoid;
    }}
    .figure-box img {{
        max-width: 95%;
        height: auto;
        border: 1px solid #cbd5e1;
        border-radius: 4px;
        box-shadow: 0 2px 6px rgba(0,0,0,0.06);
    }}
    .figure-caption {{
        font-size: 9.5pt;
        color: #334155;
        margin-top: 9px;
        text-align: justify;
        padding: 0 10px;
        line-height: 1.35;
    }}

    /* Math */
    .display-math {{
        text-align: center;
        font-family: 'Cambria Math', 'Times New Roman', serif;
        font-size: 11.5pt;
        margin: 12px 0;
        padding: 8px;
        background: #fbfcfe;
        border-radius: 4px;
        page-break-inside: avoid;
    }}
    .inline-math {{
        font-family: 'Cambria Math', 'Times New Roman', serif;
        font-size: 11pt;
    }}

    /* Code blocks */
    pre {{
        background-color: #0f172a;
        color: #e2e8f0;
        padding: 12px 14px;
        border-radius: 5px;
        font-family: 'Consolas', 'Courier New', monospace;
        font-size: 8.5pt;
        line-height: 1.35;
        overflow-x: auto;
        margin: 14px 0;
        page-break-inside: avoid;
    }}
    code {{
        font-family: 'Consolas', 'Courier New', monospace;
        font-size: 9pt;
        background-color: #f1f5f9;
        padding: 2px 5px;
        border-radius: 3px;
        color: #0f172a;
    }}
    pre code {{
        background-color: transparent;
        padding: 0;
        color: #e2e8f0;
    }}

    blockquote {{
        margin: 14px 0;
        padding: 10px 16px;
        background-color: #f8fafc;
        border-left: 4px solid #3b82f6;
        color: #334155;
        font-style: italic;
    }}

    a {{
        color: #1d4ed8;
        text-decoration: none;
    }}
    a:hover {{
        text-decoration: underline;
    }}
</style>
</head>
<body>

<!-- COVER / TITLE PAGE -->
<div class="title-page">
    <div class="thesis-pretitle">
        Academic Dissertation &bull; Master of Science Research Thesis
    </div>
    <div class="thesis-title">
        FAIRMETACHAIN: A BLOCKCHAIN-BASED FAIR RESOURCE ALLOCATION FRAMEWORK FOR METAVERSE APPLICATIONS
    </div>
    <div class="thesis-subtitle">
        A Game-Theoretic, Cryptographically Verified, and Gas-Efficient Infrastructure for Scalable Decentralized Spatial Computing
    </div>

    <hr class="divider-rule" />

    <div class="thesis-meta">
        <div style="font-size: 11pt; color: #64748b; margin-bottom: 6px;">Author & Principal Researcher:</div>
        <div class="thesis-author">Nahida Sultana</div>
        <div class="thesis-affiliation">
            Department of Computer Science & Engineering<br />
            Specialization: Distributed Systems, Game Theory & Blockchain Architecture
        </div>

        <div style="margin-top: 35px; font-size: 11pt; color: #475569;">
            <strong>Primary Publication Repository:</strong><br />
            <a href="https://github.com/Nahida-sultana/thesis_adaptive_chain">https://github.com/Nahida-sultana/thesis_adaptive_chain</a>
        </div>

        <div style="margin-top: 30px; font-size: 10pt; color: #64748b;">
            Date of Final Submission: <strong>October 2026</strong><br />
            Comparative Baseline: IEEE VTC-2022 MetaChain Architecture
        </div>

        <div class="thesis-badge">
            Smart Contract Generation: FairMetaChain V6 (Production Edition)
        </div>
    </div>
</div>

<!-- FORMAL RESEARCH ABSTRACT -->
<div class="abstract-box">
    <div class="abstract-title">ABSTRACT</div>
    <p>
        The rapid evolution of persistent synthetic realities and Metaverse environments has catalyzed unprecedented demand for scalable, low-latency, and decentralized edge computing infrastructure. To coordinate heterogeneous computational resources across decentralized Metaverse shards, existing literature—most notably the foundational MetaChain framework (IEEE VTC-2022)—employs a two-stage Stackelberg game with a pure pay-per-share reward mechanism. However, comprehensive empirical and game-theoretic analysis reveals four critical structural failures in the baseline architecture: (1) <strong>Whale Monopolization</strong>, where high-capacity nodes capture upwards of 90% of the epoch rewards, starving resource-constrained edge contributors; (2) the <strong>Fairness-Sybil Dilemma</strong>, wherein naive fairness caps inadvertently reward identity-splitting attackers with up to 1.75&times; higher profit; (3) <strong>Uncontrolled Transaction Congestion</strong>, arising from the complete absence of dynamic gas economics and progressive rebates; and (4) <strong>Vulnerability to Compute Spoofing</strong>, caused by reliance on unverified, self-reported resource claims.
    </p>
    <p>
        To address and overcome these fundamental limitations, this dissertation designs, implements, and evaluates <strong>FairMetaChain</strong>, a unified game-theoretic and cryptographically verified resource allocation framework. FairMetaChain introduces a 35% fair-share allocation ceiling modulated by continuous Exponential Moving Average (EMA) reputation dynamics (&phi; &isin; [0.2, 1.0]), systematically elevating edge node viability. To resolve the Fairness-Sybil Dilemma, we construct a <em>Dual-Mode Sybil Neutrality</em> defense integrating Trusted Execution Environment (TEE) hardware remote attestations (Intel SGX / AMD SEV), non-refundable recycled entrance fees (5 FMC), and reputation warm-up haircuts. We theoretically prove and empirically demonstrate that identity splitting yields a strictly negative net utility (&minus;1.20 FMC vs. +8.34 FMC for honest nodes; a net penalty of &minus;9.54 FMC). Furthermore, FairMetaChain establishes a dynamic per-shard gas model coupled with a 40% progressive gas rebate pool distributed strictly proportional to gas paid, rendering 1-wei dust transaction exploits completely unprofitable.
    </p>
    <p>
        The framework is fully implemented across six iterative smart contract generations (V1 to V6) written in Solidity 0.8.20, featuring EVM storage slot packing (28.2% gas savings), multi-epoch atomic batch claims (39.2% gas savings), off-chain cryptographic work receipts (<code>contributeWithProof</code>), and autonomous Chainlink-compatible keeper orchestration. Rigorous Hardhat EVM benchmarks across 11 heterogeneous node classes validate that FairMetaChain improves Jain's Fairness Index by <strong>31.4%</strong> (from 0.648 to 0.852), eliminates compute spoofing, and achieves trustless, operator-free epoch progression.
    </p>
    <div class="keywords">
        <strong>Keywords:</strong> Metaverse Computing, Blockchain Sharding, Resource Allocation, Stackelberg Game, Sybil Resistance, Trusted Execution Environments, Smart Contract Optimization, Gas Economics, Jain's Fairness Index.
    </div>
</div>

<!-- BODY -->
{html_body}

</body>
</html>
'''

    print("Writing enhanced HTML file...")
    with open(HTML_OUT, "w", encoding="utf-8") as f:
        f.write(full_html)
    print(f"HTML written to {HTML_OUT}")

    print("Compiling PDF with Google Chrome Headless...")
    cmd = [
        CHROME_PATH,
        "--headless=new",
        "--no-sandbox",
        "--disable-gpu",
        "--run-all-compositor-stages-before-draw",
        f"--print-to-pdf={PDF_OUT}",
        HTML_OUT
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    print("Chrome return code:", res.returncode)
    if os.path.exists(PDF_OUT):
        size_kb = os.path.getsize(PDF_OUT) / 1024
        print(f"SUCCESS: Generated PDF at {PDF_OUT} ({size_kb:.2f} KB)")
    else:
        print("ERROR: PDF was not generated. Stderr:", res.stderr)

if __name__ == "__main__":
    main()
