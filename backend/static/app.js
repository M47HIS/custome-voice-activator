/**
 * Voice Module — Web Dashboard
 *
 * WebSocket client for real-time status + transcription updates.
 * Canvas waveform visualization, action CRUD, transcription history.
 */

// ── State ────────────────────────────────────────────────────────────────
const STATE = {
    serverState: "idle",
    ws: null,
    reconnectTimer: null,
    actions: [],
    history: [],
    settings: { hotkey: "cmd+shift+space", mode: "hold", action: "opencode" },
    settingsModalVisible: false,
    recordingShortcut: false,
    capturedHotkey: null,
    authToken: "",
    editingAction: null,
    waveformAnimId: null,
    waveformBars: [],
    numBars: 32,
    animationTime: 0,
};

// ── DOM refs ─────────────────────────────────────────────────────────────
const $ = (sel) => document.querySelector(sel);

function authHeaders(extra = {}) {
    if (!STATE.authToken) return extra;
    return {
        ...extra,
        Authorization: `Bearer ${STATE.authToken}`,
    };
}

// ── WebSocket ────────────────────────────────────────────────────────────
function connectWS() {
    const protocol = location.protocol === "https:" ? "wss" : "ws";
    const url = `${protocol}://${location.host}/ws`;

    STATE.ws = new WebSocket(url);

    STATE.ws.onopen = () => {
        STATE.ws.send(JSON.stringify({ type: "hello", role: "ui" }));
        if (STATE.reconnectTimer) {
            clearTimeout(STATE.reconnectTimer);
            STATE.reconnectTimer = null;
        }
    };

    STATE.ws.onmessage = (event) => {
        try {
            const data = JSON.parse(event.data);
            handleMessage(data);
        } catch (e) {
            console.warn("[ws] non-JSON message:", event.data);
        }
    };

    STATE.ws.onclose = () => {
        STATE.reconnectTimer = setTimeout(connectWS, 3000);
    };

    STATE.ws.onerror = (err) => {
        console.error("[ws] error:", err);
    };
}

function handleMessage(data) {
    switch (data.type) {
        case "welcome":
            updateEngine(data.engine);
            break;
        case "status":
            STATE.serverState = data.state;
            updateStatusBadge(data.state);
            updateWaveformLabel(data.state);
            break;
        case "transcription":
            if (data.is_final && data.text) {
                addHistoryItem(data.text);
            }
            break;
        default:
            break;
    }
}

// ── Status Badge ─────────────────────────────────────────────────────────
function updateStatusBadge(state) {
    const badge = $("#status-badge");
    badge.className = `status-badge ${state}`;
    const labels = { idle: "Idle", listening: "Recording", transcribing: "Transcribing" };
    badge.textContent = labels[state] || state;
}

function updateEngine(engine) {
    const el = $("#engine-info");
    if (el) {
        el.textContent = engine || "voxtral";
    }
}

// ── Waveform Canvas ──────────────────────────────────────────────────────
function initWaveform() {
    const canvas = $("#waveform");
    if (!canvas) return;
    const ctx = canvas.getContext("2d");

    // Preferences
    const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    // Initialize bars
    for (let i = 0; i < STATE.numBars; i++) {
        STATE.waveformBars.push({
            target: 2,
            current: 2,
            phaseOffset: (i / STATE.numBars) * Math.PI * 2,
        });
    }

    function resize() {
        const rect = canvas.parentElement.getBoundingClientRect();
        const dpr = window.devicePixelRatio || 1;
        canvas.width = rect.width * dpr;
        canvas.height = rect.height * dpr;
        canvas.style.width = rect.width + "px";
        canvas.style.height = rect.height + "px";
        ctx.scale(dpr, dpr);
    }

    function draw() {
        const dpr = window.devicePixelRatio || 1;
        const w = canvas.width / dpr;
        const h = canvas.height / dpr;

        ctx.clearRect(0, 0, w, h);

        const barWidth = (w - 4) / STATE.numBars;
        const centerY = h / 2;
        const maxHeight = h * 0.45;

        // Radial glow behind waveform when recording
        if (STATE.serverState === "listening") {
            const glow = ctx.createRadialGradient(w / 2, centerY, 0, w / 2, centerY, w * 0.5);
            glow.addColorStop(0, "rgba(230, 140, 50, 0.06)");
            glow.addColorStop(1, "rgba(0, 0, 0, 0)");
            ctx.fillStyle = glow;
            ctx.fillRect(0, 0, w, h);
        }

        // Pulse ring at center when recording
        if (STATE.serverState === "listening") {
            const pulsePhase = (STATE.animationTime * 0.001) % 2;
            const pulseRadius = 20 + Math.sin(pulsePhase * Math.PI) * 60;
            const pulseAlpha = Math.max(0, 1 - Math.abs(pulsePhase - 1)) * 0.12;

            ctx.beginPath();
            ctx.arc(w / 2, centerY, pulseRadius, 0, Math.PI * 2);
            ctx.strokeStyle = `rgba(230, 140, 50, ${pulseAlpha})`;
            ctx.lineWidth = 2;
            ctx.stroke();
        }

        // Draw bars
        for (let i = 0; i < STATE.numBars; i++) {
            const bar = STATE.waveformBars[i];
            bar.current += (bar.target - bar.current) * 0.12;

            const x = i * barWidth + 2;
            const barH = Math.max(1, bar.current * maxHeight);
            const y = centerY - barH / 2;
            const radius = barWidth * 0.4;

            let color;
            if (STATE.serverState === "listening") {
                // Warm accent gradient
                const gradient = ctx.createLinearGradient(x, y, x, y + barH);
                const t = i / STATE.numBars;
                // Vary hue slightly per bar for organic feel
                gradient.addColorStop(0, `oklch(${55 + t * 20}% 0.18 ${35 + t * 15})`);
                gradient.addColorStop(1, `oklch(${50 + t * 15}% 0.22 ${45 + t * 10})`);
                color = gradient;
            } else if (STATE.serverState === "transcribing") {
                // Amber tones
                const gradient = ctx.createLinearGradient(x, y, x, y + barH);
                gradient.addColorStop(0, "oklch(65% 0.16 65)");
                gradient.addColorStop(1, "oklch(60% 0.14 60)");
                color = gradient;
            } else {
                // Idle — surface-toned, barely visible
                const gradient = ctx.createLinearGradient(x, y, x, y + barH);
                gradient.addColorStop(0, "oklch(35% 0.01 260)");
                gradient.addColorStop(1, "oklch(28% 0.01 260)");
                color = gradient;
            }

            ctx.fillStyle = color;

            ctx.beginPath();
            ctx.moveTo(x + radius, y);
            ctx.lineTo(x + barWidth - radius, y);
            ctx.arcTo(x + barWidth, y, x + barWidth, y + radius, radius);
            ctx.lineTo(x + barWidth, y + barH - radius);
            ctx.arcTo(x + barWidth, y + barH, x + barWidth - radius, y + barH, radius);
            ctx.lineTo(x + radius, y + barH);
            ctx.arcTo(x, y + barH, x, y + barH - radius, radius);
            ctx.lineTo(x, y + radius);
            ctx.arcTo(x, y, x + radius, y, radius);
            ctx.closePath();
            ctx.fill();
        }
    }

    function animateBars(state) {
        if (prefersReducedMotion) {
            // Static flat bars
            for (let i = 0; i < STATE.numBars; i++) {
                STATE.waveformBars[i].target = 1;
            }
            return;
        }

        STATE.animationTime = performance.now();

        if (state === "listening") {
            // Alive bars with per-bar phase offsets
            for (let i = 0; i < STATE.numBars; i++) {
                const bar = STATE.waveformBars[i];
                const phase = bar.phaseOffset + STATE.animationTime * 0.004;
                const wave = Math.abs(Math.sin(phase)) * 0.55;
                const noise = Math.random() * 0.3;
                bar.target = 0.03 + wave + noise;
            }
        } else if (state === "transcribing") {
            // Breathing — slow oscillation
            for (let i = 0; i < STATE.numBars; i++) {
                const bar = STATE.waveformBars[i];
                const breathe = Math.sin(bar.phaseOffset + STATE.animationTime * 0.0015) * 0.04;
                bar.target = Math.max(0.02, bar.target * 0.95 + breathe);
            }
        } else {
            // Idle — subtle breathing, not static
            for (let i = 0; i < STATE.numBars; i++) {
                const bar = STATE.waveformBars[i];
                const breathe = Math.sin(bar.phaseOffset + STATE.animationTime * 0.0006) * 0.006;
                bar.target = 0.012 + breathe;
            }
        }
    }

    function loop() {
        animateBars(STATE.serverState);
        draw();
        STATE.waveformAnimId = requestAnimationFrame(loop);
    }

    resize();
    loop();
    window.addEventListener("resize", resize);
}

function updateWaveformLabel(state) {
    const el = $("#waveform-label");
    if (!el) return;
    const labels = {
        idle: "Waiting for client...",
        listening: "Recording in progress",
        transcribing: "Transcribing...",
    };
    el.textContent = labels[state] || "Waiting for client...";
}

// ── Status Grid ──────────────────────────────────────────────────────────
function formatTimeAgo(timestamp) {
    if (!timestamp) return "—";
    const diff = (Date.now() / 1000) - timestamp;
    if (diff < 5) return "just now";
    if (diff < 60) return `${Math.floor(diff)}s ago`;
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    return `${Math.floor(diff / 3600)}h ago`;
}

async function loadStatus() {
    try {
        const resp = await fetch("/api/status");
        const data = await resp.json();
        updateEngine(data.engine);
        $("#connected-count").textContent = data.connected_clients;
        $("#last-activity").textContent = formatTimeAgo(data.last_activity);
        $("#actions-loaded").textContent = data.actions_loaded;
        STATE.serverState = data.state;
        updateStatusBadge(data.state);
        updateWaveformLabel(data.state);
    } catch (e) {
        console.error("Failed to load status:", e);
    }
}

async function loadConfig() {
    try {
        const resp = await fetch("/api/config");
        const data = await resp.json();
        STATE.authToken = data.auth_token || "";
        STATE.settings = data.settings || { hotkey: "cmd+shift+space", mode: "hold", action: "opencode" };
        updateEngine(data.engine);
    } catch (e) {
        console.error("Failed to load config:", e);
    }
}

// ── Actions ──────────────────────────────────────────────────────────────
async function loadActions() {
    try {
        const resp = await fetch("/api/actions");
        STATE.actions = await resp.json();
        renderActions();
    } catch (e) {
        console.error("Failed to load actions:", e);
    }
}

function renderActions() {
    const list = $("#actions-list");
    if (STATE.actions.length === 0) {
        list.innerHTML = `
            <div class="actions-empty">
                Create your first action to decide what happens after transcription.
                <br>
                <span class="cta-link" onclick="openAddActionModal()">Create action</span>
            </div>`;
        return;
    }

    list.innerHTML = STATE.actions
        .map(
            (action, i) => `
        <div class="action-item">
            <div class="action-info">
                <span class="action-name">${escapeHtml(action.name)}</span>
                <span class="action-desc">${escapeHtml(action.description || "")}</span>
            </div>
            <span class="action-type-badge">${escapeHtml(action.type)}</span>
            <div class="action-controls">
                <button class="btn-icon" data-action="edit" data-index="${i}" title="Edit" aria-label="Edit">&#9998;</button>
                <button class="btn-icon danger" data-action="delete" data-name="${escapeHtml(action.name)}" title="Delete" aria-label="Delete">&#10005;</button>
            </div>
        </div>`
        )
        .join("");
}

function openAddActionModal() {
    STATE.editingAction = null;
    $("#modal-title").textContent = "Add action";
    $("#action-old-name").value = "";
    $("#action-name").value = "";
    $("#action-desc").value = "";
    $("#action-type").value = "terminal_command";
    updateConfigFields("terminal_command");
    showModal();
}

function editAction(index) {
    const action = STATE.actions[index];
    STATE.editingAction = index;
    $("#modal-title").textContent = "Edit action";
    $("#action-old-name").value = action.name;
    $("#action-name").value = action.name;
    $("#action-desc").value = action.description || "";
    $("#action-type").value = action.type;
    updateConfigFields(action.type, action.config);
    showModal();
}

async function deleteAction(name) {
    try {
        const resp = await fetch(`/api/actions/${encodeURIComponent(name)}`, {
            method: "DELETE",
            headers: authHeaders(),
        });
        if (!resp.ok) {
            const err = await resp.json();
            throw new Error(err.detail || "Failed to delete action");
        }
        await loadActions();
    } catch (e) {
        console.error("Failed to delete action:", e);
        alert("Failed to delete action: " + e.message);
    }
}

function updateConfigFields(type, config = {}) {
    const container = $("#config-fields");
    let html = "";

    if (type === "terminal_command") {
        html += `
            <label for="cfg-command">Command (use {text} for transcribed text)</label>
            <input type="text" id="cfg-command" value="${escapeHtml(config.command || "")}" placeholder="opencode">
            <label>
                <input type="checkbox" id="cfg-paste" ${config.paste_text !== false ? "checked" : ""}>
                Paste transcribed text into Terminal
            </label>
        `;
    } else if (type === "clipboard") {
        html += '<p style="color: var(--text-muted); font-size: 0.8rem;">No configuration needed. Copies transcribed text to clipboard.</p>';
    } else if (type === "open_app") {
        html += `
            <label for="cfg-app">Application name</label>
            <input type="text" id="cfg-app" value="${escapeHtml(config.app || "")}" placeholder="Notes">
        `;
    } else if (type === "http_request") {
        html += `
            <label for="cfg-url">URL</label>
            <input type="text" id="cfg-url" value="${escapeHtml(config.url || "")}" placeholder="https://example.com/webhook">
            <label for="cfg-method">Method</label>
            <select id="cfg-method">
                <option value="POST" ${config.method === "POST" ? "selected" : ""}>POST</option>
                <option value="GET" ${config.method === "GET" ? "selected" : ""}>GET</option>
            </select>
            <label for="cfg-body">Body template (use {text} for transcribed text)</label>
            <textarea id="cfg-body" placeholder='{"text": "{text}"}'>${escapeHtml(config.body_template || "")}</textarea>
            <label for="cfg-headers">Headers (JSON)</label>
            <textarea id="cfg-headers" placeholder='{"Content-Type": "application/json"}'>${escapeHtml(config.headers ? JSON.stringify(config.headers) : "")}</textarea>
        `;
    }

    container.innerHTML = html;
}

function getConfigFromForm(type) {
    if (type === "terminal_command") {
        return {
            command: $("#cfg-command").value,
            paste_text: $("#cfg-paste").checked,
            new_window: true,
        };
    } else if (type === "clipboard") {
        return {};
    } else if (type === "open_app") {
        return {
            app: $("#cfg-app").value,
        };
    } else if (type === "http_request") {
        const headersStr = $("#cfg-headers").value.trim();
        let headers = {};
        if (headersStr) {
            try {
                headers = JSON.parse(headersStr);
            } catch (e) {
                alert("Invalid JSON in headers field.");
                throw e;
            }
        }
        return {
            url: $("#cfg-url").value,
            method: $("#cfg-method").value,
            body_template: $("#cfg-body").value,
            headers: headers,
        };
    }
    return {};
}

async function saveAction(e) {
    e.preventDefault();

    const name = $("#action-name").value.trim();
    const description = $("#action-desc").value.trim();
    const type = $("#action-type").value;

    if (!name || !type) {
        alert("Name and Type are required.");
        return;
    }

    let config;
    try {
        config = getConfigFromForm(type);
    } catch {
        return;
    }

    const action = { name, description, type, config };

    try {
        const resp = await fetch("/api/actions", {
            method: "POST",
            headers: authHeaders({ "Content-Type": "application/json" }),
            body: JSON.stringify(action),
        });
        if (!resp.ok) {
            const err = await resp.json();
            throw new Error(err.detail || "Failed to save action");
        }
        hideModal();
        await loadActions();
    } catch (e) {
        console.error("Failed to save action:", e);
        alert("Failed to save action: " + e.message);
    }
}

// ── History ──────────────────────────────────────────────────────────────
async function loadHistory() {
    try {
        const resp = await fetch("/api/history");
        STATE.history = await resp.json();
        renderHistory();
    } catch (e) {
        console.error("Failed to load history:", e);
    }
}

function renderHistory() {
    const list = $("#history-list");
    const viewAll = $("#view-all-link");

    if (STATE.history.length === 0) {
        list.innerHTML = '<div class="history-empty">Transcriptions will appear here after your first recording.</div>';
        viewAll.classList.add("hidden");
        return;
    }

    const visible = STATE.history.slice(0, 10);
    list.innerHTML = visible
        .map(
            (entry) => `
        <div class="history-item">
            <div class="history-text">${escapeHtml(entry.text)}</div>
            <div class="history-time">${escapeHtml(entry.iso)}</div>
        </div>`
        )
        .join("");

    if (STATE.history.length > 10) {
        viewAll.classList.remove("hidden");
        viewAll.textContent = `View all (${STATE.history.length} total)`;
    } else {
        viewAll.classList.add("hidden");
    }
}

function addHistoryItem(text) {
    STATE.history.unshift({
        text,
        iso: new Date().toISOString().replace("T", " ").substring(0, 19),
    });
    if (STATE.history.length > 50) STATE.history.length = 50;
    renderHistory();
}

// ── Modal ────────────────────────────────────────────────────────────────
function showModal() {
    $("#modal-overlay").classList.remove("hidden");
    // Focus first input
    setTimeout(() => $("#action-name").focus(), 50);
}

function hideModal() {
    $("#modal-overlay").classList.add("hidden");
}

// ── Settings Modal ──────────────────────────────────────────────────────
function openSettingsModal() {
    STATE.settingsModalVisible = true;
    const currentHotkey = STATE.settings?.hotkey || "cmd+shift+space";
    $("#settings-current-hotkey").textContent = currentHotkey;
    resetShortcutRecorder();
    $("#settings-save-success").classList.add("hidden");
    $("#settings-modal-overlay").classList.remove("hidden");
}

function closeSettingsModal() {
    STATE.settingsModalVisible = false;
    stopShortcutRecording();
    $("#settings-modal-overlay").classList.add("hidden");
}

function startShortcutRecording() {
    STATE.recordingShortcut = true;
    STATE.capturedHotkey = null;
    $("#shortcut-recorder-placeholder").classList.remove("hidden");
    $("#shortcut-captured").classList.add("hidden");
    $("#shortcut-error").classList.add("hidden");
    $("#btn-record-shortcut").disabled = true;
    $("#btn-save-settings").disabled = true;

    document.addEventListener("keydown", onShortcutKeydown);
}

function stopShortcutRecording() {
    STATE.recordingShortcut = false;
    document.removeEventListener("keydown", onShortcutKeydown);
    $("#btn-record-shortcut").disabled = false;
}

function resetShortcutRecorder() {
    STATE.capturedHotkey = null;
    $("#shortcut-recorder-placeholder").classList.add("hidden");
    $("#shortcut-captured").classList.add("hidden");
    $("#shortcut-error").classList.add("hidden");
    $("#btn-record-shortcut").disabled = false;
    $("#btn-save-settings").disabled = true;
}

function onShortcutKeydown(e) {
    if (!STATE.recordingShortcut) return;

    e.preventDefault();
    e.stopPropagation();

    // Escape during recording cancels
    if (e.key === "Escape") {
        stopShortcutRecording();
        resetShortcutRecorder();
        return;
    }

    // Collect modifiers
    const modifiers = [];
    if (e.metaKey) modifiers.push("cmd");
    if (e.ctrlKey) modifiers.push("ctrl");
    if (e.altKey) modifiers.push("alt");
    if (e.shiftKey) modifiers.push("shift");

    // Ignore pure modifier key presses
    if (e.key === "Meta" || e.key === "Control" || e.key === "Alt" || e.key === "Shift") {
        return;
    }

    // Validate: at least one modifier required
    if (modifiers.length === 0) {
        showShortcutError("Shortcut must include at least one modifier (Cmd, Ctrl, Alt, Shift)");
        return;
    }

    // Map special keys
    const specialKeyMap = {
        " ": "space",
        "Tab": "tab",
        "Enter": "enter",
        "Escape": "esc",
        "Backspace": "backspace",
        "Delete": "delete",
        "ArrowUp": "up",
        "ArrowDown": "down",
        "ArrowLeft": "left",
        "ArrowRight": "right",
    };

    let key;
    // F1-F20
    if (/^F\d+$/.test(e.key)) {
        key = e.key.toLowerCase();
    } else if (specialKeyMap[e.key] !== undefined) {
        key = specialKeyMap[e.key];
    } else if (e.key.length === 1) {
        // Single character keys (letters, digits, punctuation)
        key = e.key.toLowerCase();
    } else {
        showShortcutError("Unrecognized key. Try a different combination.");
        return;
    }

    // Normalize: modifiers in order cmd, ctrl, alt, shift, key
    const combo = modifiers.join("+") + "+" + key;

    // Success
    STATE.capturedHotkey = combo;
    stopShortcutRecording();

    $("#shortcut-recorder-placeholder").classList.add("hidden");
    $("#shortcut-captured").textContent = combo;
    $("#shortcut-captured").classList.remove("hidden");
    $("#shortcut-error").classList.add("hidden");
    $("#btn-save-settings").disabled = false;
}

function showShortcutError(message) {
    $("#shortcut-error").textContent = message;
    $("#shortcut-error").classList.remove("hidden");
}

async function saveSettings() {
    const hotkey = STATE.capturedHotkey;
    if (!hotkey) return;

    try {
        const resp = await fetch("/api/settings", {
            method: "POST",
            headers: authHeaders({ "Content-Type": "application/json" }),
            body: JSON.stringify({ hotkey }),
        });
        if (!resp.ok) {
            const err = await resp.json();
            throw new Error(err.detail || "Failed to save settings");
        }
        const data = await resp.json();
        STATE.settings = data;

        // Update displayed current hotkey
        $("#settings-current-hotkey").textContent = data.hotkey || STATE.capturedHotkey;

        // Reset recorder state
        resetShortcutRecorder();

        // Show success indicator
        const successEl = $("#settings-save-success");
        successEl.classList.remove("hidden");
        // Re-trigger animation
        successEl.style.animation = "none";
        successEl.offsetHeight; // force reflow
        successEl.style.animation = "fade-out-success 2s ease-out forwards";

        setTimeout(() => {
            closeSettingsModal();
        }, 2100);
    } catch (e) {
        console.error("Failed to save settings:", e);
        showShortcutError("Failed to save: " + e.message);
    }
}

// ── Utilities ────────────────────────────────────────────────────────────
function escapeHtml(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
}

// ── Event Bindings ───────────────────────────────────────────────────────
function bindEvents() {
    // Modal
    $("#btn-add-action").addEventListener("click", openAddActionModal);
    $("#btn-modal-close").addEventListener("click", hideModal);
    $("#btn-modal-cancel").addEventListener("click", hideModal);
    $("#modal-overlay").addEventListener("click", (e) => {
        if (e.target === $("#modal-overlay")) hideModal();
    });
    $("#action-form").addEventListener("submit", saveAction);
    $("#action-type").addEventListener("change", (e) => {
        updateConfigFields(e.target.value);
    });

    // Keyboard: Escape to close modals
    document.addEventListener("keydown", (e) => {
        if (e.key === "Escape") {
            if (STATE.recordingShortcut) return;
            if (STATE.settingsModalVisible) {
                closeSettingsModal();
                return;
            }
            hideModal();
        }
    });

    // Delegated event listener for action edit/delete buttons
    // Uses data-* attributes instead of inline onclick to prevent XSS
    const actionsList = $("#actions-list");
    actionsList.addEventListener("click", (e) => {
        const btn = e.target.closest("button[data-action]");
        if (!btn) return;

        const actionType = btn.dataset.action;
        if (actionType === "edit") {
            const index = parseInt(btn.dataset.index, 10);
            if (!isNaN(index)) editAction(index);
        } else if (actionType === "delete") {
            const name = btn.dataset.name;
            if (name) deleteAction(name);
        }
    });

    // Settings modal
    $("#btn-settings").addEventListener("click", openSettingsModal);
    $("#btn-settings-close").addEventListener("click", closeSettingsModal);
    $("#btn-settings-cancel").addEventListener("click", closeSettingsModal);
    $("#settings-modal-overlay").addEventListener("click", (e) => {
        if (e.target === $("#settings-modal-overlay")) closeSettingsModal();
    });
    $("#btn-record-shortcut").addEventListener("click", startShortcutRecording);
    $("#btn-save-settings").addEventListener("click", saveSettings);
}

// ── Init ─────────────────────────────────────────────────────────────────
async function init() {
    bindEvents();
    initWaveform();
    connectWS();
    await loadConfig();
    await loadStatus();
    await loadActions();
    await loadHistory();

    // Poll status every 10s
    setInterval(loadStatus, 10000);
    // Poll actions every 30s
    setInterval(loadActions, 30000);
}

document.addEventListener("DOMContentLoaded", init);
