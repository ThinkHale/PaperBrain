/**
 * app.js — PaperBrain main application
 *
 * Coordinates: Auth → DB → API → UI
 */

import * as Auth from "./auth.js";
import * as DB   from "./db.js";
import * as API  from "./api.js";
import { AnnotationEngine } from "./annotate.js";
import { MindMap }          from "./mindmap.js";

// ── PDF.js worker ─────────────────────────────────────────────
if (window.pdfjsLib) {
  pdfjsLib.GlobalWorkerOptions.workerSrc =
    "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";
}

// ── State ─────────────────────────────────────────────────────
const state = {
  notes:            [],
  currentNote:      null,
  currentImageUrls: [],
  editMode:         false,
  editOriginals:    {},
  annotateEngine:   null,
  currentAnnotateIdx: 0,
  mindmap:          null,
  authMode:         "signin",
};

// ── DOM helpers ───────────────────────────────────────────────
const $ = (id) => document.getElementById(id);

const authScreen      = $("auth-screen");
const app             = $("app");
const authForm        = $("auth-form");
const authEmail       = $("auth-email");
const authPassword    = $("auth-password");
const authSubmit      = $("auth-submit");
const authError       = $("auth-error");
const authSwitchLink  = $("auth-switch-link");

const sidebar         = $("sidebar");
const sidebarOverlay  = $("sidebar-overlay");
const sidebarToggle   = $("sidebar-toggle");
const sidebarClose    = $("sidebar-close");
const searchInput     = $("search-input");
const searchToggleBtn = $("search-toggle-btn");

const notesList       = $("notes-list");
const notesListMobile = $("notes-list-mobile");

const viewNotes       = $("view-notes");
const viewMap         = $("view-map");

const fileInput       = $("file-input");
const cameraInput     = $("camera-input");
const uploadZone      = $("upload-zone");
const queue           = $("queue");
const cameraNavBtn    = $("camera-nav-btn");

const noteModal       = $("note-modal");
const noteTitle       = $("note-title");
const editTitleBtn    = $("edit-title-btn");
const editModeBtn     = $("edit-mode-btn");
const reprocessBtn    = $("reprocess-btn");
const deleteNoteBtn   = $("delete-note-btn");
const noteModalClose  = $("note-modal-close");
const noteImagesWrap  = $("note-images-wrap");
const noteTagsEl      = $("note-tags");
const tagInput        = $("tag-input");
const tagAddBtn       = $("tag-add-btn");
const organizedView   = $("organized-view");
const organizedEdit   = $("organized-edit");
const transcriptionView = $("transcription-view");
const transcriptionEdit = $("transcription-edit");
const summaryView     = $("summary-view");
const keyPointsView   = $("key-points-view");
const editActions     = $("edit-actions");
const saveEditBtn     = $("save-edit-btn");
const cancelEditBtn   = $("cancel-edit-btn");
const relationsListEl = $("relations-list");
const exportMdBtn     = $("export-md-btn");
const noteMetaEl      = $("note-meta");

const annotateToggleBtn    = $("annotate-toggle-btn");
const annotateToolbar      = $("annotate-toolbar");
const annotateTagSelect    = $("annotate-tag-select");
const annotateTagNew       = $("annotate-tag-new");
const annotateDeleteBtn    = $("annotate-delete-btn");
const annotateReprocessBtn = $("annotate-reprocess-btn");
const annotateDoneBtn      = $("annotate-done-btn");

const profileModal      = $("profile-modal");
const profileModalClose = $("profile-modal-close");
const profileBtn        = $("profile-btn");
const profileNavBtn     = $("profile-nav-btn");
const profileEmail      = $("profile-email");
const profileNameInput  = $("profile-name");
const modelSelect       = $("model-select");
const themeToggle       = $("theme-toggle");
const signoutBtn        = $("signout-btn");
const saveProfileBtn    = $("save-profile-btn");
const exportAllBtn      = $("export-all-btn");

const clarifyModal  = $("clarify-modal");
const clarifyClose  = $("clarify-close");
const clarifyItems  = $("clarify-items");
const clarifySubmit = $("clarify-submit");
const clarifySkip   = $("clarify-skip");

const lightbox      = $("lightbox");
const lightboxImg   = $("lightbox-img");
const lightboxClose = $("lightbox-close");

const confirmDialog = $("confirm-dialog");
const confirmMsg    = $("confirm-msg");
const confirmOk     = $("confirm-ok");
const confirmCancel = $("confirm-cancel");
const toastContainer = $("toast-container");

const mapResetBtn   = $("map-reset");
const mapTagLinksBtn = $("map-tag-links");
const mapFilter     = $("map-filter");

// ── Utilities ─────────────────────────────────────────────────

function uuid() { return crypto.randomUUID(); }

function escHtml(str) {
  return String(str ?? "")
    .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
}

function fmtDate(iso) {
  return new Date(iso).toLocaleDateString(undefined, { year:"numeric", month:"short", day:"numeric" });
}

function toast(msg, type = "info", duration = 3500) {
  const el = document.createElement("div");
  el.className = `toast toast-${type}`;
  el.textContent = msg;
  toastContainer.appendChild(el);
  setTimeout(() => el.remove(), duration);
}

function confirm(msg) {
  return new Promise((resolve) => {
    confirmMsg.textContent = msg;
    confirmDialog.classList.remove("hidden");
    function ok()  { cleanup(); resolve(true);  }
    function no()  { cleanup(); resolve(false); }
    function cleanup() {
      confirmDialog.classList.add("hidden");
      confirmOk.removeEventListener("click", ok);
      confirmCancel.removeEventListener("click", no);
    }
    confirmOk.addEventListener("click", ok);
    confirmCancel.addEventListener("click", no);
  });
}

function renderMarkdown(text) {
  if (typeof marked === "undefined") return `<pre>${escHtml(text)}</pre>`;
  const html = marked.parse(text ?? "");
  return typeof DOMPurify !== "undefined" ? DOMPurify.sanitize(html) : `<pre>${escHtml(text)}</pre>`;
}

// ── Auth ──────────────────────────────────────────────────────

function showAuth() {
  authScreen.classList.remove("hidden");
  app.classList.add("hidden");
}

function showConfigError() {
  authScreen.classList.remove("hidden");
  app.classList.add("hidden");
  authForm?.classList.add("hidden");
  document.querySelector(".auth-tabs")?.classList.add("hidden");
  document.querySelector(".auth-hint")?.classList.add("hidden");
  if (authError) {
    authError.style.color = "var(--danger)";
    authError.textContent = Auth.configError;
    authError.classList.remove("hidden");
  }
}

function showApp() {
  authScreen.classList.add("hidden");
  app.classList.remove("hidden");
  loadNotes();
}

document.querySelectorAll(".auth-tab").forEach((tab) => {
  tab.addEventListener("click", () => {
    state.authMode = tab.dataset.tab;
    document.querySelectorAll(".auth-tab").forEach((t) => t.classList.toggle("active", t === tab));
    authSubmit.textContent = state.authMode === "signin" ? "Sign In" : "Sign Up";
    authError.classList.add("hidden");
  });
});

authSwitchLink?.addEventListener("click", (e) => {
  e.preventDefault();
  const other = state.authMode === "signin" ? "signup" : "signin";
  document.querySelector(`.auth-tab[data-tab="${other}"]`)?.click();
});

authForm?.addEventListener("submit", async (e) => {
  e.preventDefault();
  authError.classList.add("hidden");
  const email    = authEmail.value.trim();
  const password = authPassword.value;
  if (!email || !password) return;

  authSubmit.disabled = true;
  authSubmit.textContent = state.authMode === "signin" ? "Signing in…" : "Creating account…";

  const fn = state.authMode === "signin" ? Auth.signIn : Auth.signUp;
  const { user, error } = await fn(email, password);

  authSubmit.disabled = false;
  authSubmit.textContent = state.authMode === "signin" ? "Sign In" : "Sign Up";

  if (error) {
    authError.textContent = error;
    authError.classList.remove("hidden");
    return;
  }
  if (state.authMode === "signup") {
    authError.style.color = "var(--success)";
    authError.textContent = "Account created! Check your email to confirm, then sign in.";
    authError.classList.remove("hidden");
    return;
  }
  if (user) showApp();
});

// ── Sidebar ───────────────────────────────────────────────────

function openSidebar()  { sidebar.classList.add("open"); sidebarOverlay.classList.add("open"); }
function closeSidebar() { sidebar.classList.remove("open"); sidebarOverlay.classList.remove("open"); }

sidebarToggle?.addEventListener("click", openSidebar);
sidebarClose?.addEventListener("click", closeSidebar);
sidebarOverlay?.addEventListener("click", closeSidebar);
searchToggleBtn?.addEventListener("click", () => { openSidebar(); setTimeout(() => searchInput?.focus(), 200); });
cameraNavBtn?.addEventListener("click", () => cameraInput?.click());

// ── Navigation ────────────────────────────────────────────────

function switchView(view) {
  viewNotes.style.display = view === "notes" ? "flex" : "none";
  viewMap.style.display   = view === "map"   ? "flex" : "none";
  document.querySelectorAll("[data-view]").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.view === view);
  });
  if (view === "map") loadMindMap();
  closeSidebar();
}

document.querySelectorAll("[data-view]").forEach((btn) => {
  btn.addEventListener("click", () => switchView(btn.dataset.view));
});

// ── Profile modal ─────────────────────────────────────────────

async function openProfileModal() {
  profileEmail.textContent = Auth.getUser()?.email ?? "";
  profileModal.classList.remove("hidden");
  try {
    const profile = await DB.getProfile();
    profileNameInput.value = profile.display_name ?? "";
    modelSelect.value = profile.model ?? "gpt-5.4-mini";
  } catch (_) {}
}

profileBtn?.addEventListener("click", openProfileModal);
profileNavBtn?.addEventListener("click", openProfileModal);
profileModalClose?.addEventListener("click", () => profileModal.classList.add("hidden"));
profileModal?.querySelector(".modal-backdrop")?.addEventListener("click", () => profileModal.classList.add("hidden"));

themeToggle?.addEventListener("change", () => {
  const dark = themeToggle.checked;
  document.body.className = dark ? "theme-dark" : "theme-light";
  localStorage.setItem("pb_theme", dark ? "dark" : "light");
});

signoutBtn?.addEventListener("click", async () => {
  await Auth.signOut();
  profileModal.classList.add("hidden");
  showAuth();
});

saveProfileBtn?.addEventListener("click", async () => {
  try {
    await DB.updateProfile({ display_name: profileNameInput.value.trim() || null, model: modelSelect.value });
    toast("Settings saved", "success");
    profileModal.classList.add("hidden");
  } catch (err) {
    toast("Save failed: " + err.message, "error");
  }
});

exportAllBtn?.addEventListener("click", async () => {
  const data = await DB.exportAll();
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
  const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: `paperbrain-${Date.now()}.json` });
  a.click();
});

// ── Notes list ────────────────────────────────────────────────

async function loadNotes(query) {
  try {
    state.notes = query ? await DB.searchNotes(query) : await DB.getAllNotes();
    renderNotesList();
  } catch (err) {
    console.error(err);
    toast("Failed to load notes", "error");
  }
}

function renderNotesList() {
  const html = state.notes.length
    ? state.notes.map(noteCardHTML).join("")
    : `<p style="padding:16px;color:var(--text-muted);font-size:14px;">No notes yet. Upload your first handwritten page!</p>`;
  notesList.innerHTML = html;
  notesListMobile.innerHTML = html;
  document.querySelectorAll(".note-card").forEach((el) => {
    el.addEventListener("click", () => openNote(el.dataset.id));
  });
}

function noteCardHTML(note) {
  const tags = (note.tags ?? []).map((t) => `<span class="tag-chip">${escHtml(t)}</span>`).join("");
  return `<div class="note-card" data-id="${note.id}">
    <div class="note-card-title">${escHtml(note.title ?? "Untitled")}</div>
    <div class="note-card-meta">${fmtDate(note.created_at)}</div>
    <div class="note-card-summary">${escHtml(note.summary ?? "")}</div>
    ${tags ? `<div class="note-card-tags">${tags}</div>` : ""}
  </div>`;
}

let _searchTimer;
searchInput?.addEventListener("input", () => {
  clearTimeout(_searchTimer);
  _searchTimer = setTimeout(() => loadNotes(searchInput.value), 300);
});

// ── Open note modal ───────────────────────────────────────────

async function openNote(id) {
  try {
    const note = await DB.getNote(id);
    state.currentNote = note;
    state.currentImageUrls = await DB.getNoteImageUrls(id);
    state.editMode = false;
    renderNoteModal(note);
    noteModal.classList.remove("hidden");
    loadRelations(id);
  } catch (err) {
    toast("Failed to load note: " + err.message, "error");
  }
}

function renderNoteModal(note) {
  noteTitle.textContent = note.title ?? "Untitled";
  noteTitle.contentEditable = "false";
  noteMetaEl.textContent = fmtDate(note.created_at);

  organizedView.innerHTML     = renderMarkdown(note.organized);
  transcriptionView.innerHTML = `<pre>${escHtml(note.transcription)}</pre>`;
  summaryView.innerHTML       = renderMarkdown(note.summary);
  keyPointsView.innerHTML     = (note.key_points ?? [])
    .map((p) => `<div class="key-point-item">${escHtml(p)}</div>`).join("");

  renderTags(note.tags ?? []);
  renderImages();
  setEditMode(false);
  switchTab("organized");

  // Reset annotate
  destroyAnnotateEngine();
  annotateToggleBtn.classList.remove("hidden");
}

function renderImages() {
  noteImagesWrap.innerHTML = "";
  state.currentImageUrls.forEach((url, i) => {
    const container = document.createElement("div");
    container.className = "note-image-container";
    container.dataset.idx = i;

    const img = document.createElement("img");
    img.src = url;
    img.alt = `Page ${i + 1}`;
    img.loading = "lazy";
    img.addEventListener("click", () => {
      if (!state.annotateEngine) {
        lightboxImg.src = url;
        lightbox.classList.remove("hidden");
      }
    });

    container.appendChild(img);
    noteImagesWrap.appendChild(container);
  });
}

// ── Tabs ──────────────────────────────────────────────────────

function switchTab(name) {
  document.querySelectorAll(".tab-btn").forEach((btn) => btn.classList.toggle("active", btn.dataset.tab === name));
  document.querySelectorAll(".tab-panel").forEach((panel) => {
    panel.classList.toggle("active", panel.id === `tab-${name}`);
    panel.classList.toggle("hidden", panel.id !== `tab-${name}`);
  });
}

document.querySelectorAll(".tab-btn").forEach((btn) => btn.addEventListener("click", () => switchTab(btn.dataset.tab)));
noteModalClose?.addEventListener("click", () => noteModal.classList.add("hidden"));
noteModal?.querySelector(".modal-backdrop")?.addEventListener("click", () => noteModal.classList.add("hidden"));

// ── Edit mode ─────────────────────────────────────────────────

function setEditMode(on) {
  state.editMode = on;
  editModeBtn.textContent = on ? "Viewing" : "Edit";
  editActions.classList.toggle("hidden", !on);
  organizedView.classList.toggle("hidden", on);
  organizedEdit.classList.toggle("hidden", !on);
  transcriptionView.classList.toggle("hidden", on);
  transcriptionEdit.classList.toggle("hidden", !on);

  if (on) {
    state.editOriginals = {
      organized:     state.currentNote.organized ?? "",
      transcription: state.currentNote.transcription ?? "",
    };
    organizedEdit.value     = state.currentNote.organized ?? "";
    transcriptionEdit.value = state.currentNote.transcription ?? "";
  }
}

editModeBtn?.addEventListener("click", () => setEditMode(!state.editMode));
cancelEditBtn?.addEventListener("click", () => setEditMode(false));

saveEditBtn?.addEventListener("click", async () => {
  const note = state.currentNote;
  const newOrg    = organizedEdit.value;
  const newTrans  = transcriptionEdit.value;
  const corrections = diffText(state.editOriginals.transcription, newTrans);

  try {
    const updated = await DB.saveNote(note.id, { organized: newOrg, transcription: newTrans });
    state.currentNote = updated;
    organizedView.innerHTML = renderMarkdown(newOrg);
    transcriptionView.innerHTML = `<pre>${escHtml(newTrans)}</pre>`;
    setEditMode(false);
    toast("Saved", "success");
    loadNotes();

    if (corrections.length) {
      API.learnHandwriting({ noteId: note.id, corrections })
        .then((res) => { if (res.synthesized) toast("AI updated your handwriting profile", "success"); })
        .catch(() => {});
    }
  } catch (err) {
    toast("Save failed: " + err.message, "error");
  }
});

function diffText(original, edited) {
  if (original === edited) return [];
  const orig = original.split(/\s+/);
  const edit = edited.split(/\s+/);
  const corrections = [];
  const len = Math.min(orig.length, edit.length);
  for (let i = 0; i < len; i++) {
    if (orig[i] !== edit[i] && orig[i] && edit[i]) {
      corrections.push({
        original:   orig[i].replace(/[^\w'-]/g, ""),
        correction: edit[i].replace(/[^\w'-]/g, ""),
      });
    }
  }
  return corrections.slice(0, 20);
}

// ── Title editing ─────────────────────────────────────────────

editTitleBtn?.addEventListener("click", () => {
  const editing = noteTitle.contentEditable === "true";
  if (editing) {
    const newTitle = noteTitle.textContent.trim() || "Untitled";
    DB.saveNote(state.currentNote.id, { title: newTitle })
      .then(() => { state.currentNote.title = newTitle; loadNotes(); toast("Title updated", "success"); })
      .catch((err) => toast(err.message, "error"));
    noteTitle.contentEditable = "false";
    editTitleBtn.innerHTML = `<svg width="14" height="14" viewBox="0 0 20 20" fill="currentColor"><path d="M13.586 3.586a2 2 0 112.828 2.828L7.07 15.757l-3.535.707.707-3.535L13.586 3.586z"/></svg>`;
  } else {
    noteTitle.contentEditable = "true";
    noteTitle.focus();
    editTitleBtn.textContent = "✓";
  }
});

// ── Tags ──────────────────────────────────────────────────────

function renderTags(tags) {
  noteTagsEl.innerHTML = tags.map((t) =>
    `<span class="tag-chip">${escHtml(t)}<span class="tag-remove" data-tag="${escHtml(t)}">×</span></span>`
  ).join("");
  noteTagsEl.querySelectorAll(".tag-remove").forEach((btn) =>
    btn.addEventListener("click", () => removeTag(btn.dataset.tag))
  );
}

async function addTag(tag) {
  tag = tag.trim().toLowerCase().replace(/\s+/g, "-");
  if (!tag || !state.currentNote) return;
  const tags = [...new Set([...(state.currentNote.tags ?? []), tag])];
  const updated = await DB.saveNote(state.currentNote.id, { tags });
  state.currentNote = updated;
  renderTags(updated.tags);
  loadNotes();
}

async function removeTag(tag) {
  if (!state.currentNote) return;
  const tags = (state.currentNote.tags ?? []).filter((t) => t !== tag);
  const updated = await DB.saveNote(state.currentNote.id, { tags });
  state.currentNote = updated;
  renderTags(updated.tags);
  loadNotes();
}

tagAddBtn?.addEventListener("click", () => { addTag(tagInput.value); tagInput.value = ""; });
tagInput?.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); addTag(tagInput.value); tagInput.value = ""; } });

// ── Relations ─────────────────────────────────────────────────

async function loadRelations(noteId) {
  try {
    const rels = await DB.getRelations(noteId);
    relationsListEl.innerHTML = rels.length
      ? rels.map((r) => {
          const otherId = r.from_id === noteId ? r.to_id : r.from_id;
          const other   = state.notes.find((n) => n.id === otherId);
          return `<div class="relation-chip" data-id="${otherId}">
            <span class="relation-score">${Math.round((r.score ?? 0) * 100)}%</span>
            <span class="relation-title">${escHtml(other?.title ?? "Related note")}</span>
            <span class="relation-reason">${escHtml(r.reason ?? "")}</span>
          </div>`;
        }).join("")
      : `<p style="font-size:13px;color:var(--text-muted)">No related notes yet.</p>`;

    relationsListEl.querySelectorAll(".relation-chip[data-id]").forEach((el) => {
      el.addEventListener("click", () => { noteModal.classList.add("hidden"); openNote(el.dataset.id); });
    });
  } catch (_) {}
}

// ── Delete ────────────────────────────────────────────────────

deleteNoteBtn?.addEventListener("click", async () => {
  const ok = await confirm(`Delete "${state.currentNote?.title ?? "this note"}"? This cannot be undone.`);
  if (!ok) return;
  try {
    await DB.deleteNote(state.currentNote.id);
    noteModal.classList.add("hidden");
    toast("Note deleted", "success");
    loadNotes();
  } catch (err) { toast("Delete failed: " + err.message, "error"); }
});

// ── Re-process ────────────────────────────────────────────────

reprocessBtn?.addEventListener("click", async () => {
  if (!state.currentNote || !state.currentImageUrls.length) return;
  reprocessBtn.disabled = true; reprocessBtn.textContent = "Processing…";
  try {
    const dataUrls = await Promise.all(state.currentImageUrls.map(fetchAsDataUrl));
    const result = await API.processNote(dataUrls, { noteId: state.currentNote.id });
    if (result?.ok && result.note) {
      state.currentNote = result.note;
      renderNoteModal(result.note);
      loadNotes();
      toast("Re-processed", "success");
      triggerClarificationPopup(result.note);
    }
  } catch (err) { toast("Re-process failed: " + err.message, "error"); }
  finally { reprocessBtn.disabled = false; reprocessBtn.textContent = "Re-process"; }
});

async function fetchAsDataUrl(url) {
  const res = await fetch(url);
  const blob = await res.blob();
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = (e) => resolve(e.target.result);
    reader.readAsDataURL(blob);
  });
}

// ── Export markdown ───────────────────────────────────────────

exportMdBtn?.addEventListener("click", () => {
  const n = state.currentNote; if (!n) return;
  const md = `# ${n.title}\n\n## Summary\n${n.summary}\n\n## Organized\n${n.organized}\n\n## Transcription\n${n.transcription}\n`;
  const a = Object.assign(document.createElement("a"), {
    href: URL.createObjectURL(new Blob([md], { type: "text/markdown" })),
    download: `${(n.title ?? "note").replace(/[^a-z0-9]/gi, "_")}.md`,
  });
  a.click();
});

// ── ANNOTATION ────────────────────────────────────────────────

function destroyAnnotateEngine() {
  state.annotateEngine?.destroy();
  state.annotateEngine = null;
  $("annotate-fullscreen")?.classList.add("hidden");
}

annotateToggleBtn?.addEventListener("click", () => {
  startAnnotateMode(0);
});

annotateDoneBtn?.addEventListener("click", () => {
  destroyAnnotateEngine();
});

async function startAnnotateMode(idx) {
  destroyAnnotateEngine();
  state.currentAnnotateIdx = idx;

  const url = state.currentImageUrls[idx];
  if (!url) return;

  // Populate fullscreen image
  const fsImg  = $("annotate-fs-img");
  const fsWrap = $("annotate-img-wrap");
  fsImg.src = url;

  // Reuse or create canvas inside the image wrapper
  let canvas = fsWrap.querySelector("canvas");
  if (!canvas) {
    canvas = document.createElement("canvas");
    fsWrap.appendChild(canvas);
  }

  // Show fullscreen overlay
  $("annotate-fullscreen").classList.remove("hidden");

  const rows = await DB.getAnnotations(state.currentNote.id);
  const tags  = state.currentNote.tags ?? [];
  annotateTagSelect.innerHTML = `<option value="">— pick tag —</option>` +
    tags.map((t) => `<option value="${escHtml(t)}">${escHtml(t)}</option>`).join("");

  state.annotateEngine = new AnnotationEngine(canvas, fsImg, {
    onSave: (ann) => DB.saveAnnotation({ ...ann, note_id: state.currentNote.id, image_index: idx }),
    onDelete: (id) => DB.deleteAnnotation(id),
    onSelect: (ann) => {
      const sel = ann !== null;
      annotateDeleteBtn.disabled = !sel;
      annotateReprocessBtn.disabled = !sel;
    },
  });
  state.annotateEngine.loadAnnotations(rows.filter((r) => r.image_index === idx));
}

document.querySelectorAll(".tool-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tool-btn").forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
    state.annotateEngine?.setTool(btn.dataset.tool);
  });
});

annotateTagSelect?.addEventListener("change", () => { state.annotateEngine?.setTag(annotateTagSelect.value); });
annotateTagNew?.addEventListener("input", () => { if (annotateTagNew.value.trim()) state.annotateEngine?.setTag(annotateTagNew.value.trim()); });
annotateDeleteBtn?.addEventListener("click", () => { state.annotateEngine?.deleteSelected(); annotateDeleteBtn.disabled = true; annotateReprocessBtn.disabled = true; });

annotateReprocessBtn?.addEventListener("click", async () => {
  if (!state.annotateEngine) return;
  const url = state.currentImageUrls[state.currentAnnotateIdx];
  const cropped = await state.annotateEngine.cropSelected(url);
  if (!cropped) return;
  const tag = annotateTagSelect.value || annotateTagNew.value.trim() || "region";
  annotateReprocessBtn.disabled = true;
  annotateReprocessBtn.textContent = "Processing…";
  try {
    const result = await API.processRegion({ imageDataUrl: cropped, tag, noteId: state.currentNote.id });
    if (result?.ok && result.region) {
      const existing = state.currentNote.organized ?? "";
      const newContent = `${existing}\n\n## Region: ${tag}\n${result.region.content}`;
      const updated = await DB.saveNote(state.currentNote.id, { organized: newContent });
      state.currentNote = updated;
      organizedView.innerHTML = renderMarkdown(newContent);
      toast(`Region "${tag}" processed`, "success");
    }
  } catch (err) { toast("Region failed: " + err.message, "error"); }
  finally { annotateReprocessBtn.disabled = false; annotateReprocessBtn.textContent = "Re-process region"; }
});

// ── FILE UPLOAD ───────────────────────────────────────────────

uploadZone?.addEventListener("click", (e) => { if (!e.target.closest("label")) fileInput?.click(); });
uploadZone?.addEventListener("dragover",  (e) => { e.preventDefault(); uploadZone.classList.add("drag-over"); });
uploadZone?.addEventListener("dragleave", ()  => uploadZone.classList.remove("drag-over"));
uploadZone?.addEventListener("drop",      (e) => { e.preventDefault(); uploadZone.classList.remove("drag-over"); handleFiles([...e.dataTransfer.files]); });
fileInput?.addEventListener("change",   () => { handleFiles([...fileInput.files]); fileInput.value = ""; });
cameraInput?.addEventListener("change", () => { handleFiles([...cameraInput.files]); cameraInput.value = ""; });

async function handleFiles(files) {
  if (!files.length) return;
  queue.classList.remove("hidden");
  for (const file of files) {
    if (file.type === "application/pdf" || file.name.endsWith(".pdf")) {
      await processJob(uuid(), file, "pdf");
    } else if (file.type.startsWith("image/")) {
      await processJob(uuid(), file, "image");
    }
  }
}

async function processJob(jobId, file, type) {
  const item = document.createElement("div");
  item.className = "queue-item"; item.id = `job-${jobId}`;
  item.innerHTML = `
    <div class="queue-item-header">
      <span class="queue-filename">${escHtml(file.name)}</span>
      <span class="queue-status">Preparing…</span>
    </div>
    <div class="queue-bar-track"><div class="queue-bar-fill" style="width:5%"></div></div>`;
  queue.appendChild(item);

  const setStatus = (msg, pct) => {
    item.querySelector(".queue-status").textContent = msg;
    item.querySelector(".queue-bar-fill").style.width = pct + "%";
  };

  try {
    let images;
    if (type === "pdf") {
      setStatus("Rendering PDF pages…", 15);
      images = await renderPDF(file);
    } else {
      const dataUrl = await API.fileToDataUrl(file);
      images = [dataUrl];
    }

    setStatus("Transcribing with AI…", 40);
    const result = await API.processNote(images);
    setStatus("Saving…", 80);
    if (!result?.ok) throw new Error(result?.error ?? "Processing failed");

    setStatus("Done!", 100);
    item.style.opacity = "0.5";
    setTimeout(() => item.remove(), 2500);

    await loadNotes();

    if (result.note?.id) {
      await openNote(result.note.id);
      API.findRelations(result.note.id).catch(() => {});
      triggerClarificationPopup(result.note);
    }
  } catch (err) {
    item.classList.add("error");
    item.querySelector(".queue-status").textContent = "Error: " + err.message;
    setTimeout(() => item.remove(), 6000);
  }
}

async function renderPDF(file) {
  const buffer = await file.arrayBuffer();
  const pdf    = await pdfjsLib.getDocument({ data: buffer }).promise;
  const images = [];
  for (let i = 1; i <= pdf.numPages; i++) {
    const page = await pdf.getPage(i);
    const vp   = page.getViewport({ scale: 2 });
    const canvas = document.createElement("canvas");
    canvas.width = vp.width; canvas.height = vp.height;
    await page.render({ canvasContext: canvas.getContext("2d"), viewport: vp }).promise;
    images.push(canvas.toDataURL("image/jpeg", 0.88));
  }
  return images;
}

// ── CLARIFICATION POPUP ───────────────────────────────────────

async function triggerClarificationPopup(note) {
  if (!note?.transcription) return;
  const regex   = /(.{0,40})\[unclear\](.{0,40})/g;
  const matches = [];
  let m;
  while ((m = regex.exec(note.transcription)) !== null) {
    matches.push({ before: m[1], after: m[2] });
  }
  if (!matches.length) return;

  // Show note image as context if available
  const clarifyImageContext = $("clarify-image-context");
  const clarifyNoteImg      = $("clarify-note-img");
  if (clarifyImageContext && clarifyNoteImg && state.currentImageUrls?.[0]) {
    clarifyNoteImg.src = state.currentImageUrls[0];
    clarifyImageContext.classList.remove("hidden");
  } else if (clarifyImageContext) {
    clarifyImageContext.classList.add("hidden");
  }

  clarifyItems.innerHTML = "";
  clarifyModal._noteId = note.id;
  clarifyModal._inputs = [];

  matches.slice(0, 5).forEach((match) => {
    const ctx = `${match.before}[unclear]${match.after}`.trim();
    const div = document.createElement("div");
    div.className = "clarify-item";
    div.innerHTML = `
      <div class="clarify-field">
        <div class="clarify-label">Context: "…${escHtml(ctx)}…"</div>
        <input class="clarify-input" type="text" placeholder="What does the unclear word say?" />
      </div>`;
    clarifyItems.appendChild(div);
    clarifyModal._inputs.push({ input: div.querySelector(".clarify-input"), context: ctx });
  });

  clarifyModal.classList.remove("hidden");
}

clarifyClose?.addEventListener("click", () => clarifyModal.classList.add("hidden"));
clarifySkip?.addEventListener("click",  () => clarifyModal.classList.add("hidden"));
clarifyModal?.querySelector(".modal-backdrop")?.addEventListener("click", () => clarifyModal.classList.add("hidden"));

clarifySubmit?.addEventListener("click", async () => {
  const noteId = clarifyModal._noteId;
  const inputs = clarifyModal._inputs ?? [];
  const corrections = inputs
    .map((item) => ({ original: "[unclear]", correction: item.input.value.trim(), context: item.context }))
    .filter((c) => c.correction);

  if (!corrections.length) { clarifyModal.classList.add("hidden"); return; }

  clarifySubmit.disabled = true; clarifySubmit.textContent = "Learning…";
  try {
    const res = await API.learnHandwriting({ noteId, corrections });
    clarifyModal.classList.add("hidden");
    toast(res.synthesized ? "AI updated your handwriting profile!" : "Corrections saved. Thanks!", "success");
  } catch (err) {
    toast("Failed: " + err.message, "error");
  } finally {
    clarifySubmit.disabled = false; clarifySubmit.textContent = "Submit & Learn";
  }
});

// ── MIND MAP ──────────────────────────────────────────────────

async function loadMindMap() {
  try {
    const [notes, relations, positions] = await Promise.all([
      DB.getAllNotes(), DB.getAllRelations(), DB.getMindmapPositions(),
    ]);
    if (!state.mindmap) {
      state.mindmap = new MindMap("#mindmap-svg", {
        onOpenNote: (id) => { switchView("notes"); openNote(id); },
        onSavePosition: (pos) => DB.saveMindmapPosition(pos).catch(() => {}),
      });
    }
    state.mindmap.load(notes, relations, positions);
  } catch (err) { toast("Mind map error: " + err.message, "error"); }
}

mapResetBtn?.addEventListener("click", () => state.mindmap?.resetLayout());
mapTagLinksBtn?.addEventListener("click", () => state.mindmap?.toggleTagLinks());

let _mapFilter;
mapFilter?.addEventListener("input", () => {
  clearTimeout(_mapFilter);
  _mapFilter = setTimeout(() => state.mindmap?.filterByTag(mapFilter.value.trim() || null), 300);
});

// ── LIGHTBOX ──────────────────────────────────────────────────

lightboxClose?.addEventListener("click", () => lightbox.classList.add("hidden"));
lightbox?.addEventListener("click", (e) => { if (e.target === lightbox) lightbox.classList.add("hidden"); });

// ── INIT ──────────────────────────────────────────────────────

async function init() {
  // Theme
  const dark = (localStorage.getItem("pb_theme") ?? "dark") === "dark";
  document.body.className = dark ? "theme-dark" : "theme-light";
  if (themeToggle) themeToggle.checked = dark;

  if (!Auth.isConfigured) {
    showConfigError();
    return;
  }

  // Initial view state
  viewNotes.style.display = "flex";
  viewMap.style.display   = "none";

  // Auth
  const user = await Auth.init();
  Auth.onAuthChange((u) => { if (u) showApp(); else showAuth(); });
  if (user) showApp(); else showAuth();
}

init();
