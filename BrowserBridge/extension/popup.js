const button = document.querySelector("#toggle");
const status = document.querySelector("#status");
const allMediaButton = document.querySelector("#all-media");
const mediaStatus = document.querySelector("#media-status");
let tabID = null;
let enabled = false;
let allMediaEnabled = false;

function supported(url) {
  return typeof url === "string" && (url.startsWith("https://www.youtube.com/") || url.startsWith("https://music.youtube.com/"));
}

function render() {
  button.disabled = tabID === null;
  button.textContent = enabled ? "Disable EQ for This Tab" : "Enable EQ for This Tab";
  allMediaButton.disabled = allMediaEnabled;
  allMediaButton.textContent = allMediaEnabled ? "Media on Other Sites Enabled" : "Enable Media on Other Sites";
}

async function initialize() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const state = await chrome.runtime.sendMessage({ type: "nodebay-popup-status", tabID: tab?.id });
  allMediaEnabled = state?.allMediaEnabled === true;
  mediaStatus.textContent = allMediaEnabled ? "Open media tabs appear in Nodebay." : "YouTube tabs work now. Other sites need your permission.";
  if (!tab || !Number.isInteger(tab.id) || !supported(tab.url)) {
    status.textContent = "Open a YouTube or YouTube Music tab for EQ.";
    render();
    return;
  }
  tabID = tab.id;
  enabled = state?.enabled === true;
  render();
}

allMediaButton.addEventListener("click", async () => {
  allMediaButton.disabled = true;
  const granted = await chrome.permissions.request({ origins: ["http://*/*", "https://*/*"] })
    .catch(() => false);
  const result = granted
    ? await chrome.runtime.sendMessage({ type: "nodebay-refresh-all-media" })
      .catch((error) => ({ ok: false, error: error?.message }))
    : { ok: false };
  allMediaEnabled = result?.ok === true;
  mediaStatus.textContent = allMediaEnabled
    ? "Open media tabs appear in Nodebay."
    : result?.error || "Permission was not granted.";
  render();
});

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
