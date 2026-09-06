const button = document.querySelector("#toggle");
const status = document.querySelector("#status");
let tabID = null;
let enabled = false;

function supported(url) {
  return typeof url === "string" && (url.startsWith("https://www.youtube.com/") || url.startsWith("https://music.youtube.com/"));
}

function render() {
  button.disabled = tabID === null;
  button.textContent = enabled ? "Disable EQ for This Tab" : "Enable EQ for This Tab";
}

async function initialize() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || !Number.isInteger(tab.id) || !supported(tab.url)) {
    status.textContent = "Open a YouTube or YouTube Music tab first.";
    return;
  }
  tabID = tab.id;
  const state = await chrome.runtime.sendMessage({ type: "nodebay-popup-status", tabID });
  enabled = state?.enabled === true;
  render();
}

button.addEventListener("click", async () => {
  button.disabled = true;
  status.textContent = enabled ? "Restoring normal tab audio…" : "Enabling local audio processing…";
  const result = await chrome.runtime.sendMessage({
    type: enabled ? "nodebay-disable-eq" : "nodebay-enable-eq",
    tabID
  }).catch((error) => ({ ok: false, error: error?.message }));
  if (result?.ok) {
    enabled = !enabled;
    status.textContent = enabled ? "Enabled. Adjust it in Nodebay." : "Disabled.";
  } else {
    status.textContent = result?.error || "Equalizer could not be changed.";
  }
  render();
});

initialize();
