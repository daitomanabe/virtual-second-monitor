import {
  bindPointerTelemetry,
  createChannel,
  fitScale,
  loadState,
  normalizeState,
  publishState,
  renderVirtualScreen,
  applyScale
} from "/virtual-screen.js";

const elements = {
  displayStage: document.querySelector("#displayStage"),
  displayScale: document.querySelector("#displayScale"),
  displayScreen: document.querySelector("#displayScreen"),
  displaySizeLabel: document.querySelector("#displaySizeLabel"),
  displayFit: document.querySelector("#displayFit"),
  displayFullscreen: document.querySelector("#displayFullscreen")
};

let state = normalizeState(loadState());
let scale = 1;
const channel = createChannel(handleChannelMessage);

init();

function init() {
  elements.displayFit.addEventListener("click", render);
  elements.displayFullscreen.addEventListener("click", () => {
    if (!document.fullscreenElement) {
      document.documentElement.requestFullscreen();
    } else {
      document.exitFullscreen();
    }
  });

  bindPointerTelemetry(elements.displayScreen, () => state, (x, y) => {
    channel.postMessage({ type: "pointer", x, y });
  });

  window.addEventListener("resize", render);
  channel.postMessage({ type: "display-ready" });
  setInterval(() => channel.postMessage({ type: "display-heartbeat" }), 700);
  render();
}

function handleChannelMessage(message) {
  if (message?.type !== "state") return;
  state = normalizeState(message.state);
  render();
}

function render() {
  scale = fitScale(elements.displayStage, state, 1);
  elements.displaySizeLabel.textContent = `${state.width} x ${state.height} at ${Math.round(scale * 100)}%`;
  renderVirtualScreen(elements.displayScreen, state);
  applyScale(elements.displayScale, state, scale);
  publishState(channel, state);
}
