import {
  bindPointerTelemetry,
  createChannel,
  defaultState,
  fitScale,
  loadState,
  normalizeState,
  presets,
  publishState,
  renderVirtualScreen,
  saveState,
  applyScale
} from "/virtual-screen.js";

const elements = {
  displayStatus: document.querySelector("#displayStatus"),
  openDisplay: document.querySelector("#openDisplay"),
  presetGrid: document.querySelector("#presetGrid"),
  widthInput: document.querySelector("#widthInput"),
  heightInput: document.querySelector("#heightInput"),
  modeTabs: document.querySelector("#modeTabs"),
  patternSelect: document.querySelector("#patternSelect"),
  urlInput: document.querySelector("#urlInput"),
  mediaInput: document.querySelector("#mediaInput"),
  colorInput: document.querySelector("#colorInput"),
  hudToggle: document.querySelector("#hudToggle"),
  gridToggle: document.querySelector("#gridToggle"),
  safeToggle: document.querySelector("#safeToggle"),
  cursorToggle: document.querySelector("#cursorToggle"),
  zoomInput: document.querySelector("#zoomInput"),
  zoomReadout: document.querySelector("#zoomReadout"),
  fitPreview: document.querySelector("#fitPreview"),
  copyUrl: document.querySelector("#copyUrl"),
  previewViewport: document.querySelector("#previewViewport"),
  previewScale: document.querySelector("#previewScale"),
  previewScreen: document.querySelector("#previewScreen"),
  screenLabel: document.querySelector("#screenLabel"),
  modeLabel: document.querySelector("#modeLabel"),
  pointerLabel: document.querySelector("#pointerLabel"),
  patternControl: document.querySelector("#patternControl"),
  urlControl: document.querySelector("#urlControl"),
  mediaControl: document.querySelector("#mediaControl"),
  solidControl: document.querySelector("#solidControl")
};

let state = normalizeState(loadState());
let displayWindow = null;
let displayHeartbeat = 0;
const channel = createChannel(handleChannelMessage);

init();

function init() {
  renderPresetButtons();
  bindControls();
  bindPointerTelemetry(elements.previewScreen, () => state, (x, y) => {
    updateState({ cursorX: x, cursorY: y }, { transient: true });
  });
  window.addEventListener("resize", render);
  setInterval(updateDisplayStatus, 600);
  render();
  publish();
}

function bindControls() {
  elements.openDisplay.addEventListener("click", () => {
    displayWindow = window.open("/display.html", "virtual-second-display", "popup,width=1280,height=760");
    setTimeout(publish, 250);
  });

  elements.widthInput.addEventListener("input", () => updateState({ width: elements.widthInput.value }));
  elements.heightInput.addEventListener("input", () => updateState({ height: elements.heightInput.value }));

  elements.modeTabs.addEventListener("click", (event) => {
    const button = event.target.closest("[data-mode]");
    if (!button) return;
    updateState({ mode: button.dataset.mode });
  });

  elements.patternSelect.addEventListener("change", () => updateState({ pattern: elements.patternSelect.value }));
  elements.urlInput.addEventListener("change", () => updateState({ targetUrl: normalizeUrl(elements.urlInput.value) }));
  elements.colorInput.addEventListener("input", () => updateState({ fillColor: elements.colorInput.value }));

  elements.hudToggle.addEventListener("change", () => updateState({ showHud: elements.hudToggle.checked }));
  elements.gridToggle.addEventListener("change", () => updateState({ showGrid: elements.gridToggle.checked }));
  elements.safeToggle.addEventListener("change", () => updateState({ showSafeArea: elements.safeToggle.checked }));
  elements.cursorToggle.addEventListener("change", () => updateState({ showCursor: elements.cursorToggle.checked }));

  elements.zoomInput.addEventListener("input", () => updateState({ zoom: elements.zoomInput.value }, { localOnly: true }));
  elements.fitPreview.addEventListener("click", () => {
    const fit = Math.round(fitScale(elements.previewViewport, state, 1) * 100);
    updateState({ zoom: fit }, { localOnly: true });
  });

  elements.copyUrl.addEventListener("click", async () => {
    await navigator.clipboard.writeText(new URL("/display.html", window.location.href).href);
    elements.copyUrl.textContent = "Copied";
    setTimeout(() => {
      elements.copyUrl.textContent = "Copy URL";
    }, 1100);
  });

  elements.mediaInput.addEventListener("change", () => {
    const file = elements.mediaInput.files?.[0];
    if (file) readMediaFile(file);
  });

  ["dragenter", "dragover"].forEach((eventName) => {
    elements.mediaControl.addEventListener(eventName, (event) => {
      event.preventDefault();
      elements.mediaControl.classList.add("dragging");
    });
  });

  ["dragleave", "drop"].forEach((eventName) => {
    elements.mediaControl.addEventListener(eventName, (event) => {
      event.preventDefault();
      elements.mediaControl.classList.remove("dragging");
    });
  });

  elements.mediaControl.addEventListener("drop", (event) => {
    const file = event.dataTransfer.files?.[0];
    if (file) readMediaFile(file);
  });
}

function renderPresetButtons() {
  elements.presetGrid.replaceChildren();
  presets.forEach((preset) => {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = `${preset.label} ${preset.width}x${preset.height}`;
    button.addEventListener("click", () => updateState({ width: preset.width, height: preset.height }));
    elements.presetGrid.appendChild(button);
  });
}

function updateState(patch, options = {}) {
  state = normalizeState({ ...state, ...patch, updatedAt: Date.now() });
  render();

  if (!options.transient) saveState(state);
  if (!options.localOnly) publish();
}

function publish() {
  publishState(channel, state);
}

function render() {
  elements.widthInput.value = state.width;
  elements.heightInput.value = state.height;
  elements.patternSelect.value = state.pattern;
  elements.urlInput.value = state.targetUrl;
  elements.colorInput.value = state.fillColor;
  elements.hudToggle.checked = state.showHud;
  elements.gridToggle.checked = state.showGrid;
  elements.safeToggle.checked = state.showSafeArea;
  elements.cursorToggle.checked = state.showCursor;
  elements.zoomInput.value = state.zoom;
  elements.zoomReadout.textContent = state.zoom;

  elements.screenLabel.textContent = `${state.width} x ${state.height}`;
  elements.modeLabel.textContent = state.mode.charAt(0).toUpperCase() + state.mode.slice(1);
  elements.pointerLabel.textContent = state.cursorX === null ? "x: -, y: -" : `x: ${Math.round(state.cursorX)}, y: ${Math.round(state.cursorY)}`;

  for (const button of elements.presetGrid.querySelectorAll("button")) {
    const preset = presets.find((item) => button.textContent.includes(`${item.width}x${item.height}`));
    button.classList.toggle("active", Boolean(preset && preset.width === state.width && preset.height === state.height));
  }

  for (const button of elements.modeTabs.querySelectorAll("[data-mode]")) {
    button.classList.toggle("active", button.dataset.mode === state.mode);
  }

  elements.patternControl.classList.toggle("hidden", state.mode !== "pattern");
  elements.urlControl.classList.toggle("hidden", state.mode !== "url");
  elements.mediaControl.classList.toggle("hidden", state.mode !== "media");
  elements.solidControl.classList.toggle("hidden", state.mode !== "solid");

  renderVirtualScreen(elements.previewScreen, state);
  applyScale(elements.previewScale, state, state.zoom / 100);
}

function handleChannelMessage(message) {
  if (message?.type === "display-ready") {
    displayHeartbeat = Date.now();
    publish();
  }

  if (message?.type === "display-heartbeat") {
    displayHeartbeat = Date.now();
  }

  if (message?.type === "pointer") {
    updateState({ cursorX: message.x, cursorY: message.y }, { transient: true });
  }
}

function updateDisplayStatus() {
  const online = Date.now() - displayHeartbeat < 1800 || (displayWindow && !displayWindow.closed);
  elements.displayStatus.textContent = online ? "Display online" : "Display offline";
  elements.displayStatus.classList.toggle("online", online);
}

function readMediaFile(file) {
  if (!file.type.startsWith("image/") && !file.type.startsWith("video/")) return;

  const reader = new FileReader();
  reader.addEventListener("load", () => {
    updateState({
      mode: "media",
      mediaSrc: String(reader.result || ""),
      mediaType: file.type
    });
  });
  reader.readAsDataURL(file);
}

function normalizeUrl(value) {
  const trimmed = value.trim();
  if (!trimmed) return defaultState.targetUrl;
  if (/^https?:\/\//i.test(trimmed)) return trimmed;
  if (trimmed.startsWith("/")) return new URL(trimmed, window.location.href).href;
  return `http://${trimmed}`;
}
