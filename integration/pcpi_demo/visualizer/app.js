const mesh = document.getElementById("mesh");
const logBox = document.getElementById("logBox");
const btnRun = document.getElementById("btnRun");
const btnStep = document.getElementById("btnStep");
const btnStepBack = document.getElementById("btnStepBack");
const btnReset = document.getElementById("btnReset");
const workspace = document.getElementById("workspace");
const columnSplitter = document.getElementById("columnSplitter");
const rowSplitter = document.getElementById("rowSplitter");
const signalPopover = document.getElementById("signalPopover");
const signalPopoverTitle = document.getElementById("signalPopoverTitle");
const signalPopoverBody = document.getElementById("signalPopoverBody");
const archInfoModal = document.getElementById("archInfoModal");
const btnArchInfo = document.getElementById("btnArchInfo");
const btnArchInfoClose = document.getElementById("btnArchInfoClose");
const archInfoBackdrop = document.getElementById("archInfoBackdrop");
const cpuInfoModal = document.getElementById("cpuInfoModal");
const btnCpuInfo = document.getElementById("btnCpuInfo");
const btnCpuInfoClose = document.getElementById("btnCpuInfoClose");
const cpuInfoBackdrop = document.getElementById("cpuInfoBackdrop");
const appGuideModal = document.getElementById("appGuideModal");
const btnAppGuide = document.getElementById("btnAppGuide");
const btnAppGuideClose = document.getElementById("btnAppGuideClose");
const appGuideBackdrop = document.getElementById("appGuideBackdrop");
const panelButtons = [...document.querySelectorAll("[data-control]")];

const elements = {
  stateValue: document.getElementById("stateValue"),
  cycleValue: document.getElementById("cycleValue"),
  waitCycleValue: document.getElementById("waitCycleValue"),
  sigInsnMatch: document.getElementById("sigInsnMatch"),
  sigValid: document.getElementById("sigValid"),
  sigWait: document.getElementById("sigWait"),
  sigReady: document.getElementById("sigReady"),
  sigWr: document.getElementById("sigWr"),
  sigRd: document.getElementById("sigRd"),
  sigRespValid: document.getElementById("sigRespValid"),
  sigRs1: document.getElementById("sigRs1"),
  sigRs2: document.getElementById("sigRs2"),
  sigElemIdx: document.getElementById("sigElemIdx"),
  sigBufA: document.getElementById("sigBufA"),
  sigBufB: document.getElementById("sigBufB"),
  sigMemValid: document.getElementById("sigMemValid"),
  sigMemWe: document.getElementById("sigMemWe"),
  sigMemAddr: document.getElementById("sigMemAddr"),
  sigMemWdata: document.getElementById("sigMemWdata"),
  sigMemRdata: document.getElementById("sigMemRdata"),
  sigMemReady: document.getElementById("sigMemReady"),
  sigBusy: document.getElementById("sigBusy"),
  sigDone: document.getElementById("sigDone"),
  sigAccelCycle: document.getElementById("sigAccelCycle"),
  stateTitle: document.getElementById("stateTitle"),
  stateDesc: document.getElementById("stateDesc"),
  cpuBlock: document.getElementById("cpuBlock"),
  wrapperBlock: document.getElementById("wrapperBlock"),
  accelBlock: document.getElementById("accelBlock"),
  memoryBlock: document.getElementById("memoryBlock"),
  decodeBlock: document.getElementById("decodeBlock"),
  memSeqBlock: document.getElementById("memSeqBlock"),
  baseBlock: document.getElementById("baseBlock"),
  bufferBlock: document.getElementById("bufferBlock"),
  respBlock: document.getElementById("respBlock"),
  accelCtrlBlock: document.getElementById("accelCtrlBlock"),
  issueBlock: document.getElementById("issueBlock"),
  statusBlock: document.getElementById("statusBlock")
};

const stateMeta = {
  IDLE: {
    title: "S_IDLE",
    desc: "The wrapper is idle. No memory request is active and the CPU is not stalled."
  },
  LOAD_A: {
    title: "S_LOAD_A",
    desc: "The custom instruction matches. The wrapper latches pcpi_rs1 into base_a and reads the 16 A elements into a_flat."
  },
  LOAD_B: {
    title: "S_LOAD_B",
    desc: "A is buffered. The wrapper now reads the 16 B elements into b_flat while keeping the CPU stalled."
  },
  KICK: {
    title: "S_KICK",
    desc: "The wrapper pulses accel_start and presents a_flat / b_flat to the accelerator."
  },
  WAIT_ACC: {
    title: "S_WAIT_ACC",
    desc: "The accelerator is busy. Issue logic drives aligned operands into the 4x4 array for 10 scheduled compute cycles."
  },
  STORE_C: {
    title: "S_STORE_C",
    desc: "The wrapper writes the 16 output words from c_flat back to memory at C_BASE_ADDR 0x0000_0200."
  },
  RESP: {
    title: "S_RESP",
    desc: "The wrapper raises resp_valid, drives pcpi_ready / pcpi_wr, and returns result_reg on pcpi_rd."
  }
};

const fsmItems = new Map(
  [...document.querySelectorAll("#fsmList li")].map((li) => [li.dataset.state, li])
);

const signalLines = new Map(
  [...document.querySelectorAll(".sig")].map((el) => [el.id, el])
);

const infoButtons = new Map(
  [...document.querySelectorAll(".arrow-info")].map((button) => [button.dataset.signal, button])
);

const signalInfo = {
  sigPcpiReq: {
    title: "PCPI Request",
    body: "<code>pcpi_valid</code>, <code>pcpi_insn</code>, <code>pcpi_rs1</code>, <code>pcpi_rs2</code>"
  },
  sigPcpiResp: {
    title: "PCPI Response",
    body: "<code>pcpi_wait</code>, <code>pcpi_ready</code>, <code>pcpi_wr</code>, <code>pcpi_rd</code>"
  },
  sigAccelStart: {
    title: "Accel Start",
    body: "<code>accel_start</code>"
  },
  sigAccelPayload: {
    title: "Accel Payload",
    body: "<code>a_flat</code>, <code>b_flat</code>"
  },
  sigAccelStatus: {
    title: "Accel Status / Result",
    body: "<code>accel_busy</code>, <code>accel_done</code>, <code>c_flat</code>, <code>accel_cycle_count</code>"
  },
  sigMemReq: {
    title: "Memory Request",
    body: "<code>accel_mem_valid</code>, <code>accel_mem_we</code>, <code>accel_mem_addr</code>, <code>accel_mem_wdata</code>"
  },
  sigMemResp: {
    title: "Memory Response",
    body: "<code>accel_mem_rdata</code>, <code>accel_mem_ready</code>"
  }
};

const cells = [];
for (let r = 0; r < 4; r += 1) {
  for (let c = 0; c < 4; c += 1) {
    const cell = document.createElement("div");
    cell.className = "cell";
    cell.dataset.r = String(r);
    cell.dataset.c = String(c);
    cell.innerHTML = [
      `<span class="cell-tag">PE${r}${c}</span>`,
      `<span class="port port-y-in"></span>`,
      `<span class="port port-x-in"></span>`,
      `<span class="port port-x-out"></span>`,
      `<span class="port port-y-out"></span>`,
      `<span class="flow-arrow flow-arrow-right"></span>`,
      `<span class="flow-arrow flow-arrow-down"></span>`,
      `<div class="cell-center">idle</div>`
    ].join("");
    mesh.appendChild(cell);
    cells.push(cell);
  }
}

const model = {
  state: "IDLE",
  microCycle: 0,
  waitAccCycle: 0,
  running: false,
  timer: null,
  history: []
};

const dragState = {
  mode: null
};

function cloneSnapshot() {
  return {
    state: model.state,
    microCycle: model.microCycle,
    waitAccCycle: model.waitAccCycle
  };
}

function restoreSnapshot(snapshot) {
  model.state = snapshot.state;
  model.microCycle = snapshot.microCycle;
  model.waitAccCycle = snapshot.waitAccCycle;
}

function writeLog(msg) {
  const t = new Date().toLocaleTimeString();
  logBox.textContent += `[${t}] ${msg}\n`;
  logBox.scrollTop = logBox.scrollHeight;
}

function setActiveSignal(id, active) {
  const line = signalLines.get(id);
  if (line) {
    line.classList.toggle("active", active);
  }
  const button = infoButtons.get(id);
  if (button && active && signalPopover.hidden) {
    button.classList.add("active");
  } else if (button && signalPopover.dataset.signal !== id) {
    button.classList.remove("active");
  }
}

function hideSignalPopover() {
  signalPopover.hidden = true;
  signalPopover.dataset.signal = "";
  signalPopoverTitle.textContent = "";
  signalPopoverBody.innerHTML = "";
  infoButtons.forEach((button) => button.classList.remove("active"));
}

function openArchInfo() {
  archInfoModal.hidden = false;
}

function closeArchInfo() {
  archInfoModal.hidden = true;
}

function openCpuInfo() {
  cpuInfoModal.hidden = false;
}

function closeCpuInfo() {
  cpuInfoModal.hidden = true;
}

function openAppGuide() {
  appGuideModal.hidden = false;
}

function closeAppGuide() {
  appGuideModal.hidden = true;
}

function toggleSignalPopover(signalId) {
  const button = infoButtons.get(signalId);
  const info = signalInfo[signalId];
  if (!button || !info) {
    return;
  }

  const alreadyOpen = !signalPopover.hidden && signalPopover.dataset.signal === signalId;
  hideSignalPopover();
  if (alreadyOpen) {
    return;
  }

  const rect = button.getBoundingClientRect();
  const canvasRect = button.offsetParent.getBoundingClientRect();
  signalPopover.hidden = false;
  signalPopover.dataset.signal = signalId;
  signalPopoverTitle.textContent = info.title;
  signalPopoverBody.innerHTML = info.body;
  signalPopover.style.left = `${rect.left - canvasRect.left + 28}px`;
  signalPopover.style.top = `${rect.top - canvasRect.top - 4}px`;
  button.classList.add("active");
}

function clearVisualState() {
  Object.values(elements).forEach((el) => {
    if (el && el.classList) {
      el.classList.remove("active");
    }
  });
  signalLines.forEach((line) => line.classList.remove("active"));
  infoButtons.forEach((button) => button.classList.remove("active"));
  fsmItems.forEach((item) => item.classList.remove("active"));
  cells.forEach((cell) => {
    cell.classList.remove("active", "done");
    cell.querySelectorAll(".port, .flow-arrow").forEach((el) => el.classList.remove("show"));
    cell.querySelector(".cell-center").textContent = "idle";
  });
}

function updateControlButtons() {
  btnRun.disabled = model.running;
  btnStep.disabled = model.running;
  btnStepBack.disabled = model.running || model.history.length === 0;
  btnRun.textContent = model.running ? "Running..." : "Run Full Transaction";
  panelButtons.forEach((button) => {
    switch (button.dataset.control) {
      case "run":
        button.disabled = model.running;
        button.textContent = model.running ? "Running..." : "Run";
        break;
      case "step":
        button.disabled = model.running;
        break;
      case "back":
        button.disabled = model.running || model.history.length === 0;
        break;
      case "reset":
        button.disabled = false;
        break;
      default:
        break;
    }
  });
}

function getDerivedSignals() {
  const loadA = model.state === "LOAD_A";
  const loadB = model.state === "LOAD_B";
  const kick = model.state === "KICK";
  const waitAcc = model.state === "WAIT_ACC";
  const storeC = model.state === "STORE_C";
  const resp = model.state === "RESP";
  const active = model.state !== "IDLE";

  let memAddr = "-";
  let memWdata = "-";
  let memRdata = "-";
  let elemIdx = "-";

  if (loadA) {
    memAddr = "base_a + elem_idx*4";
    memRdata = "A word";
    elemIdx = "0..15 (A)";
  } else if (loadB) {
    memAddr = "base_b + elem_idx*4";
    memRdata = "B word";
    elemIdx = "0..15 (B)";
  } else if (storeC) {
    memAddr = "0x0000_0200 + elem_idx*4";
    memWdata = "signext(c_flat[idx])";
    elemIdx = "0..15 (C)";
  }

  return {
    insnMatch: active ? "1" : "0",
    pcpiValid: active ? "1" : "0",
    pcpiWait: ["LOAD_A", "LOAD_B", "KICK", "WAIT_ACC", "STORE_C"].includes(model.state) ? "1" : "0",
    pcpiReady: resp ? "1" : "0",
    pcpiWr: resp ? "1" : "0",
    pcpiRd: resp ? "c00" : "-",
    respValid: resp ? "1" : "0",
    rs1: active ? "0x00000100 -> base_a" : "-",
    rs2: active ? "0x00000140 -> base_b" : "-",
    elemIdx,
    bufA: loadA ? "filling" : ["LOAD_B", "KICK", "WAIT_ACC", "STORE_C", "RESP"].includes(model.state) ? "loaded" : "empty",
    bufB: loadB ? "filling" : ["KICK", "WAIT_ACC", "STORE_C", "RESP"].includes(model.state) ? "loaded" : "empty",
    memValid: loadA || loadB || storeC ? "1" : "0",
    memWe: storeC ? "1" : "0",
    memAddr,
    memWdata,
    memRdata,
    memReady: loadA || loadB || storeC ? "1" : "0",
    busy: waitAcc ? "1" : "0",
    done: resp ? "1" : "0",
    accelCycle: waitAcc ? `${model.waitAccCycle}` : resp ? "10" : "0"
  };
}

function setSignalText(sig) {
  elements.stateValue.textContent = model.state;
  elements.cycleValue.textContent = String(model.microCycle);
  elements.waitCycleValue.textContent = model.state === "WAIT_ACC" ? `${model.waitAccCycle} / 10` : model.state === "RESP" ? "10 / 10" : "0 / 10";
  elements.sigInsnMatch.textContent = sig.insnMatch;
  elements.sigValid.textContent = sig.pcpiValid;
  elements.sigWait.textContent = sig.pcpiWait;
  elements.sigReady.textContent = sig.pcpiReady;
  elements.sigWr.textContent = sig.pcpiWr;
  elements.sigRd.textContent = sig.pcpiRd;
  elements.sigRespValid.textContent = sig.respValid;
  elements.sigRs1.textContent = sig.rs1;
  elements.sigRs2.textContent = sig.rs2;
  elements.sigElemIdx.textContent = sig.elemIdx;
  elements.sigBufA.textContent = sig.bufA;
  elements.sigBufB.textContent = sig.bufB;
  elements.sigMemValid.textContent = sig.memValid;
  elements.sigMemWe.textContent = sig.memWe;
  elements.sigMemAddr.textContent = sig.memAddr;
  elements.sigMemWdata.textContent = sig.memWdata;
  elements.sigMemRdata.textContent = sig.memRdata;
  elements.sigMemReady.textContent = sig.memReady;
  elements.sigBusy.textContent = sig.busy;
  elements.sigDone.textContent = sig.done;
  elements.sigAccelCycle.textContent = sig.accelCycle;
}

function activateArchitecture(sig) {
  if (model.state !== "IDLE") {
    elements.cpuBlock.classList.add("active");
    elements.wrapperBlock.classList.add("active");
    elements.decodeBlock.classList.add("active");
    setActiveSignal("sigPcpiReq", true);
  }

  if (sig.pcpiWait === "1") {
    elements.memSeqBlock.classList.add("active");
    setActiveSignal("sigPcpiResp", true);
  }

  if (["LOAD_A", "LOAD_B"].includes(model.state)) {
    elements.baseBlock.classList.add("active");
    elements.bufferBlock.classList.add("active");
    elements.memoryBlock.classList.add("active");
    setActiveSignal("sigMemReq", true);
    setActiveSignal("sigMemResp", true);
  }

  if (model.state === "KICK") {
    elements.accelBlock.classList.add("active");
    elements.accelCtrlBlock.classList.add("active");
    setActiveSignal("sigAccelStart", true);
    setActiveSignal("sigAccelPayload", true);
  }

  if (model.state === "WAIT_ACC") {
    elements.accelBlock.classList.add("active");
    elements.accelCtrlBlock.classList.add("active");
    elements.issueBlock.classList.add("active");
    elements.statusBlock.classList.add("active");
    setActiveSignal("sigAccelPayload", true);
    setActiveSignal("sigAccelStatus", true);
  }

  if (model.state === "STORE_C") {
    elements.memoryBlock.classList.add("active");
    elements.respBlock.classList.add("active");
    elements.statusBlock.classList.add("active");
    setActiveSignal("sigMemReq", true);
    setActiveSignal("sigAccelStatus", true);
  }

  if (model.state === "RESP") {
    elements.respBlock.classList.add("active");
    setActiveSignal("sigPcpiResp", true);
    setActiveSignal("sigAccelStatus", true);
  }
}

function paintSystolicWave(cycle) {
  cells.forEach((cell) => {
    const r = Number(cell.dataset.r);
    const c = Number(cell.dataset.c);
    const start = r + c;
    const end = start + 3;
    const xIn = cell.querySelector(".port-x-in");
    const yIn = cell.querySelector(".port-y-in");
    const xOut = cell.querySelector(".port-x-out");
    const yOut = cell.querySelector(".port-y-out");
    const rightArrow = cell.querySelector(".flow-arrow-right");
    const downArrow = cell.querySelector(".flow-arrow-down");
    const center = cell.querySelector(".cell-center");

    if (cycle >= start && cycle <= end) {
      const k = cycle - start;
      const aVal = `A${r}${k}`;
      const bVal = `B${k}${c}`;
      cell.classList.add("active");
      xIn.textContent = `xin ${aVal}`;
      yIn.textContent = `yin ${bVal}`;
      xOut.textContent = `xout ${aVal}`;
      yOut.textContent = `yout ${bVal}`;
      [xIn, yIn, xOut, yOut, rightArrow, downArrow].forEach((el) => el.classList.add("show"));
      center.innerHTML = `MAC<br><code>k=${k}</code>`;
    } else if (cycle > end) {
      cell.classList.add("done");
      center.innerHTML = `done<br><code>z_acc</code>`;
    }
  });
}

function render() {
  clearVisualState();
  const sig = getDerivedSignals();
  setSignalText(sig);
  const meta = stateMeta[model.state];
  elements.stateTitle.textContent = meta.title;
  elements.stateDesc.textContent = meta.desc;
  fsmItems.get(model.state)?.classList.add("active");
  activateArchitecture(sig);

  if (model.state === "WAIT_ACC") {
    paintSystolicWave(model.waitAccCycle);
  } else if (model.state === "RESP") {
    cells.forEach((cell) => {
      cell.classList.add("done");
      cell.querySelector(".cell-center").innerHTML = `done<br><code>z_acc</code>`;
    });
  }

  updateControlButtons();
}

function pushHistory() {
  model.history.push(cloneSnapshot());
}

function advanceOneTick() {
  pushHistory();
  model.microCycle += 1;

  switch (model.state) {
    case "IDLE":
      model.state = "LOAD_A";
      writeLog("Custom instruction matched. Wrapper enters S_LOAD_A and starts the A read burst.");
      break;
    case "LOAD_A":
      model.state = "LOAD_B";
      writeLog("A burst complete. Wrapper enters S_LOAD_B.");
      break;
    case "LOAD_B":
      model.state = "KICK";
      writeLog("B burst complete. Wrapper enters S_KICK.");
      break;
    case "KICK":
      model.state = "WAIT_ACC";
      model.waitAccCycle = 0;
      writeLog("One-cycle accel_start pulse issued. Accelerator becomes busy.");
      break;
    case "WAIT_ACC":
      model.waitAccCycle += 1;
      writeLog(`WAIT_ACC ${model.waitAccCycle}/10: PE cells receive aligned operands and forward x_out/y_out.`);
      if (model.waitAccCycle >= 10) {
        model.state = "STORE_C";
        writeLog("accel_done observed. Wrapper enters S_STORE_C.");
      }
      break;
    case "STORE_C":
      model.state = "RESP";
      writeLog("C writeback complete. Wrapper enters S_RESP.");
      break;
    case "RESP":
      model.state = "IDLE";
      model.running = false;
      if (model.timer) {
        clearInterval(model.timer);
        model.timer = null;
      }
      writeLog("Transaction retired. CPU resumes normal execution.");
      break;
    default:
      model.state = "IDLE";
      break;
  }

  render();
}

function stepBack() {
  if (model.running || model.history.length === 0) {
    return;
  }
  const snapshot = model.history.pop();
  restoreSnapshot(snapshot);
  writeLog(`Stepped back to ${model.state}.`);
  render();
}

function runFull() {
  if (model.running) {
    return;
  }
  if (model.state === "RESP") {
    model.state = "IDLE";
    model.microCycle = 0;
    model.waitAccCycle = 0;
    model.history = [];
  }
  model.running = true;
  render();
  writeLog("Starting full transaction animation.");
  model.timer = setInterval(() => {
    advanceOneTick();
    if (!model.running && model.timer) {
      clearInterval(model.timer);
      model.timer = null;
    }
  }, 800);
}

function stepOnce() {
  if (model.running) {
    return;
  }
  advanceOneTick();
}

function resetAll() {
  if (model.timer) {
    clearInterval(model.timer);
    model.timer = null;
  }
  model.running = false;
  model.state = "IDLE";
  model.microCycle = 0;
  model.waitAccCycle = 0;
  model.history = [];
  logBox.textContent = "";
  writeLog("Reset to S_IDLE.");
  render();
}

function startDrag(mode, event) {
  if (window.innerWidth <= 1320) {
    return;
  }
  dragState.mode = mode;
  document.body.style.userSelect = "none";
  document.body.style.cursor = mode === "column" ? "col-resize" : "row-resize";
  event.preventDefault();
}

function handleDrag(event) {
  if (!dragState.mode) {
    return;
  }

  const rect = workspace.getBoundingClientRect();

  if (dragState.mode === "column") {
    const splitterWidth = 12;
    const minLeft = 680;
    const minRight = 420;
    let left = event.clientX - rect.left;
    left = Math.max(minLeft, Math.min(left, rect.width - minRight - splitterWidth));
    const right = rect.width - left - splitterWidth - 14;
    workspace.style.setProperty("--left-col", `${left}px`);
    workspace.style.setProperty("--right-col", `${Math.max(minRight, right)}px`);
    return;
  }

  if (dragState.mode === "row") {
    const splitterHeight = 12;
    const minTop = 420;
    const minBottom = 320;
    let top = event.clientY - rect.top;
    top = Math.max(minTop, Math.min(top, rect.height - minBottom - splitterHeight));
    const bottom = rect.height - top - splitterHeight - 14;
    workspace.style.setProperty("--top-row", `${top}px`);
    workspace.style.setProperty("--bottom-row", `${Math.max(minBottom, bottom)}px`);
  }
}

function stopDrag() {
  if (!dragState.mode) {
    return;
  }
  dragState.mode = null;
  document.body.style.userSelect = "";
  document.body.style.cursor = "";
}

btnRun.addEventListener("click", runFull);
btnStep.addEventListener("click", stepOnce);
btnStepBack.addEventListener("click", stepBack);
btnReset.addEventListener("click", resetAll);
panelButtons.forEach((button) => {
  button.addEventListener("click", () => {
    switch (button.dataset.control) {
      case "run":
        runFull();
        break;
      case "step":
        stepOnce();
        break;
      case "back":
        stepBack();
        break;
      case "reset":
        resetAll();
        break;
      default:
        break;
    }
  });
});
btnArchInfo?.addEventListener("click", openArchInfo);
btnArchInfoClose?.addEventListener("click", closeArchInfo);
archInfoBackdrop?.addEventListener("click", closeArchInfo);
btnCpuInfo?.addEventListener("click", openCpuInfo);
btnCpuInfoClose?.addEventListener("click", closeCpuInfo);
cpuInfoBackdrop?.addEventListener("click", closeCpuInfo);
btnAppGuide?.addEventListener("click", openAppGuide);
btnAppGuideClose?.addEventListener("click", closeAppGuide);
appGuideBackdrop?.addEventListener("click", closeAppGuide);
infoButtons.forEach((button, signalId) => {
  button.addEventListener("click", (event) => {
    event.stopPropagation();
    toggleSignalPopover(signalId);
  });
});
columnSplitter?.addEventListener("mousedown", (event) => startDrag("column", event));
rowSplitter?.addEventListener("mousedown", (event) => startDrag("row", event));
window.addEventListener("mousemove", handleDrag);
window.addEventListener("mouseup", stopDrag);
window.addEventListener("mouseleave", stopDrag);
window.addEventListener("click", (event) => {
  if (!signalPopover.hidden && !signalPopover.contains(event.target) && !event.target.classList.contains("arrow-info")) {
    hideSignalPopover();
  }
});
window.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    hideSignalPopover();
    closeArchInfo();
    closeCpuInfo();
    closeAppGuide();
  }
});

resetAll();
