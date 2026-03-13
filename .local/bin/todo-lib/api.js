const https = require("https");
const fs = require("fs");
const path = require("path");
const os = require("os");

function getToken() {
  if (process.env.TODOIST_API_TOKEN) return process.env.TODOIST_API_TOKEN;
  const tokenPath = path.join(os.homedir(), ".config", "todoist", "token");
  try {
    return fs.readFileSync(tokenPath, "utf8").trim();
  } catch {
    return null;
  }
}

function request(method, urlPath, body, { timeout } = {}) {
  const token = getToken();
  if (!token) {
    return Promise.reject(
      new Error(
        "No API token. Set TODOIST_API_TOKEN or put token in ~/.config/todoist/token"
      )
    );
  }

  return new Promise((resolve, reject) => {
    const options = {
      hostname: "api.todoist.com",
      path: urlPath,
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
    };
    if (timeout) options.timeout = timeout;

    const req = https.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        if (res.statusCode === 204) return resolve(null);
        if (res.statusCode >= 400) {
          let msg = `HTTP ${res.statusCode}`;
          try {
            msg = JSON.parse(data).message || msg;
          } catch {}
          return reject(new Error(msg));
        }
        try {
          resolve(JSON.parse(data));
        } catch {
          resolve(data);
        }
      });
    });

    if (timeout) {
      req.on("timeout", () => {
        req.destroy();
        reject(new Error("timeout"));
      });
    }
    req.on("error", reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

function listTasks(params) {
  const qs = params
    ? "?" +
      Object.entries(params)
        .filter(([, v]) => v != null)
        .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
        .join("&")
    : "";
  return request("GET", `/api/v1/tasks${qs}`).then((d) => d.results || []);
}

function getTask(id) {
  return request("GET", `/api/v1/tasks/${id}`);
}

function createTask(body) {
  return request("POST", "/api/v1/tasks", body);
}

function closeTask(id) {
  return request("POST", `/api/v1/tasks/${id}/close`);
}

function deleteTask(id) {
  return request("DELETE", `/api/v1/tasks/${id}`);
}

function updateTask(id, body) {
  return request("POST", `/api/v1/tasks/${id}`, body);
}

function listProjects() {
  return request("GET", "/api/v1/projects").then((d) => d.results || []);
}

function listTasksQuick() {
  return request("GET", "/api/v1/tasks", null, { timeout: 3000 }).then((d) => d.results || []);
}

function listCompletedTasks(params) {
  const since = params?.since || new Date(Date.now() - 7 * 86400000).toISOString();
  const until = params?.until || new Date().toISOString();
  const qs = new URLSearchParams({ since, until, limit: String(params?.limit || 50) });
  if (params?.project_id) qs.set("project_id", params.project_id);
  return request("GET", `/api/v1/tasks/completed/by_completion_date?${qs}`).then((d) => d.items || []);
}

function listProjectsQuick() {
  return request("GET", "/api/v1/projects", null, { timeout: 3000 }).then((d) => d.results || []);
}

function listSections(params) {
  const qs = params
    ? "?" +
      Object.entries(params)
        .filter(([, v]) => v != null)
        .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
        .join("&")
    : "";
  return request("GET", `/api/v1/sections${qs}`).then((d) => d.results || d);
}

function getSection(id) {
  return request("GET", `/api/v1/sections/${id}`);
}

function createSection(body) {
  return request("POST", "/api/v1/sections", body);
}

function updateSection(id, body) {
  return request("POST", `/api/v1/sections/${id}`, body);
}

function deleteSection(id) {
  return request("DELETE", `/api/v1/sections/${id}`);
}

function listSectionsQuick() {
  return request("GET", "/api/v1/sections", null, { timeout: 3000 }).then((d) => d.results || d);
}

function moveTask(id, body) {
  return request("POST", `/api/v1/tasks/${id}/move`, body);
}

module.exports = {
  listTasks,
  getTask,
  createTask,
  closeTask,
  deleteTask,
  updateTask,
  listProjects,
  listCompletedTasks,
  listTasksQuick,
  listProjectsQuick,
  listSections,
  getSection,
  createSection,
  updateSection,
  deleteSection,
  listSectionsQuick,
  moveTask,
};
