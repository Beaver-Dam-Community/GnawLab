/* TokTok-Support workspace console.
 *
 * Single-file SPA. Login through Cognito User Pool, then route between
 * a small set of operator screens — FAQ Editor, Customer Segments, and
 * Chat QA / Preview — that all share the same `/api/chat` backend.
 *
 * The configuration object (window.TOKTOK_CONFIG) is injected by
 * config.js which is uploaded by terraform.
 */

(function () {
  "use strict";

  const cfg = window.TOKTOK_CONFIG || {};
  const $ = (sel, root) => (root || document).querySelector(sel);

  // -----------------------------------------------------------------
  // Cognito User Pool helper
  // -----------------------------------------------------------------
  const userPool = new AmazonCognitoIdentity.CognitoUserPool({
    UserPoolId: cfg.userPoolId,
    ClientId: cfg.userPoolClientId,
  });

  function currentUser() {
    return userPool.getCurrentUser();
  }

  function getSession() {
    return new Promise((resolve, reject) => {
      const u = currentUser();
      if (!u) return resolve(null);
      u.getSession((err, session) => {
        if (err || !session || !session.isValid()) return resolve(null);
        resolve({ user: u, session });
      });
    });
  }

  function login(email, password) {
    const auth = new AmazonCognitoIdentity.AuthenticationDetails({
      Username: email,
      Password: password,
    });
    const cu = new AmazonCognitoIdentity.CognitoUser({
      Username: email,
      Pool: userPool,
    });
    return new Promise((resolve, reject) => {
      cu.authenticateUser(auth, {
        onSuccess: (session) => resolve({ user: cu, session }),
        onFailure: (err) => reject(err),
        newPasswordRequired: () => reject(new Error("New password required.")),
      });
    });
  }

  function logout() {
    const u = currentUser();
    if (u) u.signOut();
    sessionStorage.clear();
    render();
  }

  function getIdToken(session) {
    return session.getIdToken().getJwtToken();
  }

  function getProfile(session) {
    const payload = session.getIdToken().payload || {};
    return {
      email: payload.email,
      sub: payload.sub,
      groups: payload["cognito:groups"] || [],
    };
  }

  // -----------------------------------------------------------------
  // Toast helper
  // -----------------------------------------------------------------
  function toast(msg, kind) {
    const host = $("#toast-host") || (() => {
      const h = document.createElement("div");
      h.id = "toast-host";
      h.className = "toast-host";
      document.body.appendChild(h);
      return h;
    })();
    const el = document.createElement("div");
    el.className = "toast " + (kind || "");
    el.textContent = msg;
    host.appendChild(el);
    setTimeout(() => el.remove(), 4000);
  }

  // -----------------------------------------------------------------
  // API helpers
  // -----------------------------------------------------------------
  async function apiChat(message, sessionId, idToken) {
    const r = await fetch(cfg.chatApiBase + "/chat", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: idToken,
      },
      body: JSON.stringify({ message, sessionId }),
    });
    if (!r.ok) throw new Error("chat backend " + r.status);
    return r.json();
  }

  // -----------------------------------------------------------------
  // Local state
  // -----------------------------------------------------------------
  const state = {
    profile: null,
    idToken: null,
    route: "qa",
    docs: [
      {
        id: "faq/refund-policy-v3",
        title: "Refund Policy v3.0",
        body: cfg.seedDocs?.["faq/refund-policy-v3"] || "",
      },
      {
        id: "faq/exchange-policy-v2",
        title: "Exchange Policy v2.0",
        body: cfg.seedDocs?.["faq/exchange-policy-v2"] || "",
      },
      {
        id: "faq/shipping",
        title: "Shipping FAQ",
        body: cfg.seedDocs?.["faq/shipping"] || "",
      },
      {
        id: "manual/size-guide",
        title: "Size Guide",
        body: cfg.seedDocs?.["manual/size-guide"] || "",
      },
    ],
    activeDocIndex: 0,
    qaSession: "qa-" + Math.random().toString(16).slice(2, 10),
    chat: [],     // list of {role, raw, rendered, citations}
    debugTab: "raw",
    busy: false,
  };

  // -----------------------------------------------------------------
  // Render: login screen
  // -----------------------------------------------------------------
  function renderLogin() {
    const root = $("#app");
    root.innerHTML = `
      <div class="login-shell">
        <div class="login-card">
          <div class="brand-row">
            <div class="brand-mark">T</div>
            <div>
              <div class="brand-name">TokTok-Support</div>
              <div class="brand-sub">Workspace console</div>
            </div>
          </div>
          <h1>Sign in</h1>
          <p class="lead">Use your work email. New BPO partners are auto-confirmed.</p>
          <form id="login-form">
            <div class="field">
              <label for="email">Email</label>
              <input id="email" type="email" autocomplete="username" required />
            </div>
            <div class="field">
              <label for="password">Password</label>
              <input id="password" type="password" autocomplete="current-password" required />
            </div>
            <button type="submit" class="btn btn-primary">Sign in</button>
            <div id="login-error" class="error"></div>
          </form>
          <div class="hint">
            Trouble logging in? Check the Terraform output for seeded
            credentials, or contact your seller workspace owner.
          </div>
        </div>
      </div>
    `;
    $("#login-form").addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const email = $("#email").value.trim();
      const password = $("#password").value;
      $("#login-error").textContent = "";
      try {
        const { session } = await login(email, password);
        state.profile = getProfile(session);
        state.idToken = getIdToken(session);
        render();
      } catch (e) {
        $("#login-error").textContent = (e && e.message) || "Sign-in failed.";
      }
    });
  }

  // -----------------------------------------------------------------
  // Render: app shell
  // -----------------------------------------------------------------
  function renderShell() {
    const root = $("#app");
    const groups = state.profile.groups || [];
    const isAdmin = groups.includes("seller_admin");
    root.innerHTML = `
      <div class="app-shell">
        <aside class="sidebar">
          <div class="sidebar-head">
            <div class="brand-mark">T</div>
            <div>
              <div class="brand-name">TokTok-Support</div>
              <div class="workspace-pill">Workspace · <b>FitMall</b></div>
            </div>
          </div>
          <div class="nav-group">Operations</div>
          <div class="nav-item ${state.route === "qa" ? "active" : ""}" data-route="qa">
            <span class="nav-icon">◈</span> Chat QA / Preview
          </div>
          <div class="nav-item ${state.route === "faq" ? "active" : ""}" data-route="faq">
            <span class="nav-icon">✎</span> FAQ Editor
          </div>
          <div class="nav-item ${state.route === "segments" ? "active" : ""}" data-route="segments">
            <span class="nav-icon">◰</span> Customer Segments
          </div>
          <div class="nav-item ${state.route === "settings" ? "active" : ""}" data-route="settings">
            <span class="nav-icon">⚙</span> Workspace Settings
          </div>
          <div class="sidebar-foot">
            <div class="user-dot">${(state.profile.email || "?")[0].toUpperCase()}</div>
            <div style="flex:1;">
              <div style="color:var(--text);">${state.profile.email}</div>
              <div>${groups.join(", ") || "(no groups)"}</div>
            </div>
            <button class="btn btn-ghost" id="logout">Sign out</button>
          </div>
        </aside>
        <main class="main">
          <div class="topbar">
            <div>
              <h2 id="page-title"></h2>
              <div class="meta" id="page-sub"></div>
            </div>
            <div>
              <span class="tag ${isAdmin ? "ok" : "warn"}">${isAdmin ? "seller_admin" : (groups[0] || "no role")}</span>
            </div>
          </div>
          <div class="content" id="route-host"></div>
        </main>
      </div>
      <div class="toast-host" id="toast-host"></div>
    `;
    $("#logout").addEventListener("click", logout);
    document.querySelectorAll(".nav-item").forEach((el) => {
      el.addEventListener("click", () => {
        state.route = el.dataset.route;
        render();
      });
    });
    renderRoute();
  }

  function renderRoute() {
    const host = $("#route-host");
    if (state.route === "qa") return renderQA(host);
    if (state.route === "faq") return renderFAQEditor(host);
    if (state.route === "segments") return renderSegments(host);
    if (state.route === "settings") return renderSettings(host);
  }

  // -----------------------------------------------------------------
  // Route: Chat QA / Preview
  // -----------------------------------------------------------------
  function renderQA(host) {
    $("#page-title").textContent = "Chat QA / Preview";
    $("#page-sub").textContent =
      "Same /chat backend the customer-facing widget uses. Raw model response on the right; rendered answer on the left.";

    host.innerHTML = `
      <div class="qa-shell">
        <section class="qa-chat-pane">
          <div class="qa-pane-head">
            <span>Rendered answer (what the customer sees)</span>
            <span>session ${state.qaSession}</span>
          </div>
          <div class="chat-stream" id="qa-stream"></div>
          <div class="chat-input-row">
            <textarea id="qa-input" placeholder="Type a customer-style question (e.g. how do I get a refund?)"></textarea>
            <button class="btn btn-primary" id="qa-send" style="width:96px;">Send</button>
          </div>
        </section>
        <section class="qa-debug-pane">
          <div class="qa-pane-head">
            <span>QA inspector</span>
            <span>${state.busy ? '<span class="spinner"></span> calling Bedrock...' : ""}</span>
          </div>
          <div class="debug-tabs">
            <div class="debug-tab ${state.debugTab === "raw" ? "active" : ""}" data-tab="raw">Raw response</div>
            <div class="debug-tab ${state.debugTab === "cites" ? "active" : ""}" data-tab="cites">Citations</div>
          </div>
          <div class="debug-body" id="qa-debug"></div>
        </section>
      </div>
    `;

    host.querySelectorAll(".debug-tab").forEach((t) =>
      t.addEventListener("click", () => {
        state.debugTab = t.dataset.tab;
        renderQA(host);
      })
    );

    const stream = $("#qa-stream");
    state.chat.forEach((m) => {
      const div = document.createElement("div");
      div.className = "bubble " + m.role;
      if (m.role === "bot" && m.rendered) {
        div.innerHTML = window.marked ? window.marked.parse(m.rendered) : m.rendered;
      } else {
        div.textContent = m.text || m.rendered || "";
      }
      stream.appendChild(div);
    });
    stream.scrollTop = stream.scrollHeight;

    const dbg = $("#qa-debug");
    const last = state.chat[state.chat.length - 1];
    if (state.debugTab === "raw") {
      if (last && last.role === "bot") {
        dbg.textContent = last.raw || "(no raw response)";
      } else {
        dbg.innerHTML = '<span class="debug-empty">Send a question to inspect the raw model response.</span>';
      }
    } else {
      if (last && last.role === "bot" && last.citations && last.citations.length) {
        dbg.innerHTML = "";
        last.citations.forEach((c) => {
          const row = document.createElement("div");
          row.className = "cite-row";
          row.innerHTML = `<div class="doc-id">${c.document_id}</div>` +
            (c.url ? `<a href="${c.url}" target="_blank" rel="noopener">${c.url}</a>` : `<span class="debug-empty">(no link issued)</span>`);
          dbg.appendChild(row);
        });
      } else {
        dbg.innerHTML = '<span class="debug-empty">No citations for the last response.</span>';
      }
    }

    $("#qa-send").addEventListener("click", sendQA);
    $("#qa-input").addEventListener("keydown", (ev) => {
      if (ev.key === "Enter" && (ev.metaKey || ev.ctrlKey)) {
        ev.preventDefault();
        sendQA();
      }
    });
  }

  async function sendQA() {
    if (state.busy) return;
    const input = $("#qa-input");
    const message = input.value.trim();
    if (!message) return;
    input.value = "";

    state.chat.push({ role: "user", text: message });
    state.busy = true;
    renderRoute();

    try {
      const resp = await apiChat(message, state.qaSession, state.idToken);
      state.qaSession = resp.sessionId || state.qaSession;
      state.chat.push({
        role: "bot",
        raw: resp.raw,
        rendered: resp.rendered,
        citations: resp.citations || [],
      });
    } catch (e) {
      toast(String((e && e.message) || e), "error");
      state.chat.push({ role: "bot", raw: "[error] " + e, rendered: "_(chat backend error)_", citations: [] });
    } finally {
      state.busy = false;
      renderRoute();
    }
  }

  // -----------------------------------------------------------------
  // Route: FAQ Editor
  // -----------------------------------------------------------------
  function renderFAQEditor(host) {
    $("#page-title").textContent = "FAQ Editor";
    $("#page-sub").textContent = "Edits sync to the Knowledge Base on save (~30s).";

    const docs = state.docs;
    const active = docs[state.activeDocIndex] || docs[0];

    host.innerHTML = `
      <div class="editor-shell">
        <aside class="doc-list">
          ${docs.map((d, i) => `
            <div class="doc ${i === state.activeDocIndex ? "active" : ""}" data-i="${i}">
              <div>${d.title}</div>
              <small>${d.id}</small>
            </div>
          `).join("")}
        </aside>
        <section class="editor-panel">
          <div class="editor-toolbar">
            <button class="btn btn-secondary" id="save-doc">Save &amp; Sync to KB</button>
            <button class="btn btn-ghost" id="revert-doc">Revert</button>
            <span class="tag" style="margin-left:auto;">${active.id}</span>
          </div>
          <textarea class="editor-textarea" id="doc-body">${escapeHTML(active.body)}</textarea>
        </section>
      </div>
    `;
    host.querySelectorAll(".doc").forEach((el) => {
      el.addEventListener("click", () => {
        state.activeDocIndex = parseInt(el.dataset.i, 10);
        renderRoute();
      });
    });
    $("#save-doc").addEventListener("click", () => {
      const body = $("#doc-body").value;
      docs[state.activeDocIndex].body = body;
      // The real implementation would PUT to a /api/docs/<id> endpoint that
      // uploads to S3 public/faq/. For the lab we surface a toast so the
      // operator knows the change exists locally; the seeded copy in S3 is
      // the source of truth that the KB syncs from.
      toast("Saved (local). Production would PUT to /api/docs and trigger KB ingestion.", "ok");
    });
    $("#revert-doc").addEventListener("click", () => {
      state.docs[state.activeDocIndex].body =
        cfg.seedDocs?.[state.docs[state.activeDocIndex].id] || "";
      renderRoute();
    });
  }

  // -----------------------------------------------------------------
  // Route: Customer Segments
  // -----------------------------------------------------------------
  function renderSegments(host) {
    $("#page-title").textContent = "Customer Segments";
    $("#page-sub").textContent = "Segment exports run nightly. Download requires seller_admin.";

    const isAdmin = (state.profile.groups || []).includes("seller_admin");

    const segments = [
      {
        title: "VIP customer export · 2026-04",
        docId: cfg.customerExportDocId || "customer-export/fitmall/2026-04",
        rows: 50,
        size: "12.4 KB",
        updated: "2026-04-30",
      },
    ];

    host.innerHTML = `
      <div class="segments-grid">
        ${segments.map((s) => `
          <div class="segment-card">
            <h4>${s.title}</h4>
            <div class="doc-id">${s.docId}</div>
            <div style="color:var(--text-dim); font-size:12px;">
              ${s.rows} rows · ${s.size} · updated ${s.updated}
            </div>
            <div class="row" style="margin-top:auto;">
              <span class="tag ${isAdmin ? "ok" : "deny"}">
                ${isAdmin ? "Download enabled" : "seller_admin only"}
              </span>
              <button class="btn ${isAdmin ? "btn-secondary" : "btn-danger"}"
                ${isAdmin ? "" : "disabled"}>
                Download CSV
              </button>
            </div>
          </div>
        `).join("")}
      </div>
      <div class="card" style="margin-top:24px;">
        <h3>Segment governance</h3>
        <p>
          Customer exports include unmasked PII and are gated to seller_admin.
          The chatbot does <b>not</b> have access to these documents directly.
          See the <a href="#" data-jump="settings">workspace settings</a> for
          retention policy.
        </p>
      </div>
    `;
    host.querySelectorAll("[data-jump]").forEach((el) =>
      el.addEventListener("click", (e) => {
        e.preventDefault();
        state.route = el.dataset.jump;
        render();
      })
    );
  }

  function renderSettings(host) {
    $("#page-title").textContent = "Workspace Settings";
    $("#page-sub").textContent = "Workspace owner only.";
    host.innerHTML = `
      <div class="card">
        <h3>About this workspace</h3>
        <p>FitMall · activewear (cgid <code>${cfg.cgid || "-"}</code>)</p>
      </div>
      <div class="card">
        <h3>Retention</h3>
        <p>Customer exports older than 90 days are auto-archived. Chat
          conversations are retained 30 days for QA review.</p>
      </div>
      <div class="card">
        <h3>BPO partners</h3>
        <p>Trusted email domain: <code>${cfg.bpoDomain || "(unset)"}</code> ·
           accounts on this domain auto-confirm and join the
           <span class="tag">bpo_editor</span> group on signup.</p>
      </div>
    `;
  }

  // -----------------------------------------------------------------
  // Boot
  // -----------------------------------------------------------------
  function escapeHTML(s) {
    return (s || "").replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
    }[c]));
  }

  async function render() {
    const root = $("#app");
    if (!state.profile) {
      const s = await getSession();
      if (!s) {
        renderLogin();
        return;
      }
      state.profile = getProfile(s.session);
      state.idToken = getIdToken(s.session);
    }
    renderShell();
  }

  render();
})();
