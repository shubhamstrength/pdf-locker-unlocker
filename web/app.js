"use strict";

const $ = (sel) => document.querySelector(sel);
const worker = new Worker("worker.js");
const pending = new Map();
let nextId = 0;

function call(action, bytes, options = {}) {
  return new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    // Send a copy so the original stays usable for a retry with another password.
    const copy = bytes.slice();
    worker.postMessage({ id, action, bytes: copy, options }, [copy.buffer]);
  });
}

worker.onmessage = ({ data }) => {
  const p = pending.get(data.id);
  pending.delete(data.id);
  if (data.error) p.reject(new Error(data.error));
  else p.resolve(data.result);
};

const state = { mode: "lock", files: [], busy: false };

const PROTECTION_LABEL = {
  none: "Not protected",
  password: "Password protected",
  restricted: "Opens freely, has restrictions",
  invalid: "Not a valid PDF",
};

// ---- Files ----

async function addFiles(list) {
  const added = [...list].filter(
    (f) => (f.type === "application/pdf" || /\.pdf$/i.test(f.name)) &&
      !state.files.some((x) => x.file.name === f.name && x.file.size === f.size && x.file.lastModified === f.lastModified)
  );
  if (!added.length) {
    if (list.length) showMessage("Only PDF files can be added.", true);
    return;
  }
  for (const file of added) {
    state.files.push({ id: crypto.randomUUID(), file, bytes: null, protection: null, result: null, error: null });
  }
  render();
  await Promise.all(state.files.filter((f) => !f.protection).map(async (item) => {
    item.bytes = new Uint8Array(await item.file.arrayBuffer());
    try {
      item.protection = await call("inspect", item.bytes);
    } catch {
      item.protection = "invalid";
    }
  }));
  // Switch to the mode that matches what was added.
  const usable = state.files.filter((f) => f.protection !== "invalid");
  if (usable.length && usable.every((f) => f.protection !== "none")) setMode("unlock");
  else if (usable.length && usable.every((f) => f.protection === "none")) setMode("lock");
  render();
}

function removeFile(id) {
  const item = state.files.find((f) => f.id === id);
  if (item?.result) URL.revokeObjectURL(item.result.url);
  state.files = state.files.filter((f) => f.id !== id);
  render();
}

function outputName(name, suffix) {
  return name.replace(/\.pdf$/i, "") + "-" + suffix + ".pdf";
}

// ---- Rendering ----

function render() {
  const ul = $("#files");
  ul.replaceChildren(...state.files.map((item) => {
    const li = document.createElement("li");
    const info = document.createElement("div");
    info.className = "info";
    const name = document.createElement("div");
    name.className = "name";
    name.textContent = item.file.name;
    const status = document.createElement("div");
    status.className = "status";
    if (item.error) {
      status.textContent = item.error;
      status.classList.add("err");
    } else if (item.result) {
      status.textContent = state.mode === "lock" ? "Locked" : "Unlocked";
      status.classList.add("ok");
    } else {
      status.textContent = item.busy ? "Working…" : item.protection ? PROTECTION_LABEL[item.protection] : "Reading…";
      if (item.protection === "invalid") status.classList.add("err");
    }
    info.append(name, status);
    li.append(info);

    if (item.result) {
      const a = document.createElement("a");
      a.className = "download";
      a.href = item.result.url;
      a.download = item.result.name;
      a.textContent = "Download";
      li.append(a);
    }
    const rm = document.createElement("button");
    rm.type = "button";
    rm.className = "remove";
    rm.setAttribute("aria-label", `Remove ${item.file.name}`);
    rm.textContent = "×";
    rm.onclick = () => removeFile(item.id);
    li.append(rm);
    return li;
  }));

  const n = state.files.filter((f) => f.protection && f.protection !== "invalid").length;
  const verb = state.mode === "lock" ? "Lock" : "Unlock";
  $("#run").textContent = state.busy ? "Working…" : `${verb} ${n > 1 ? n + " PDFs" : "PDF"}`;
  $("#run").disabled = state.busy || validate() !== null;
  const problem = state.files.length ? validate() : null;
  if (!state.busy && problem) showMessage(problem);
  else if (!state.busy) showMessage("");
}

function showMessage(text, isError = false) {
  const m = $("#message");
  m.textContent = text;
  m.classList.toggle("err", isError);
}

function validate() {
  const ready = state.files.filter((f) => f.protection && f.protection !== "invalid");
  if (!ready.length) return state.files.length ? "Waiting for a valid PDF." : "Add one or more PDFs.";
  const pw = $("#password").value;
  if (state.mode === "lock") {
    if (ready.some((f) => f.protection !== "none")) return "Some PDFs are already protected. Unlock them first or remove them.";
    if (!pw) return "Choose a password.";
    if (pw !== $("#confirm").value) return "Passwords don't match.";
    if ($("#restrict").open) {
      const owner = $("#owner").value;
      if (!owner) return "Choose a permissions password.";
      if (owner === pw) return "Use a permissions password that differs from the open password.";
    }
  } else {
    if (ready.some((f) => f.protection === "none")) return "Some PDFs aren't protected. Remove them to continue.";
    if (!pw && ready.some((f) => f.protection === "password")) return "Enter the PDF's password.";
  }
  return null;
}

function setMode(mode) {
  if (state.mode === mode) return;
  state.mode = mode;
  document.body.dataset.mode = mode;
  for (const tab of document.querySelectorAll("[role=tab]")) {
    tab.setAttribute("aria-selected", String(tab.dataset.mode === mode));
  }
  for (const f of state.files) {
    if (f.result) URL.revokeObjectURL(f.result.url);
    f.result = null;
    f.error = null;
  }
  render();
}

// ---- Run ----

async function run() {
  if (validate()) return;
  state.busy = true;
  render();
  const password = $("#password").value;
  const restrict = $("#restrict").open;
  const options = state.mode === "lock"
    ? {
        userPassword: password,
        ownerPassword: restrict ? $("#owner").value : "",
        allowPrint: !restrict || $("#allow-print").checked,
        allowCopy: !restrict || $("#allow-copy").checked,
        allowEdit: !restrict || $("#allow-edit").checked,
      }
    : { password };

  let done = 0;
  for (const item of state.files) {
    if (!item.protection || item.protection === "invalid" || item.result) continue;
    item.busy = true;
    item.error = null;
    render();
    try {
      const out = await call(state.mode, item.bytes, options);
      const blob = new Blob([out], { type: "application/pdf" });
      const name = outputName(item.file.name, state.mode === "lock" ? "locked" : "unlocked");
      item.result = { url: URL.createObjectURL(blob), name };
      done++;
    } catch (e) {
      item.error = e.message;
    }
    item.busy = false;
  }
  state.busy = false;
  render();

  // A single result downloads straight away; several get a Download link each.
  if (done === 1 && state.files.filter((f) => f.result).length === 1) document.querySelector(".files a.download")?.click();
  if (done) showMessage(done === 1 ? "Done. Your file is ready." : `Done. ${done} files are ready to download.`);
}

// ---- Wiring ----

document.body.dataset.mode = state.mode;

for (const tab of document.querySelectorAll("[role=tab]")) {
  tab.addEventListener("click", () => setMode(tab.dataset.mode));
}

const drop = $("#drop");
drop.tabIndex = 0;
drop.addEventListener("keydown", (e) => {
  if (e.key === "Enter" || e.key === " ") {
    e.preventDefault();
    $("#file-input").click();
  }
});
$("#file-input").addEventListener("change", (e) => {
  addFiles(e.target.files);
  e.target.value = "";
});
for (const ev of ["dragenter", "dragover"]) {
  drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add("over"); });
}
for (const ev of ["dragleave", "drop"]) {
  drop.addEventListener(ev, () => drop.classList.remove("over"));
}
drop.addEventListener("drop", (e) => {
  e.preventDefault();
  addFiles(e.dataTransfer.files);
});
// Dropping outside the box shouldn't navigate away from the page.
window.addEventListener("dragover", (e) => e.preventDefault());
window.addEventListener("drop", (e) => e.preventDefault());

for (const btn of document.querySelectorAll(".reveal")) {
  btn.addEventListener("click", () => {
    const input = btn.previousElementSibling;
    const show = input.type === "password";
    input.type = show ? "text" : "password";
    btn.textContent = show ? "Hide" : "Show";
    btn.setAttribute("aria-label", show ? "Hide password" : "Show password");
  });
}

$("#form").addEventListener("input", render);
$("#restrict").addEventListener("toggle", render);
$("#form").addEventListener("submit", (e) => {
  e.preventDefault();
  run();
});

render();
