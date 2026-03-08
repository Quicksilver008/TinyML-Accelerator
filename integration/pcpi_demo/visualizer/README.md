# TinyML PCPI Visualizer (Vercel-ready)

Path:
`integration/pcpi_demo/visualizer/`

This is a dependency-free static app that visualizes:
1. system architecture across CPU, wrapper, accelerator, and memory domains
2. wrapper FSM progression with forward and backward stepping
3. PCPI handshake (`pcpi_valid`, `pcpi_wait`, `pcpi_ready`, `pcpi_wr`, `pcpi_rd`)
4. wrapper-owned memory traffic for A/B reads and C writeback
5. 4x4 systolic PE-level operand movement during `WAIT_ACC`
6. project-specific info popups for opcode, Q5.10, stall/handoff behavior, and file mapping

## Files

1. `index.html`
2. `styles.css`
3. `app.js`

## Local run

From this folder:

```powershell
python -m http.server 8080
```

Open:
`http://localhost:8080`

Hard refresh after edits:
`Ctrl + F5`

## Current UI

The app is organized into four panels:
1. `System Architecture`
2. `Systolic Array View`
3. `State Transitions`
4. `Event Log`

Each panel header exposes:
1. `Run`
2. `Step Back`
3. `Step`
4. `Reset`

Additional info controls:
1. top-right `App Guide` button explains how to use the visualizer
2. `Architecture Info` button explains domains, signals, opcode, Q5.10, files, and transaction flow
3. CPU block `i` button explains PicoRV32 handoff/stall behavior and includes a reference 5-stage pipeline diagram
4. small `i` buttons on architecture arrows show the exact signals carried on that path

Resizable layout:
1. drag the vertical splitter to resize left/right panels
2. drag the horizontal splitter to resize top/bottom panels

## Vercel deploy

Current production URL:
`https://tinyml-pcpi-visualizer.vercel.app`

Option A (Vercel dashboard):
1. Import this repository in Vercel.
2. Set **Root Directory** to `integration/pcpi_demo/visualizer`.
3. Framework preset: `Other`.
4. Deploy.

Option B (CLI in this folder):

```powershell
npx --yes vercel@latest
```

Then:

```powershell
npx --yes vercel@latest --prod
```

## Notes

1. Animation sequence mirrors current wrapper states:
   `IDLE -> LOAD_A -> LOAD_B -> KICK -> WAIT_ACC -> STORE_C -> RESP -> IDLE`
2. `WAIT_ACC` is shown as 10 micro-cycles to match `COMPUTE_CYCLES=10`.
3. C writeback base is depicted according to current RTL behavior (fixed C base in wrapper).
4. The app intentionally shows a reference 5-stage CPU diagram only as teaching context; the integrated CPU here is PicoRV32, which is FSM-based.
