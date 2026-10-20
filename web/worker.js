// Runs qpdf (compiled to WebAssembly) off the main thread. Files are processed in memory and never uploaded.
importScripts("vendor/qpdf.js"); // defines the global `Module` factory

const wasmUrl = new URL("vendor/qpdf.wasm", self.location).href;

async function qpdf(args, input) {
  // A fresh instance per call keeps qpdf's global state from leaking between files.
  // The browser caches the .wasm download, so only the first call fetches it.
  const q = await Module({ locateFile: () => wasmUrl }).catch(() => {
    throw new Error("Could not load the PDF engine. Check your connection and reload the page.");
  });
  q.FS.writeFile("/in.pdf", input);
  let code;
  try {
    code = q.callMain(args);
  } catch (e) {
    code = typeof e?.status === "number" ? e.status : 2;
  }
  let output = null;
  try {
    output = q.FS.readFile("/out.pdf");
  } catch {}
  // qpdf exits 0 on success and 3 when it succeeded with warnings.
  return { ok: (code === 0 || code === 3) && output !== null, output };
}

function looksLikePdf(bytes) {
  const head = new TextDecoder("latin1").decode(bytes.subarray(0, 1024));
  return head.includes("%PDF-");
}

function hasEncryptDict(bytes) {
  // The /Encrypt entry lives in the (never compressed) trailer or xref stream dictionary.
  return new TextDecoder("latin1").decode(bytes).includes("/Encrypt");
}

async function inspect(bytes) {
  if (!looksLikePdf(bytes)) return "invalid";
  if (!hasEncryptDict(bytes)) return "none";
  // If qpdf can decrypt it with no password, it only has an owner (permissions) password.
  const { ok } = await qpdf(["--decrypt", "/in.pdf", "/out.pdf"], bytes);
  return ok ? "restricted" : "password";
}

async function lock(bytes, { userPassword, ownerPassword, allowPrint, allowCopy, allowEdit }) {
  const args = ["--encrypt", userPassword, ownerPassword || userPassword, "256"];
  if (!allowPrint) args.push("--print=none");
  if (!allowCopy) args.push("--extract=n");
  if (!allowEdit) args.push("--modify=none", "--annotate=n", "--assemble=n", "--form=n");
  args.push("--", "/in.pdf", "/out.pdf");
  const { ok, output } = await qpdf(args, bytes);
  if (!ok) throw new Error("This PDF could not be locked. It may be damaged.");
  return output;
}

async function unlock(bytes, password) {
  const { ok, output } = await qpdf([`--password=${password}`, "--decrypt", "/in.pdf", "/out.pdf"], bytes);
  if (!ok) throw new Error(password ? "The password is incorrect." : "This PDF needs a password.");
  return output;
}

self.onmessage = async ({ data }) => {
  const { id, action, bytes, options } = data;
  try {
    let result;
    if (action === "inspect") result = await inspect(bytes);
    else if (action === "lock") result = await lock(bytes, options);
    else if (action === "unlock") result = await unlock(bytes, options.password);
    const transfer = result instanceof Uint8Array ? [result.buffer] : [];
    self.postMessage({ id, result }, transfer);
  } catch (e) {
    self.postMessage({ id, error: e.message || String(e) });
  }
};
