"""
EdgeMATX Presentation Generator
Produces: EdgeMATX_presentation.pptx
Run: python generate_ppt.py
"""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.oxml.ns import qn
from pptx.chart.data import ChartData
from pptx.enum.chart import XL_CHART_TYPE
from lxml import etree
import os

# ── THEME ─────────────────────────────────────────────────────────────────────
BG     = RGBColor(0x0B, 0x14, 0x2A)
CARD   = RGBColor(0x14, 0x21, 0x3E)
CARD2  = RGBColor(0x1E, 0x2D, 0x4F)
CYAN   = RGBColor(0x00, 0xD4, 0xFF)
ORANGE = RGBColor(0xFF, 0x6B, 0x35)
GREEN  = RGBColor(0x00, 0xDC, 0x75)
WHITE  = RGBColor(0xFF, 0xFF, 0xFF)
GRAY   = RGBColor(0x90, 0xA4, 0xB8)
YELLOW = RGBColor(0xFB, 0xBF, 0x24)
PINK   = RGBColor(0xF0, 0x6A, 0xC8)
RED    = RGBColor(0xFF, 0x4D, 0x4D)

W = Inches(13.333)
H = Inches(7.5)

# ── CORE HELPERS ──────────────────────────────────────────────────────────────

def make_prs():
    prs = Presentation()
    prs.slide_width  = W
    prs.slide_height = H
    return prs

def blank(prs):
    return prs.slides.add_slide(prs.slide_layouts[6])

def set_bg(slide, color=BG):
    fill = slide.background.fill
    fill.solid()
    fill.fore_color.rgb = color

def box(slide, text, l, t, w, h, size=22, bold=False,
        color=WHITE, align=PP_ALIGN.LEFT, italic=False):
    tb = slide.shapes.add_textbox(l, t, w, h)
    tf = tb.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.alignment = align
    run = p.add_run()
    run.text = text
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.italic = italic
    run.font.color.rgb = color
    return tb

def add_para(tf, text, size=18, bold=False, color=WHITE,
             align=PP_ALIGN.LEFT, italic=False, before=0):
    p = tf.add_paragraph()
    p.alignment = align
    if before:
        p.space_before = Pt(before)
    r = p.add_run()
    r.text = text
    r.font.size = Pt(size)
    r.font.bold = bold
    r.font.italic = italic
    r.font.color.rgb = color
    return p

def rect(slide, l, t, w, h, fill=CARD, line=None, lw=Pt(1.5), radius=False):
    shape = slide.shapes.add_shape(1, l, t, w, h)
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill
    if line:
        shape.line.color.rgb = line
        shape.line.width = lw
    else:
        shape.line.fill.background()
    return shape

def hrule(slide, l, t, w, color=CYAN, thick=Pt(2)):
    s = slide.shapes.add_shape(1, l, t, w, thick)
    s.fill.solid()
    s.fill.fore_color.rgb = color
    s.line.fill.background()
    return s

def header(slide, title, sub=None):
    box(slide, title,
        Inches(0.45), Inches(0.12), Inches(12.5), Inches(0.75),
        size=34, bold=True, color=CYAN)
    hrule(slide, Inches(0.45), Inches(0.9), Inches(12.4))
    if sub:
        box(slide, sub,
            Inches(0.45), Inches(0.92), Inches(12.4), Inches(0.45),
            size=15, color=GRAY)

def footer(slide, text="EdgeMATX  ·  NITK Surathkal  ·  ECE Department  ·  2026"):
    box(slide, text,
        Inches(0.45), Inches(7.12), Inches(12.4), Inches(0.32),
        size=11, color=GRAY)

def pill(slide, l, t, label, fill=CYAN, text_col=BG):
    """Small coloured badge/pill."""
    r = rect(slide, l, t, Inches(1.8), Inches(0.42), fill=fill)
    box(slide, label, l, t + Inches(0.07),
        Inches(1.8), Inches(0.35), size=13, bold=True,
        color=text_col, align=PP_ALIGN.CENTER)
    return r

# ── ANIMATION HELPER ──────────────────────────────────────────────────────────

def add_click_animations(slide, shape_ids, preset=10, delay_ms=0):
    """
    Add on-click fade-in (preset=10) or appear (preset=1) entrance
    animations to a list of shape IDs.
    """
    p_ns = "http://schemas.openxmlformats.org/presentationml/2006/main"
    base_id = 3

    seq_children = ""
    for i, spid in enumerate(shape_ids):
        oid = base_id + i * 5
        seq_children += f"""
        <p:par xmlns:p="{p_ns}">
          <p:cTn id="{oid}" fill="hold">
            <p:stCondLst><p:cond evt="onBegin" delay="indefinite"/></p:stCondLst>
            <p:childTnLst>
              <p:par>
                <p:cTn id="{oid+1}" presetID="{preset}" presetClass="entr"
                       presetSubtype="0" fill="hold" grpId="{i}"
                       nodeType="clickEffect">
                  <p:stCondLst><p:cond delay="{delay_ms}"/></p:stCondLst>
                  <p:childTnLst>
                    <p:set>
                      <p:cBhvr>
                        <p:cTn id="{oid+2}" dur="500" fill="hold"/>
                        <p:tgtEl><p:spTgt spid="{spid}"/></p:tgtEl>
                        <p:attrNameLst>
                          <p:attrName>style.visibility</p:attrName>
                        </p:attrNameLst>
                      </p:cBhvr>
                      <p:to><p:strVal val="visible"/></p:to>
                    </p:set>
                  </p:childTnLst>
                </p:cTn>
              </p:par>
            </p:childTnLst>
          </p:cTn>
        </p:par>"""

    xml = f"""<p:timing xmlns:p="{p_ns}">
  <p:tnLst>
    <p:par>
      <p:cTn id="1" dur="indefinite" restart="whenNotActive" nodeType="tmRoot">
        <p:childTnLst>
          <p:seq concurrent="1" nextAc="seek">
            <p:cTn id="2" dur="indefinite" nodeType="mainSeq">
              <p:childTnLst>{seq_children}
              </p:childTnLst>
            </p:cTn>
            <p:prevCondLst>
              <p:cond evt="onBegin" delay="0"><p:tn/></p:cond>
            </p:prevCondLst>
          </p:seq>
        </p:childTnLst>
      </p:cTn>
    </p:par>
  </p:tnLst>
</p:timing>"""
    slide.element.append(etree.fromstring(xml))

def add_transition(slide, dur_ms=700, t_type="fade"):
    """Add a slide transition."""
    p_ns = "http://schemas.openxmlformats.org/presentationml/2006/main"
    xml = f'<p:transition xmlns:p="{p_ns}" spd="med" dur="{dur_ms}"><p:{t_type}/></p:transition>'
    slide.element.append(etree.fromstring(xml))

# ═══════════════════════════════════════════════════════════════════════════════
# SLIDES
# ═══════════════════════════════════════════════════════════════════════════════

# ── SLIDE 1: TITLE ────────────────────────────────────────────────────────────
def slide_title(prs):
    s = blank(prs)
    set_bg(s)

    # Left accent stripe
    rect(s, Inches(0), Inches(0), Inches(0.12), H, fill=CYAN)

    # Decorative top bar
    rect(s, Inches(0.12), Inches(0), W, Inches(0.06), fill=ORANGE)

    # Large project acronym
    box(s, "EdgeMATX",
        Inches(0.7), Inches(0.7), Inches(9), Inches(1.6),
        size=80, bold=True, color=CYAN)

    # Full title
    box(s, "Design and Integration of a TinyML Systolic\nAccelerator with PicoRV32",
        Inches(0.7), Inches(2.3), Inches(8.8), Inches(1.3),
        size=26, color=WHITE)

    hrule(s, Inches(0.7), Inches(3.65), Inches(8.5), color=ORANGE, thick=Pt(1.5))

    # Team block
    tb = slide.shapes.add_textbox(Inches(0.7), Inches(3.8), Inches(6), Inches(1.6)) if False else \
         s.shapes.add_textbox(Inches(0.7), Inches(3.8), Inches(6), Inches(1.6))
    tf = tb.text_frame; tf.word_wrap = True
    add_para(tf, "Submitted by", 13, italic=True, color=GRAY)
    for name in ["Nishchay Pallav  221EC233",
                 "Mohammad Omar Sulemani  221EC230",
                 "Md Atib Kaif  221EC129"]:
        add_para(tf, name, 17, bold=True, color=WHITE, before=2)

    # Guide
    box(s, "Under the Guidance of  Dr Rathamala Rao",
        Inches(0.7), Inches(5.5), Inches(7), Inches(0.45),
        size=15, color=GRAY)

    # Institution
    box(s, "Dept. of Electronics & Communication Engineering\nNational Institute of Technology Karnataka, Surathkal — 575025",
        Inches(0.7), Inches(6.1), Inches(9), Inches(0.8),
        size=13, color=GRAY)

    # Right side: stats panel
    panel = rect(s, Inches(10.0), Inches(1.5), Inches(3.0), Inches(4.5),
                 fill=CARD, line=CYAN, lw=Pt(1))

    for i, (val, lbl, col) in enumerate([
        ("673",    "Cycles",        CYAN),
        ("54×",    "Peak Speedup",  GREEN),
        ("19/19",  "Tests Pass",    ORANGE),
        ("4×4",    "Systolic Array",YELLOW),
    ]):
        y = Inches(1.7) + i * Inches(1.05)
        box(s, val, Inches(10.15), y, Inches(2.7), Inches(0.58),
            size=30, bold=True, color=col, align=PP_ALIGN.CENTER)
        box(s, lbl, Inches(10.15), y + Inches(0.52), Inches(2.7), Inches(0.38),
            size=12, color=GRAY, align=PP_ALIGN.CENTER)

    add_transition(s)
    return s

# ── SLIDE 2: THE PROBLEM ──────────────────────────────────────────────────────
def slide_problem(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "The Problem", "Matrix multiplication is ubiquitous — and painfully slow on embedded CPUs")
    footer(s)

    # Left column: where it's used
    rect(s, Inches(0.4), Inches(1.35), Inches(4.0), Inches(5.7),
         fill=CARD, line=CYAN, lw=Pt(1))
    box(s, "Where It's Needed",
        Inches(0.5), Inches(1.45), Inches(3.8), Inches(0.5),
        size=16, bold=True, color=CYAN)
    hrule(s, Inches(0.5), Inches(1.95), Inches(3.7), color=CYAN, thick=Pt(1))
    tb = s.shapes.add_textbox(Inches(0.55), Inches(2.05), Inches(3.75), Inches(4.8))
    tf = tb.text_frame; tf.word_wrap = True
    for item in [
        ("⚡  TinyML Inference", "Neural network layers are dense GEMM ops"),
        ("📡  Digital Signal Processing", "Convolution = repeated matrix multiply"),
        ("🔬  Scientific Computing", "Linear solvers, transforms — all matrix ops"),
        ("📷  Image Processing", "Filters, transforms, feature extraction"),
    ]:
        add_para(tf, item[0], 16, bold=True, color=WHITE, before=8)
        add_para(tf, item[1], 12, italic=True, color=GRAY, before=1)

    # Middle column: sequential execution problem
    rect(s, Inches(4.7), Inches(1.35), Inches(4.3), Inches(5.7),
         fill=CARD, line=ORANGE, lw=Pt(1))
    box(s, "Sequential CPU Execution",
        Inches(4.8), Inches(1.45), Inches(4.1), Inches(0.5),
        size=16, bold=True, color=ORANGE)
    hrule(s, Inches(4.8), Inches(1.95), Inches(4.1), color=ORANGE, thick=Pt(1))

    # Code snippet
    code_bg = rect(s, Inches(4.8), Inches(2.05), Inches(4.1), Inches(2.3),
                   fill=RGBColor(0x08, 0x0F, 0x1E), line=GRAY, lw=Pt(0.5))
    tb = s.shapes.add_textbox(Inches(4.9), Inches(2.1), Inches(3.9), Inches(2.2))
    tf = tb.text_frame; tf.word_wrap = False
    for line_txt in [
        "for i in range(4):",
        "  for j in range(4):",
        "    for k in range(4):",
        "      C[i][j] += A[i][k]",
        "             * B[k][j]",
    ]:
        add_para(tf, line_txt, 14, color=GREEN,
                 align=PP_ALIGN.LEFT)

    tb2 = s.shapes.add_textbox(Inches(4.8), Inches(4.45), Inches(4.1), Inches(2.4))
    tf2 = tb2.text_frame; tf2.word_wrap = True
    for txt, col in [
        ("64 multiply-accumulate ops", WHITE),
        ("executed one at a time", GRAY),
        ("", WHITE),
        ("RV32I (no MUL):   26,130 cycles", RED),
        ("RV32IM (with MUL):  7,975 cycles", YELLOW),
    ]:
        add_para(tf2, txt, 15, color=col, before=3)

    # Right column: the gap
    rect(s, Inches(9.25), Inches(1.35), Inches(3.65), Inches(5.7),
         fill=CARD2, line=GREEN, lw=Pt(1))
    box(s, "The Gap",
        Inches(9.35), Inches(1.45), Inches(3.45), Inches(0.5),
        size=16, bold=True, color=GREEN)
    hrule(s, Inches(9.35), Inches(1.95), Inches(3.45), color=GREEN, thick=Pt(1))

    for val, lbl, col in [
        ("26 K",  "cycles wasted\nper 4×4 multiply",      RED),
        ("100%",  "sequential\nutilisation",               ORANGE),
        ("0",     "hardware\nparallelism",                 GRAY),
    ]:
        y_offset = [Inches(2.1), Inches(3.45), Inches(4.8)]
        idx = [("26 K", Inches(2.1)), ("100%", Inches(3.45)), ("0", Inches(4.8))]
        pass

    for i, (val, lbl, col) in enumerate([
        ("26 K",  "cycles wasted per\n4×4 multiply",  RED),
        ("100%",  "sequential\nexecution on CPU",     ORANGE),
        ("0×",    "hardware\nparallelism",             GRAY),
    ]):
        y = Inches(2.1) + i * Inches(1.35)
        box(s, val, Inches(9.35), y, Inches(3.45), Inches(0.65),
            size=36, bold=True, color=col, align=PP_ALIGN.CENTER)
        box(s, lbl, Inches(9.35), y + Inches(0.6), Inches(3.45), Inches(0.6),
            size=13, color=GRAY, align=PP_ALIGN.CENTER)

    add_transition(s)
    return s

# ── SLIDE 3: THE SOLUTION ─────────────────────────────────────────────────────
def slide_solution(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "The Solution: EdgeMATX", "A custom PCPI coprocessor tightly coupled to PicoRV32")
    footer(s)

    # Big central tagline
    rect(s, Inches(0.4), Inches(1.35), Inches(12.5), Inches(1.2),
         fill=CARD, line=CYAN, lw=Pt(1.5))
    box(s, "One custom instruction replaces 64 sequential CPU operations",
        Inches(0.6), Inches(1.45), Inches(12.1), Inches(1.0),
        size=26, bold=True, color=WHITE, align=PP_ALIGN.CENTER)

    # Three pillars
    for i, (icon, title, body, col) in enumerate([
        ("⚡", "Tightly Coupled",
         "PCPI interface: zero memory-mapped overhead. CPU stalls and resumes — no interrupts, no DMA.",
         CYAN),
        ("🔲", "Systolic Datapath",
         "4×4 array of 16 processing elements. All 16 MACs execute in parallel every clock cycle.",
         ORANGE),
        ("🔢", "Q5.10 Fixed-Point",
         "16-bit signed arithmetic. No floating-point hardware needed — ideal for constrained silicon.",
         GREEN),
    ]):
        x = Inches(0.4) + i * Inches(4.32)
        rect(s, x, Inches(2.8), Inches(4.1), Inches(3.0),
             fill=CARD, line=col, lw=Pt(1.5))
        box(s, icon + "  " + title,
            x + Inches(0.15), Inches(2.92), Inches(3.8), Inches(0.6),
            size=18, bold=True, color=col)
        hrule(s, x + Inches(0.15), Inches(3.52), Inches(3.8),
              color=col, thick=Pt(0.8))
        box(s, body,
            x + Inches(0.15), Inches(3.62), Inches(3.8), Inches(1.9),
            size=14, color=WHITE)

    # Bottom bar: key numbers
    rect(s, Inches(0.4), Inches(6.05), Inches(12.5), Inches(0.85),
         fill=RGBColor(0x00, 0x1A, 0x33), line=CYAN, lw=Pt(1))
    for i, (val, lbl) in enumerate([
        ("673",     "Deterministic cycles"),
        ("38.83×",  "Speedup (sparse data)"),
        ("53.86×",  "Speedup (dense data)"),
        ("11.85×",  "Speedup vs MUL-equipped rv32im"),
    ]):
        x = Inches(0.6) + i * Inches(3.1)
        box(s, val, x, Inches(6.1), Inches(1.5), Inches(0.42),
            size=22, bold=True, color=CYAN)
        box(s, lbl, x + Inches(1.5), Inches(6.17), Inches(1.5), Inches(0.32),
            size=11, color=GRAY)

    add_transition(s)
    return s

# ── SLIDE 4: SYSTEM ARCHITECTURE ─────────────────────────────────────────────
def slide_architecture(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "System Architecture", "PicoRV32 + PCPI custom instruction interface + 4×4 systolic accelerator")
    footer(s)

    # Block diagram drawn with shapes + text
    # Firmware layer
    fw = rect(s, Inches(0.5), Inches(1.35), Inches(2.5), Inches(5.7),
              fill=RGBColor(0x0D, 0x2A, 0x1A), line=GREEN, lw=Pt(1.5))
    box(s, "Firmware Layer\n(RISC-V C code)",
        Inches(0.6), Inches(1.45), Inches(2.3), Inches(0.65),
        size=13, bold=True, color=GREEN, align=PP_ALIGN.CENTER)
    tb = s.shapes.add_textbox(Inches(0.55), Inches(2.2), Inches(2.4), Inches(4.6))
    tf = tb.text_frame; tf.word_wrap = True
    for item in ["Load matrix A\n→ 0x100–0x13C",
                 "Load matrix B\n→ 0x140–0x17C",
                 "Execute custom\ninstruction\n0x5420818b",
                 "Read result C\n← 0x200–0x23C"]:
        add_para(tf, item, 12, color=WHITE, before=8)

    # Arrow 1
    box(s, "→", Inches(3.1), Inches(4.0), Inches(0.5), Inches(0.5),
        size=24, bold=True, color=CYAN, align=PP_ALIGN.CENTER)

    # PicoRV32 core
    cpu = rect(s, Inches(3.55), Inches(1.35), Inches(2.7), Inches(5.7),
               fill=RGBColor(0x0A, 0x1A, 0x3A), line=CYAN, lw=Pt(2))
    box(s, "PicoRV32\nCPU Core",
        Inches(3.65), Inches(1.45), Inches(2.5), Inches(0.65),
        size=15, bold=True, color=CYAN, align=PP_ALIGN.CENTER)
    hrule(s, Inches(3.65), Inches(2.1), Inches(2.5), color=CYAN, thick=Pt(0.8))
    tb2 = s.shapes.add_textbox(Inches(3.65), Inches(2.2), Inches(2.5), Inches(4.5))
    tf2 = tb2.text_frame; tf2.word_wrap = True
    for item in ["RV32I ISA", "ENABLE_PCPI=1", "ENABLE_MUL=0",
                 "Custom opcode\ndecoded &\ndispatched via\nPCPI signals",
                 "Stalls until\npcpi_ready=1"]:
        add_para(tf2, item, 12, color=WHITE, before=6)

    # Arrow 2 (PCPI)
    pcpi_x = Inches(6.45)
    rect(s, pcpi_x, Inches(3.6), Inches(0.9), Inches(0.9),
         fill=CARD2, line=YELLOW, lw=Pt(1))
    box(s, "PCPI", pcpi_x, Inches(3.72), Inches(0.9), Inches(0.4),
        size=11, bold=True, color=YELLOW, align=PP_ALIGN.CENTER)
    box(s, "⟷", Inches(6.35), Inches(3.68), Inches(1.1), Inches(0.55),
        size=26, bold=True, color=YELLOW, align=PP_ALIGN.CENTER)

    # Accelerator block
    accel = rect(s, Inches(7.55), Inches(1.35), Inches(2.9), Inches(5.7),
                 fill=RGBColor(0x1A, 0x0A, 0x2E), line=ORANGE, lw=Pt(2))
    box(s, "PCPI Coprocessor\nWrapper",
        Inches(7.65), Inches(1.45), Inches(2.7), Inches(0.65),
        size=15, bold=True, color=ORANGE, align=PP_ALIGN.CENTER)
    hrule(s, Inches(7.65), Inches(2.1), Inches(2.7), color=ORANGE, thick=Pt(0.8))
    tb3 = s.shapes.add_textbox(Inches(7.65), Inches(2.2), Inches(2.7), Inches(1.3))
    tf3 = tb3.text_frame; tf3.word_wrap = True
    for item in ["Detects custom opcode", "Drives matrix engine",
                 "Issues pcpi_ready"]:
        add_para(tf3, item, 12, color=WHITE, before=4)

    # Systolic sub-block
    rect(s, Inches(7.65), Inches(3.65), Inches(2.7), Inches(3.0),
         fill=RGBColor(0x2A, 0x10, 0x45), line=PINK, lw=Pt(1.5))
    box(s, "4×4 Systolic Array",
        Inches(7.75), Inches(3.72), Inches(2.5), Inches(0.5),
        size=13, bold=True, color=PINK, align=PP_ALIGN.CENTER)
    box(s, "16 Processing Elements\nQ5.10 Fixed-Point MACs\nOutput-Stationary Dataflow",
        Inches(7.75), Inches(4.2), Inches(2.5), Inches(1.2),
        size=12, color=WHITE, align=PP_ALIGN.CENTER)
    box(s, "↕ Memory", Inches(7.75), Inches(5.5), Inches(2.5), Inches(0.4),
        size=12, color=GRAY, align=PP_ALIGN.CENTER)

    # Memory block
    mem = rect(s, Inches(10.65), Inches(1.35), Inches(2.35), Inches(5.7),
               fill=RGBColor(0x15, 0x1A, 0x10), line=GREEN, lw=Pt(1.5))
    box(s, "Memory\nMap",
        Inches(10.75), Inches(1.45), Inches(2.15), Inches(0.65),
        size=14, bold=True, color=GREEN, align=PP_ALIGN.CENTER)
    hrule(s, Inches(10.75), Inches(2.1), Inches(2.15), color=GREEN, thick=Pt(0.8))
    tb4 = s.shapes.add_textbox(Inches(10.75), Inches(2.2), Inches(2.15), Inches(4.5))
    tf4 = tb4.text_frame; tf4.word_wrap = True
    for addr, lbl, col in [
        ("0x100–0x13C", "Matrix A (in)", CYAN),
        ("0x140–0x17C", "Matrix B (in)", CYAN),
        ("0x200–0x23C", "Matrix C (out)", GREEN),
    ]:
        add_para(tf4, addr, 12, bold=True, color=col, before=10)
        add_para(tf4, lbl, 11, italic=True, color=GRAY, before=1)

    # Arrow to memory
    box(s, "↔", Inches(10.35), Inches(3.9), Inches(0.6), Inches(0.5),
        size=22, bold=True, color=GREEN, align=PP_ALIGN.CENTER)

    add_transition(s)
    return s

# ── SLIDE 5: PCPI INTERFACE ───────────────────────────────────────────────────
def slide_pcpi(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "PCPI: The Custom Instruction Bridge",
           "Pico Co-Processor Interface — zero-cost hardware dispatch")
    footer(s)

    # Left: signals table
    rect(s, Inches(0.4), Inches(1.35), Inches(5.8), Inches(5.7),
         fill=CARD, line=YELLOW, lw=Pt(1))
    box(s, "Interface Signals", Inches(0.55), Inches(1.45),
        Inches(5.5), Inches(0.45), size=16, bold=True, color=YELLOW)
    hrule(s, Inches(0.55), Inches(1.9), Inches(5.5), color=YELLOW, thick=Pt(0.8))

    signals = [
        ("pcpi_valid",  "CPU → CoPro", "Custom instruction detected",       CYAN),
        ("pcpi_insn",   "CPU → CoPro", "Full 32-bit instruction word",       CYAN),
        ("pcpi_rs1",    "CPU → CoPro", "Source register rs1 (matrix A addr)",CYAN),
        ("pcpi_rs2",    "CPU → CoPro", "Source register rs2 (matrix B addr)",CYAN),
        ("pcpi_wr",     "CoPro → CPU", "Write result back to rd",            ORANGE),
        ("pcpi_rd",     "CoPro → CPU", "Result value (unused in EdgeMATX)",  ORANGE),
        ("pcpi_ready",  "CoPro → CPU", "Computation done — CPU resumes",     GREEN),
        ("pcpi_wait",   "CoPro → CPU", "Hold CPU stall (optional)",          GRAY),
    ]
    tb = s.shapes.add_textbox(Inches(0.55), Inches(2.0), Inches(5.5), Inches(4.8))
    tf = tb.text_frame; tf.word_wrap = True
    for sig, direction, desc, col in signals:
        add_para(tf, f"▸ {sig}", 14, bold=True, color=col, before=5)
        add_para(tf, f"   {direction}  ·  {desc}", 11, color=GRAY, before=0)

    # Right: handshake timeline
    rect(s, Inches(6.5), Inches(1.35), Inches(6.5), Inches(5.7),
         fill=CARD2, line=CYAN, lw=Pt(1))
    box(s, "Execution Handshake", Inches(6.65), Inches(1.45),
        Inches(6.2), Inches(0.45), size=16, bold=True, color=CYAN)
    hrule(s, Inches(6.65), Inches(1.9), Inches(6.2), color=CYAN, thick=Pt(0.8))

    steps = [
        ("1", "CPU fetches custom instruction 0x5420818b",           CYAN),
        ("2", "pcpi_valid=1, instruction + rs1/rs2 broadcast",       CYAN),
        ("3", "CPU stalls — waiting for pcpi_ready",                 YELLOW),
        ("4", "Coprocessor reads matrix A & B from memory",          ORANGE),
        ("5", "4×4 systolic array computes all 16 dot products",     ORANGE),
        ("6", "Results written to matrix C region (0x200–0x23C)",    ORANGE),
        ("7", "pcpi_ready=1  →  CPU resumes next instruction",       GREEN),
    ]
    for i, (num, text, col) in enumerate(steps):
        y = Inches(2.05) + i * Inches(0.7)
        rect(s, Inches(6.65), y, Inches(0.42), Inches(0.42),
             fill=col, line=None)
        box(s, num, Inches(6.65), y, Inches(0.42), Inches(0.42),
            size=14, bold=True, color=BG, align=PP_ALIGN.CENTER)
        box(s, text, Inches(7.15), y + Inches(0.04), Inches(5.7), Inches(0.5),
            size=13, color=WHITE)

    # Opcode callout
    rect(s, Inches(6.65), Inches(6.95 - 0.7), Inches(6.2), Inches(0.52),
         fill=RGBColor(0x08, 0x0F, 0x1E), line=ORANGE, lw=Pt(1))
    box(s, "Custom opcode:  0x5420818b  (custom-0 space, opcode 0001011)",
        Inches(6.75), Inches(6.3), Inches(6.0), Inches(0.42),
        size=13, bold=True, color=ORANGE)

    add_transition(s)
    return s

# ── SLIDE 6: SYSTOLIC ARRAY ───────────────────────────────────────────────────
def slide_systolic(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "The 4×4 Systolic Array", "16 parallel Processing Elements — output-stationary dataflow")
    footer(s)

    # Draw 4×4 grid of PE boxes
    pe_size  = Inches(0.92)
    pe_gap   = Inches(0.18)
    grid_l   = Inches(0.55)
    grid_t   = Inches(1.45)

    # Column labels (B inputs — top)
    for col in range(4):
        cx = grid_l + col * (pe_size + pe_gap)
        box(s, f"B col {col}", cx, Inches(1.3), pe_size, Inches(0.35),
            size=10, color=ORANGE, align=PP_ALIGN.CENTER, bold=True)
        # down arrow
        box(s, "↓", cx + Inches(0.35), Inches(1.62), Inches(0.25), Inches(0.25),
            size=12, color=ORANGE, align=PP_ALIGN.CENTER)

    for row in range(4):
        ry = grid_t + row * (pe_size + pe_gap)

        # Row label (A inputs — left)
        box(s, f"A row {row}  →", Inches(0.0), ry + Inches(0.28),
            Inches(0.6), Inches(0.4), size=10, color=CYAN, bold=True)

        for col in range(4):
            cx = grid_l + col * (pe_size + pe_gap)

            colors_ = [CYAN, ORANGE, GREEN, PINK]
            pe_col  = colors_[row]
            pe_fill = RGBColor(
                int(pe_col[0] * 0.12),
                int(pe_col[1] * 0.12),
                int(pe_col[2] * 0.12),
            )
            border_col = pe_col

            b = rect(s, cx, ry, pe_size, pe_size,
                     fill=RGBColor(0x18, 0x25, 0x45), line=border_col, lw=Pt(1.5))
            box(s, f"PE\n[{row},{col}]",
                cx, ry + Inches(0.15), pe_size, Inches(0.65),
                size=13, bold=True, color=border_col, align=PP_ALIGN.CENTER)
            box(s, "MAC",
                cx, ry + Inches(0.62), pe_size, Inches(0.28),
                size=10, color=GRAY, align=PP_ALIGN.CENTER)

            # Right arrows between PEs
            if col < 3:
                box(s, "→", cx + pe_size, ry + Inches(0.33),
                    pe_gap + Inches(0.02), Inches(0.3),
                    size=11, color=GRAY, align=PP_ALIGN.CENTER)
            # Down arrows
            if row < 3:
                box(s, "↓", cx + Inches(0.37), ry + pe_size,
                    Inches(0.2), pe_gap,
                    size=10, color=GRAY, align=PP_ALIGN.CENTER)

        # Output label (C — right side)
        out_x = grid_l + 4 * (pe_size + pe_gap)
        box(s, f"→ C row {row}", out_x, ry + Inches(0.28),
            Inches(1.0), Inches(0.38), size=10, color=GREEN, bold=True)

    # Right panel: dataflow explanation
    rx = Inches(4.9) + 4 * Inches(0)
    rx = grid_l + 4 * (pe_size + pe_gap) + Inches(1.1)
    rect(s, rx, Inches(1.35), Inches(13.333 - rx / 914400 - 0.4), Inches(5.7),
         fill=CARD, line=CYAN, lw=Pt(1))

    rw = Inches(13.333) - rx - Inches(0.45)
    box(s, "How It Works", rx + Inches(0.15), Inches(1.45),
        rw - Inches(0.2), Inches(0.45), size=16, bold=True, color=CYAN)
    hrule(s, rx + Inches(0.15), Inches(1.9), rw - Inches(0.2),
          color=CYAN, thick=Pt(0.8))

    tb = s.shapes.add_textbox(rx + Inches(0.15), Inches(2.0),
                               rw - Inches(0.2), Inches(4.8))
    tf = tb.text_frame; tf.word_wrap = True
    facts = [
        ("Output-stationary", "Each PE accumulates its partial sum for C[i,j] in place"),
        ("Row broadcast", "Row i of matrix A flows right across row i of PEs"),
        ("Column broadcast", "Column j of matrix B flows down column j of PEs"),
        ("Parallel MACs", "All 16 PEs execute simultaneously every clock cycle"),
        ("Deterministic", "673 cycles regardless of operand values"),
        ("16-bit Q5.10", "Multiply → shift-right 10 → accumulate → truncate"),
    ]
    for title, desc in facts:
        add_para(tf, f"▸ {title}", 14, bold=True, color=ORANGE, before=8)
        add_para(tf, f"  {desc}", 12, color=WHITE, before=1)

    add_transition(s)
    return s

# ── SLIDE 7: Q5.10 FIXED-POINT ────────────────────────────────────────────────
def slide_fixedpoint(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "Q5.10 Fixed-Point Arithmetic",
           "16-bit two's complement — integer simplicity, fractional precision")
    footer(s)

    # Bit layout diagram
    bit_w = Inches(0.78)
    bit_t = Inches(1.45)
    bit_h = Inches(0.75)

    labels = ["S", "I4", "I3", "I2", "I1", "I0",
              "F9", "F8", "F7", "F6", "F5", "F4", "F3", "F2", "F1", "F0"]
    colors_ = ([RED] +
               [ORANGE] * 5 +
               [CYAN]   * 10)
    bit_nums = [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]

    for i in range(16):
        x = Inches(0.4) + i * bit_w
        rect(s, x, bit_t, bit_w, bit_h,
             fill=colors_[i], line=BG, lw=Pt(2))
        box(s, labels[i], x, bit_t + Inches(0.13), bit_w, bit_h - Inches(0.26),
            size=14, bold=True, color=BG, align=PP_ALIGN.CENTER)
        box(s, str(bit_nums[i]), x, bit_t + bit_h + Inches(0.02),
            bit_w, Inches(0.28), size=9, color=GRAY, align=PP_ALIGN.CENTER)

    # Brace labels
    box(s, "Sign (1 bit)", Inches(0.4), bit_t + bit_h + Inches(0.3),
        bit_w, Inches(0.38), size=11, color=RED, align=PP_ALIGN.CENTER)
    box(s, "Integer part  (5 bits)", Inches(1.2), bit_t + bit_h + Inches(0.3),
        bit_w * 5, Inches(0.38), size=11, color=ORANGE, align=PP_ALIGN.CENTER)
    box(s, "Fractional part  (10 bits)", Inches(1.2) + bit_w * 5,
        bit_t + bit_h + Inches(0.3), bit_w * 10, Inches(0.38),
        size=11, color=CYAN, align=PP_ALIGN.CENTER)

    # Properties grid
    props = [
        ("Range",       "−32.0  to  +31.999",    WHITE),
        ("Resolution",  "1 / 1024  ≈  0.001",    WHITE),
        ("Format",      "16-bit signed integer",  WHITE),
        ("Scaling",     "Multiply → shift right 10 bits", WHITE),
    ]
    for i, (k, v, col) in enumerate(props):
        x = Inches(0.4) + i * Inches(3.22)
        rect(s, x, Inches(3.3), Inches(3.1), Inches(1.0),
             fill=CARD, line=CYAN, lw=Pt(1))
        box(s, k, x + Inches(0.1), Inches(3.38), Inches(2.9), Inches(0.38),
            size=13, bold=True, color=CYAN)
        box(s, v, x + Inches(0.1), Inches(3.72), Inches(2.9), Inches(0.48),
            size=14, color=WHITE)

    # PE arithmetic walkthrough
    rect(s, Inches(0.4), Inches(4.5), Inches(12.5), Inches(2.3),
         fill=CARD2, line=ORANGE, lw=Pt(1))
    box(s, "Processing Element MAC Operation  (per clock cycle):",
        Inches(0.55), Inches(4.58), Inches(12.1), Inches(0.42),
        size=15, bold=True, color=ORANGE)

    steps = [
        ("①  Multiply",     "a_in × b_in  →  32-bit signed product"),
        ("②  Scale",        "product >>> 10  (arithmetic right-shift corrects Q5.10 format)"),
        ("③  Accumulate",   "acc +=  scaled_product  (32-bit running sum)"),
        ("④  Pass through", "a_out ← a_in  ;  b_out ← b_in  (feed neighbours)"),
    ]
    for i, (step, desc) in enumerate(steps):
        x = Inches(0.55) + i * Inches(3.12)
        box(s, step, x, Inches(5.05), Inches(2.9), Inches(0.38),
            size=13, bold=True, color=YELLOW)
        box(s, desc, x, Inches(5.42), Inches(3.0), Inches(1.2),
            size=11, color=WHITE)

    add_transition(s)
    return s

# ── SLIDE 8: VERIFICATION STRATEGY ───────────────────────────────────────────
def slide_verification(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "Verification Strategy", "Four-layer simulation campaign — from unit tests to full system benchmarking")
    footer(s)

    layers = [
        (4, "Performance Benchmarking",
         "Cycle-count measurement against two software baselines (no-MUL and MUL-equipped).",
         YELLOW, "673 cycles measured"),
        (3, "Protocol Handoff Validation",
         "Isolated test of PCPI signal handshake — pcpi_valid, pcpi_ready, pcpi_insn correctness.",
         ORANGE, "PASS"),
        (2, "CPU Integration Regression",
         "Full system simulation: PicoRV32 + PCPI wrapper + accelerator. 8 input profiles.",
         CYAN, "8 / 8 PASS"),
        (1, "Standalone Unit Tests",
         "Accelerator module in isolation. Zero, identity, dense, boundary, negative-element cases.",
         GREEN, "19 / 19 PASS"),
    ]

    for i, (num, title, desc, col, result) in enumerate(layers):
        y = Inches(1.35) + i * Inches(1.38)
        w_bar = Inches(12.5) - i * Inches(0.6)
        x_bar = Inches(0.4) + i * Inches(0.3)

        rect(s, x_bar, y, w_bar, Inches(1.28), fill=CARD, line=col, lw=Pt(1.5))

        # Layer number badge
        rect(s, x_bar + Inches(0.1), y + Inches(0.19),
             Inches(0.55), Inches(0.55), fill=col)
        box(s, str(num), x_bar + Inches(0.1), y + Inches(0.19),
            Inches(0.55), Inches(0.55), size=20, bold=True,
            color=BG, align=PP_ALIGN.CENTER)

        box(s, f"Layer {num}  ·  {title}",
            x_bar + Inches(0.8), y + Inches(0.1), Inches(9.0), Inches(0.48),
            size=17, bold=True, color=col)
        box(s, desc,
            x_bar + Inches(0.8), y + Inches(0.58), Inches(8.8), Inches(0.62),
            size=13, color=WHITE)

        # Result badge
        rect(s, x_bar + w_bar - Inches(2.0), y + Inches(0.35),
             Inches(1.85), Inches(0.5), fill=col)
        box(s, result,
            x_bar + w_bar - Inches(2.0), y + Inches(0.39),
            Inches(1.85), Inches(0.42), size=14, bold=True,
            color=BG, align=PP_ALIGN.CENTER)

    add_transition(s)
    return s

# ── SLIDE 9: TEST RESULTS SCORECARD ──────────────────────────────────────────
def slide_results_tests(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "Verification Results", "100% pass rate across all test flows — simulation-complete milestone")
    footer(s)

    # Big pass badge
    rect(s, Inches(0.4), Inches(1.35), Inches(3.8), Inches(5.7),
         fill=RGBColor(0x00, 0x20, 0x10), line=GREEN, lw=Pt(2))
    box(s, "100%", Inches(0.4), Inches(1.9), Inches(3.8), Inches(1.2),
        size=64, bold=True, color=GREEN, align=PP_ALIGN.CENTER)
    box(s, "PASS RATE",
        Inches(0.4), Inches(3.1), Inches(3.8), Inches(0.5),
        size=18, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
    hrule(s, Inches(0.7), Inches(3.65), Inches(3.2), color=GREEN, thick=Pt(1))

    tb = s.shapes.add_textbox(Inches(0.55), Inches(3.75), Inches(3.5), Inches(2.9))
    tf = tb.text_frame; tf.word_wrap = True
    for val, lbl in [("19 / 19", "standalone unit tests"),
                     ("8 / 8",   "integration cases"),
                     ("5 / 5",   "professor demo cases"),
                     ("✓",       "handoff protocol test"),
                     ("✓",       "one-command gate check")]:
        add_para(tf, f"{val}  {lbl}", 14, before=7,
                 color=GREEN if "19" in val or "8" in val else WHITE)

    # Test category breakdown
    categories = [
        ("Zero / Null Matrix",        2,  2,  GREEN),
        ("Identity Matrix",           3,  3,  GREEN),
        ("Dense (varied magnitudes)", 8,  8,  GREEN),
        ("Q5.10 Sign Boundary",       4,  4,  GREEN),
        ("Negative Elements",         2,  2,  GREEN),
        ("Integration: varied inputs",8,  8,  CYAN),
        ("Professor Demo Cases",      5,  5,  ORANGE),
    ]
    rect(s, Inches(4.45), Inches(1.35), Inches(8.45), Inches(5.7),
         fill=CARD, line=CYAN, lw=Pt(1))
    box(s, "Test Category Breakdown",
        Inches(4.6), Inches(1.45), Inches(8.1), Inches(0.45),
        size=16, bold=True, color=CYAN)
    hrule(s, Inches(4.6), Inches(1.9), Inches(8.1), color=CYAN, thick=Pt(0.8))

    bar_l = Inches(7.2)
    bar_max_w = Inches(4.8)
    for i, (cat, total, passed, col) in enumerate(categories):
        y = Inches(2.05) + i * Inches(0.68)
        box(s, cat, Inches(4.6), y + Inches(0.1), Inches(2.5), Inches(0.42),
            size=12, color=WHITE)
        # Bar
        rect(s, bar_l, y + Inches(0.18), bar_max_w, Inches(0.28),
             fill=CARD2, line=None)
        rect(s, bar_l, y + Inches(0.18),
             bar_max_w * passed / total, Inches(0.28),
             fill=col, line=None)
        box(s, f"{passed}/{total}", bar_l + bar_max_w + Inches(0.1), y + Inches(0.1),
            Inches(0.7), Inches(0.42), size=12, bold=True, color=col)

    add_transition(s)
    return s

# ── SLIDE 10: PERFORMANCE — CYCLE COUNTS ─────────────────────────────────────
def slide_cycles(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "Performance: Cycle Counts",
           "Deterministic execution — 673 cycles regardless of input values")
    footer(s)

    # Left: numbers highlight
    rect(s, Inches(0.4), Inches(1.35), Inches(4.5), Inches(5.7),
         fill=CARD2, line=CYAN, lw=Pt(1.5))

    for i, (val, lbl, sub, col) in enumerate([
        ("673",    "EdgeMATX Accelerator",    "rv32i + PCPI",       CYAN),
        ("7,975",  "Software + MUL",          "rv32im baseline",    YELLOW),
        ("26,130", "Software (no MUL)",       "rv32i baseline",     RED),
        ("36,246", "Software (no MUL, dense)","dense profile",      RED),
    ]):
        y = Inches(1.45) + i * Inches(1.38)
        box(s, val,
            Inches(0.6), y, Inches(3.5), Inches(0.72),
            size=34, bold=True, color=col, align=PP_ALIGN.CENTER)
        box(s, lbl,
            Inches(0.6), y + Inches(0.68), Inches(3.5), Inches(0.38),
            size=13, color=WHITE, align=PP_ALIGN.CENTER)
        box(s, sub,
            Inches(0.6), y + Inches(1.0), Inches(3.5), Inches(0.3),
            size=11, italic=True, color=GRAY, align=PP_ALIGN.CENTER)

    # Right: bar chart via python-pptx
    chart_data = ChartData()
    chart_data.categories = ['EdgeMATX\n(PCPI)', 'SW + MUL\n(rv32im)', 'SW no-MUL\n(rv32i)', 'SW no-MUL\n(dense)']
    chart_data.add_series('Cycles', (673, 7975, 26130, 36246))

    chart = s.shapes.add_chart(
        XL_CHART_TYPE.BAR_CLUSTERED,
        Inches(5.1), Inches(1.35), Inches(7.9), Inches(5.7),
        chart_data
    ).chart

    chart.has_legend = False
    chart.has_title  = True
    chart.chart_title.has_text_frame = True
    chart.chart_title.text_frame.text = "Cycle Count Comparison"
    chart.chart_title.text_frame.paragraphs[0].runs[0].font.size = Pt(14)
    chart.chart_title.text_frame.paragraphs[0].runs[0].font.bold = True

    # Style series bars
    series = chart.series[0]
    from pptx.dml.color import RGBColor as RC
    # Colour each bar individually via XML
    pts_xml = series.format.fill  # fallback — style the series
    series.format.fill.solid()
    series.format.fill.fore_color.rgb = CYAN

    add_transition(s)
    return s

# ── SLIDE 11: PERFORMANCE — SPEEDUP ──────────────────────────────────────────
def slide_speedup(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "Performance: Speedup", "38–54× over rv32i software baseline — 11.85× over MUL-equipped core")
    footer(s)

    # Three big speedup callouts
    for i, (val, title, desc, col) in enumerate([
        ("38.83×", "Sparse  vs  rv32i",
         "Identity-sequence benchmark\n26,130 → 673 cycles",    GREEN),
        ("53.86×", "Dense   vs  rv32i",
         "Live dense profile\n36,246 → 673 cycles",             CYAN),
        ("11.85×", "Any     vs  rv32im",
         "Even against MUL-equipped core\n7,975 → 673 cycles",  ORANGE),
    ]):
        x = Inches(0.4) + i * Inches(4.32)
        b = rect(s, x, Inches(1.35), Inches(4.1), Inches(3.1),
                 fill=CARD, line=col, lw=Pt(2))
        box(s, val, x, Inches(1.55), Inches(4.1), Inches(1.1),
            size=46, bold=True, color=col, align=PP_ALIGN.CENTER)
        box(s, title, x, Inches(2.65), Inches(4.1), Inches(0.5),
            size=17, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        box(s, desc, x, Inches(3.18), Inches(4.1), Inches(0.8),
            size=13, italic=True, color=GRAY, align=PP_ALIGN.CENTER)

    # Table
    rect(s, Inches(0.4), Inches(4.65), Inches(12.5), Inches(2.4),
         fill=CARD2, line=CYAN, lw=Pt(1))
    box(s, "Consolidated Speedup Table",
        Inches(0.55), Inches(4.72), Inches(12.1), Inches(0.38),
        size=14, bold=True, color=CYAN)

    headers = ["Profile", "EdgeMATX", "SW (no MUL)", "SW (MUL)", "Speedup vs no-MUL", "Speedup vs MUL"]
    col_widths = [1.8, 1.4, 1.6, 1.4, 2.0, 1.8]
    row_data = [
        ["identity_x_sequence", "673", "26,130", "7,975", "38.83×", "11.85×"],
        ["live_real_input (dense)", "673", "36,246", "7,975", "53.86×", "11.85×"],
    ]

    x_start = Inches(0.5)
    for j, (h, cw) in enumerate(zip(headers, col_widths)):
        x = x_start + sum(Inches(col_widths[k]) for k in range(j))
        box(s, h, x, Inches(5.12), Inches(cw), Inches(0.38),
            size=11, bold=True, color=GRAY, align=PP_ALIGN.CENTER)

    for r, row in enumerate(row_data):
        y = Inches(5.52) + r * Inches(0.5)
        rc_ = [WHITE, CYAN, RED, YELLOW, GREEN, ORANGE]
        for j, (cell, cw) in enumerate(zip(row, col_widths)):
            x = x_start + sum(Inches(col_widths[k]) for k in range(j))
            box(s, cell, x, y, Inches(cw), Inches(0.44),
                size=12, bold=(j >= 4), color=rc_[j], align=PP_ALIGN.CENTER)

    add_transition(s)
    return s

# ── SLIDE 12: INTERACTIVE VISUALIZERS ────────────────────────────────────────
def slide_visualizers(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "Interactive Visualizers", "Explore the design live in your browser")
    footer(s)

    for i, (title, url, desc_lines, col) in enumerate([
        ("Architecture Overview",
         "riscv-visualizer-2.vercel.app",
         ["High-level system architecture and dataflow",
          "Firmware layer · PicoRV32 · PCPI · Systolic Array",
          "Step-through execution with annotations"],
         CYAN),
        ("Processor Signal Simulation",
         "tinyml-pcpi-visualizer.vercel.app",
         ["Instruction decode · PCPI signal timeline",
          "Accelerator invocation waveform",
          "Systolic array computation state"],
         ORANGE),
    ]):
        x = Inches(0.4) + i * Inches(6.5)
        rect(s, x, Inches(1.35), Inches(6.2), Inches(5.7),
             fill=CARD, line=col, lw=Pt(2))

        box(s, title, x + Inches(0.2), Inches(1.45),
            Inches(5.8), Inches(0.55), size=20, bold=True, color=col)
        hrule(s, x + Inches(0.2), Inches(2.0), Inches(5.8),
              color=col, thick=Pt(0.8))

        # URL badge
        rect(s, x + Inches(0.2), Inches(2.1), Inches(5.8), Inches(0.52),
             fill=RGBColor(0x08, 0x0F, 0x1E), line=col, lw=Pt(1))
        box(s, "🔗  " + url,
            x + Inches(0.25), Inches(2.17), Inches(5.7), Inches(0.38),
            size=14, bold=True, color=col)

        tb = s.shapes.add_textbox(x + Inches(0.2), Inches(2.75),
                                   Inches(5.8), Inches(3.5))
        tf = tb.text_frame; tf.word_wrap = True
        for line in desc_lines:
            add_para(tf, "▸  " + line, 15, color=WHITE, before=10)

        # Placeholder browser frame
        rect(s, x + Inches(0.2), Inches(4.15), Inches(5.8), Inches(1.85),
             fill=RGBColor(0x08, 0x10, 0x1C), line=GRAY, lw=Pt(0.8))
        box(s, "[ Open in browser to view live simulation ]",
            x + Inches(0.2), Inches(4.8), Inches(5.8), Inches(0.5),
            size=12, italic=True, color=GRAY, align=PP_ALIGN.CENTER)

    add_transition(s)
    return s

# ── SLIDE 13: FUTURE WORK ─────────────────────────────────────────────────────
def slide_future(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "What's Next: Pynq-Z2 FPGA Deployment",
           "Simulation-proven design → physical hardware closure")
    footer(s)

    # Journey graphic: three stages
    stages = [
        ("✅ DONE",       "Simulation",
         "673-cycle verified\nbehaviour on\nIcarus Verilog",    GREEN),
        ("🔜 NEXT",       "FPGA Synthesis",
         "Map to Pynq-Z2\nXilinx Zynq-7020\nPost-synthesis timing",  YELLOW),
        ("🔭 FUTURE",     "Scale & Deploy",
         "On-board cycle counts\nAXI/BRAM memory\n8×8 array extension",  GRAY),
    ]
    for i, (status, stage, desc, col) in enumerate(stages):
        x = Inches(0.5) + i * Inches(4.28)
        rect(s, x, Inches(1.35), Inches(4.0), Inches(3.8),
             fill=CARD, line=col, lw=Pt(2))
        box(s, status, x, Inches(1.45), Inches(4.0), Inches(0.45),
            size=13, bold=True, color=col, align=PP_ALIGN.CENTER)
        box(s, stage, x, Inches(1.88), Inches(4.0), Inches(0.65),
            size=22, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        box(s, desc, x, Inches(2.58), Inches(4.0), Inches(1.4),
            size=14, color=GRAY, align=PP_ALIGN.CENTER)

        if i < 2:
            box(s, "→", Inches(4.55) + i * Inches(4.28), Inches(2.75),
                Inches(0.4), Inches(0.5),
                size=26, bold=True, color=GRAY, align=PP_ALIGN.CENTER)

    # Pending items
    rect(s, Inches(0.4), Inches(5.3), Inches(12.5), Inches(1.85),
         fill=CARD2, line=ORANGE, lw=Pt(1))
    box(s, "Open Items Before Hardware Closure",
        Inches(0.55), Inches(5.38), Inches(12.1), Inches(0.42),
        size=14, bold=True, color=ORANGE)
    tb = s.shapes.add_textbox(Inches(0.55), Inches(5.82),
                               Inches(12.1), Inches(1.1))
    tf = tb.text_frame; tf.word_wrap = True
    items = [
        "Cycle-scaling estimator anchor needs updating (869 → 673 cycles)",
        "On-board rdcycle CSR measurements to cross-validate simulation results",
        "AXI-BRAM memory interface replacing software-driven memory reads",
    ]
    for item in items:
        add_para(tf, "▸  " + item, 13, color=WHITE, before=3)

    add_transition(s)
    return s

# ── SLIDE 14: CONCLUSION ──────────────────────────────────────────────────────
def slide_conclusion(prs):
    s = blank(prs)
    set_bg(s)
    header(s, "Conclusion", "Simulation-complete milestone — all objectives achieved")
    footer(s)

    achievements = [
        ("Hardware Accelerator", "4×4 systolic array with 16 Q5.10 fixed-point MACs, implemented in Verilog", CYAN),
        ("CPU Integration", "Tightly coupled to PicoRV32 via PCPI custom instruction — single opcode dispatch", ORANGE),
        ("Deterministic Execution", "673-cycle latency, invariant to operand values — ideal for real-time systems", GREEN),
        ("Verified Performance", "38.83× – 53.86× speedup over rv32i; 11.85× over MUL-equipped rv32im", YELLOW),
        ("100% Test Coverage", "19/19 standalone · 8/8 integration · 5/5 professor demo · handoff PASS", PINK),
        ("Interactive Tooling", "Two live web visualizers for architecture walkthrough and signal-level simulation", GRAY),
    ]

    for i, (title, desc, col) in enumerate(achievements):
        row = i // 2
        c   = i %  2
        x = Inches(0.4) + c * Inches(6.3)
        y = Inches(1.35) + row * Inches(1.5)
        rect(s, x, y, Inches(6.05), Inches(1.38),
             fill=CARD, line=col, lw=Pt(1.5))
        box(s, title, x + Inches(0.15), y + Inches(0.1),
            Inches(5.75), Inches(0.48), size=16, bold=True, color=col)
        box(s, desc, x + Inches(0.15), y + Inches(0.58),
            Inches(5.75), Inches(0.65), size=12, color=WHITE)

    add_transition(s)
    return s

# ── SLIDE 15: THANK YOU ───────────────────────────────────────────────────────
def slide_thankyou(prs):
    s = blank(prs)
    set_bg(s)
    rect(s, Inches(0), Inches(0), W, Inches(0.08), fill=CYAN)
    rect(s, Inches(0), H - Inches(0.08), W, Inches(0.08), fill=ORANGE)

    box(s, "Thank You", Inches(0.5), Inches(0.8), W - Inches(1.0), Inches(1.6),
        size=72, bold=True, color=CYAN, align=PP_ALIGN.CENTER)
    box(s, "Questions & Discussion", Inches(0.5), Inches(2.4),
        W - Inches(1.0), Inches(0.7), size=26, color=WHITE, align=PP_ALIGN.CENTER)

    hrule(s, Inches(2.0), Inches(3.2), Inches(9.333), color=ORANGE, thick=Pt(1.5))

    # Team
    tb = s.shapes.add_textbox(Inches(1.5), Inches(3.4), Inches(6.0), Inches(1.6))
    tf = tb.text_frame; tf.word_wrap = True
    add_para(tf, "Team", 13, italic=True, color=GRAY)
    for name in ["Nishchay Pallav  221EC233",
                 "Mohammad Omar Sulemani  221EC230",
                 "Md Atib Kaif  221EC129"]:
        add_para(tf, name, 16, bold=True, color=WHITE, before=3)

    # Visualizer URLs
    tb2 = s.shapes.add_textbox(Inches(7.8), Inches(3.4), Inches(5.2), Inches(1.6))
    tf2 = tb2.text_frame; tf2.word_wrap = True
    add_para(tf2, "Live Visualizers", 13, italic=True, color=GRAY)
    for url in ["riscv-visualizer-2.vercel.app",
                "tinyml-pcpi-visualizer.vercel.app"]:
        add_para(tf2, "🔗 " + url, 13, color=CYAN, before=5)

    box(s, "Dept. of Electronics & Communication Engineering\nNational Institute of Technology Karnataka, Surathkal — 575025  ·  2026",
        Inches(0.5), Inches(6.5), W - Inches(1.0), Inches(0.7),
        size=12, color=GRAY, align=PP_ALIGN.CENTER)

    add_transition(s)
    return s

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def build():
    prs = make_prs()

    print("Building slides...")
    slide_title(prs)        ; print("  [OK] Slide 1  - Title")
    slide_problem(prs)      ; print("  [OK] Slide 2  - The Problem")
    slide_solution(prs)     ; print("  [OK] Slide 3  - The Solution")
    slide_architecture(prs) ; print("  [OK] Slide 4  - System Architecture")
    slide_pcpi(prs)         ; print("  [OK] Slide 5  - PCPI Interface")
    slide_systolic(prs)     ; print("  [OK] Slide 6  - Systolic Array")
    slide_fixedpoint(prs)   ; print("  [OK] Slide 7  - Q5.10 Fixed-Point")
    slide_verification(prs) ; print("  [OK] Slide 8  - Verification Strategy")
    slide_results_tests(prs); print("  [OK] Slide 9  - Test Results")
    slide_cycles(prs)       ; print("  [OK] Slide 10 - Cycle Counts")
    slide_speedup(prs)      ; print("  [OK] Slide 11 - Speedup")
    slide_visualizers(prs)  ; print("  [OK] Slide 12 - Visualizers")
    slide_future(prs)       ; print("  [OK] Slide 13 - Future Work")
    slide_conclusion(prs)   ; print("  [OK] Slide 14 - Conclusion")
    slide_thankyou(prs)     ; print("  [OK] Slide 15 - Thank You")

    out = os.path.join(os.path.dirname(__file__), "EdgeMATX_presentation.pptx")
    prs.save(out)
    print("\nDone. Saved -> " + out)

if __name__ == "__main__":
    build()
