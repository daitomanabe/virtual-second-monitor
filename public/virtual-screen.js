export const CHANNEL_NAME = "virtual-second-monitor";
export const STORAGE_KEY = "virtual-second-monitor-state";

export const presets = [
  { label: "HD", width: 1280, height: 720 },
  { label: "FHD", width: 1920, height: 1080 },
  { label: "WUXGA", width: 1920, height: 1200 },
  { label: "4K", width: 3840, height: 2160 },
  { label: "8K", width: 7680, height: 4320 },
  { label: "Portrait", width: 1080, height: 1920 },
  { label: "Square", width: 1080, height: 1080 }
];

export const defaultState = {
  width: 1920,
  height: 1080,
  mode: "pattern",
  pattern: "bars",
  targetUrl: "http://localhost:3000/",
  mediaSrc: "",
  mediaType: "",
  fillColor: "#111820",
  showHud: true,
  showGrid: true,
  showSafeArea: false,
  showCursor: true,
  zoom: 42,
  cursorX: null,
  cursorY: null,
  updatedAt: Date.now()
};

export function loadState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return { ...defaultState };
    return normalizeState({ ...defaultState, ...JSON.parse(raw) });
  } catch {
    return { ...defaultState };
  }
}

export function saveState(state) {
  const stateForStorage = { ...state };
  if (stateForStorage.mediaSrc.length > 1_500_000) {
    stateForStorage.mediaSrc = "";
    stateForStorage.mediaType = "";
  }
  localStorage.setItem(STORAGE_KEY, JSON.stringify(stateForStorage));
}

export function normalizeState(state) {
  return {
    ...defaultState,
    ...state,
    width: clampInt(state.width, 160, 7680, defaultState.width),
    height: clampInt(state.height, 120, 4320, defaultState.height),
    zoom: clampInt(state.zoom, 10, 100, defaultState.zoom),
    mode: ["pattern", "url", "media", "solid"].includes(state.mode) ? state.mode : defaultState.mode,
    pattern: ["bars", "checker", "gradient", "coordinates"].includes(state.pattern) ? state.pattern : defaultState.pattern
  };
}

export function createChannel(onMessage) {
  const channel = new BroadcastChannel(CHANNEL_NAME);
  channel.addEventListener("message", (event) => onMessage(event.data));
  return channel;
}

export function publishState(channel, state) {
  channel.postMessage({ type: "state", state: { ...state, updatedAt: Date.now() } });
}

export function renderVirtualScreen(root, state) {
  root.style.setProperty("--screen-width", `${state.width}px`);
  root.style.setProperty("--screen-height", `${state.height}px`);
  root.replaceChildren();

  root.appendChild(renderContent(state));

  if (state.showGrid) {
    root.appendChild(el("div", "grid-overlay"));
  }

  if (state.showSafeArea) {
    root.appendChild(el("div", "safe-overlay"));
  }

  if (state.showHud) {
    const hud = el("div", "hud-overlay");
    const cursor = state.cursorX === null ? "-, -" : `${Math.round(state.cursorX)}, ${Math.round(state.cursorY)}`;
    hud.innerHTML = [
      `RES ${state.width} x ${state.height}`,
      `MODE ${state.mode.toUpperCase()}`,
      `DPR ${window.devicePixelRatio.toFixed(2)}`,
      `PTR ${cursor}`
    ].join("<br>");
    root.appendChild(hud);
  }

  if (state.showCursor && state.cursorX !== null && state.cursorY !== null) {
    const cursor = el("div", "cursor-overlay");
    cursor.style.left = `${state.cursorX}px`;
    cursor.style.top = `${state.cursorY}px`;
    root.appendChild(cursor);
  }
}

export function fitScale(container, state, maxScale = 1) {
  const rect = container.getBoundingClientRect();
  const padding = 34;
  const widthScale = Math.max(0.01, (rect.width - padding) / state.width);
  const heightScale = Math.max(0.01, (rect.height - padding) / state.height);
  return Math.min(maxScale, widthScale, heightScale);
}

export function applyScale(scaleEl, state, scale) {
  scaleEl.style.width = `${state.width}px`;
  scaleEl.style.height = `${state.height}px`;
  scaleEl.style.transform = `translate(-${(state.width * scale) / 2}px, -${(state.height * scale) / 2}px) scale(${scale})`;
}

export function bindPointerTelemetry(screen, getState, onPointer) {
  screen.addEventListener("pointermove", (event) => {
    const state = getState();
    const rect = screen.getBoundingClientRect();
    const x = clamp((event.clientX - rect.left) / rect.width * state.width, 0, state.width);
    const y = clamp((event.clientY - rect.top) / rect.height * state.height, 0, state.height);
    onPointer(x, y);
  });

  screen.addEventListener("pointerleave", () => onPointer(null, null));
}

function renderContent(state) {
  if (state.mode === "url") {
    if (!state.targetUrl) return emptyState("Enter a target URL");
    const iframe = el("iframe", "url-content");
    iframe.src = state.targetUrl;
    iframe.allow = "fullscreen; autoplay; clipboard-read; clipboard-write";
    return iframe;
  }

  if (state.mode === "media") {
    if (!state.mediaSrc) return emptyState("Drop media in controller");
    if (state.mediaType.startsWith("video/")) {
      const video = el("video", "media-content");
      video.src = state.mediaSrc;
      video.autoplay = true;
      video.loop = true;
      video.muted = true;
      video.playsInline = true;
      return video;
    }
    const image = el("img", "media-content");
    image.src = state.mediaSrc;
    image.alt = "Virtual display media";
    return image;
  }

  if (state.mode === "solid") {
    const solid = el("div", "solid-content");
    solid.style.background = state.fillColor;
    return solid;
  }

  return renderPattern(state);
}

function renderPattern(state) {
  if (state.pattern === "bars") {
    const bars = el("div", "pattern pattern-bars");
    ["white", "yellow", "cyan", "green", "magenta", "red", "blue", "black"].forEach((name) => {
      bars.appendChild(el("div", `bar-${name}`));
    });
    return bars;
  }

  if (state.pattern === "coordinates") {
    const coordinates = el("div", "pattern pattern-coordinates");
    const points = [
      [0, 0],
      [state.width / 2, 0],
      [0, state.height / 2],
      [state.width / 2, state.height / 2]
    ];
    points.forEach(([x, y]) => {
      const label = el("div", "coordinate-label", `${Math.round(x)}, ${Math.round(y)}`);
      label.style.left = `${x}px`;
      label.style.top = `${y}px`;
      coordinates.appendChild(label);
    });
    return coordinates;
  }

  return el("div", `pattern pattern-${state.pattern}`);
}

function emptyState(text) {
  return el("div", "empty-state", text);
}

function el(tagName, className, text = "") {
  const node = document.createElement(tagName);
  if (className) node.className = className;
  if (text) node.textContent = text;
  return node;
}

function clampInt(value, min, max, fallback) {
  const next = Number.parseInt(value, 10);
  if (!Number.isFinite(next)) return fallback;
  return Math.min(max, Math.max(min, next));
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}
