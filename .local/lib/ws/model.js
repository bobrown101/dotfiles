const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const os = require("os");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const HOME = os.homedir();
const SRC = path.join(HOME, "src");
const WS_DIR = path.join(HOME, "src", "workspaces");
const BRANCH_PREFIX = "brbrown";

// ---------------------------------------------------------------------------
// Shell / process helpers
// ---------------------------------------------------------------------------

function tmuxHasSession(name) {
  return (
    spawnSync("tmux", ["has-session", "-t", name], { stdio: "pipe" })
      .status === 0
  );
}

function pgrepCount(pattern) {
  const result = spawnSync("pgrep", ["-f", pattern], {
    encoding: "utf8",
    stdio: "pipe",
  });
  if (result.status !== 0) return 0;
  return result.stdout.trim().split("\n").filter(Boolean).length;
}

// ---------------------------------------------------------------------------
// Filesystem helpers
// ---------------------------------------------------------------------------

function getRepos(wsPath) {
  if (!fs.existsSync(wsPath)) return [];
  return fs
    .readdirSync(wsPath, { withFileTypes: true })
    .filter(
      (d) =>
        d.isDirectory() && fs.existsSync(path.join(wsPath, d.name, ".git"))
    )
    .map((d) => d.name)
    .sort();
}

function parentRepo(wtPath) {
  const gitFile = path.join(wtPath, ".git");
  if (!fs.existsSync(gitFile) || fs.statSync(gitFile).isDirectory()) {
    return null;
  }
  const content = fs.readFileSync(gitFile, "utf8").trim();
  const gitdir = content.replace("gitdir: ", "");
  const match = gitdir.match(/^(.*)\/\.git\/worktrees\/.*/);
  return match ? match[1] : null;
}

function allWorkspaces() {
  if (!fs.existsSync(WS_DIR)) return [];
  return fs
    .readdirSync(WS_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort();
}

function getSrcRepos() {
  if (!fs.existsSync(SRC)) return [];
  return fs
    .readdirSync(SRC, { withFileTypes: true })
    .filter(
      (d) => d.isDirectory() && fs.existsSync(path.join(SRC, d.name, ".git"))
    )
    .map((d) => d.name)
    .sort();
}

// ---------------------------------------------------------------------------
// URL maps
// ---------------------------------------------------------------------------

const APP_PATHS = {
  "crm-index-ui": "/contacts/103830646/objects/0-1/views/all/list",
  "crm-object-table": "/crm-object-table-kitchen-sink/103830646/",
  "customer-data-table": "/framework-data-table-kitchen-sink/103830646/",
  "crm-object-board": "/crm-object-board-kitchen-sink/103830646/",
  "customer-data-bulk-actions":
    "/customer-data-bulk-actions-kitchen-sink/103830646/",
  "customer-data-properties":
    "/customer-data-properties-kitchen-sink/99632791/",
  "crm-index-view-components": "/crm-index-toolbar-sandbox-ui/103830646",
  "crm-object-gantt": "/crm-object-gantt-kitchen-sink/103830646/",
};

const TEST_PATHS = {
  "crm-index-ui": ["/crm-index-ui/static/test/test.html?spec="],
  "crm-object-table": ["/crm-object-table/static/test/test.html?spec="],
  "customer-data-table": [
    "/framework-data-table/static/test/test.html?spec=",
  ],
  "crm-object-search-query-libs": [
    "/crm-object-search-query-utilities/static/test/test.html?spec=",
  ],
  "customer-data-bulk-actions": [
    "/customer-data-bulk-actions-container/static/test/test.html?spec=",
    "/customer-data-bulk-actions/static/test/test.html?spec=",
  ],
  "customer-data-tracking": [
    "/customer-data-tracking/static/test/test.html?spec=",
  ],
  "customer-data-sidebar": [
    "/customer-data-sidebar/static/test/test.html?spec=",
  ],
  "customer-data-properties": [
    "/customer-data-properties/static/test/test.html?spec=",
  ],
  "crm-settings": ["/crm-settings/static/test/test.html"],
  "crm-records-ui": ["/crm-records-ui/static/test/test.html?spec="],
  "reference-resolvers-lite": [
    "/reference-resolvers-lite/static/test/test.html?spec=",
  ],
  "customer-data-associations": [
    "/customer-data-associations/static/test/test.html?spec=",
  ],
  "customer-data-views-management": [
    "/customer-data-views-management/static/test/test.html?spec=",
    "/views-management-ui/static/test/test.html?spec=",
  ],
  "crm-index-view-components": [
    "/crm-index-view-components-main/static/test/test.html?spec=",
    "/crm-index-view-table-edit-columns-modal/static/test/test.html?spec=",
    "/crm-index-visualization-toolbar/static/test/test.html",
  ],
  "crm-index-associations-lib": [
    "/crm-index-associations-lib/static/test/test.html?spec=",
  ],
  reporting: [
    "/reporting-crm-object-table/static/test/test.html",
    "/reporting-enablement/static/test/test.html?spec=",
  ],
  "crm-links": ["/crm-links/static/test/test.html"],
  pulse: ["/pulse/static/test/test.html"],
};

function appUrl(repo, base) {
  const p = APP_PATHS[repo];
  return p ? base + p : null;
}

function testUrls(repo, base) {
  const paths = TEST_PATHS[repo];
  return paths ? paths.map((p) => base + p) : [];
}

// ---------------------------------------------------------------------------
// Worktree operations
// ---------------------------------------------------------------------------

function getCurrentBranch(wtPath) {
  const result = spawnSync("git", ["-C", wtPath, "branch", "--show-current"], {
    encoding: "utf8",
    stdio: "pipe",
  });
  return result.stdout.trim();
}

// Returns { success: true } or { success: false, detail: string }
function switchBranch(wtPath, branch) {
  const repoDir = parentRepo(wtPath);
  if (repoDir) {
    spawnSync("git", ["-C", repoDir, "fetch", "origin"], { stdio: "pipe" });
  }

  const checkout = spawnSync("git", ["-C", wtPath, "checkout", branch], {
    encoding: "utf8",
    stdio: "pipe",
  });
  if (checkout.status === 0) return { success: true };

  const create = spawnSync(
    "git",
    ["-C", wtPath, "checkout", "-b", branch, "origin/master"],
    { encoding: "utf8", stdio: "pipe" }
  );
  if (create.status === 0) return { success: true };

  return { success: false, detail: (checkout.stderr || create.stderr).trim() };
}

// Returns { status: "new"|"existing", branch } or null on failure
function createWorktree(repoDir, wtPath, branch) {
  const tryNew = spawnSync(
    "git",
    ["-C", repoDir, "worktree", "add", "-b", branch, wtPath, "origin/master"],
    { stdio: "pipe" }
  );
  if (tryNew.status === 0) {
    spawnSync(
      "git",
      ["-C", wtPath, "pull", "--ff-only", "origin", "master"],
      { stdio: "inherit" }
    );
    return { status: "new", branch };
  }
  const tryExisting = spawnSync(
    "git",
    ["-C", repoDir, "worktree", "add", wtPath, branch],
    { stdio: "pipe" }
  );
  if (tryExisting.status === 0) {
    spawnSync(
      "git",
      ["-C", wtPath, "pull", "--ff-only", "origin", "master"],
      { stdio: "inherit" }
    );
    return { status: "existing", branch };
  }
  return null;
}

function removeWorktree(wtPath) {
  const repoDir = parentRepo(wtPath);
  if (!repoDir) return { status: "error", detail: "could not resolve parent repo" };
  spawnSync(
    "git",
    ["-C", repoDir, "worktree", "remove", wtPath, "--force"],
    { stdio: "pipe" }
  );
  return { status: "removed" };
}

// ---------------------------------------------------------------------------
// Process management
// ---------------------------------------------------------------------------

function buildServeCmd(name, wsRoot, repos) {
  const yarnCmds = repos.map((r) => `cd ${path.join(wsRoot, r)} && bend yarn`);
  yarnCmds.push("cd ~");
  yarnCmds.push(
    `BEND_WORKTREE=${name} NODE_ARGS=--max_old_space_size=16384 bend reactor serve ${wsRoot}/* --update --ts-watch --enable-tools --run-tests`
  );
  return yarnCmds.join(" && ");
}

// Returns messages[] describing what was cleaned up
function killProcesses(wsRoot) {
  const messages = [];
  const count = pgrepCount(wsRoot);
  if (count > 0) {
    spawnSync("pkill", ["-TERM", "-f", wsRoot], { stdio: "pipe" });
    messages.push(`Sent SIGTERM to ${count} processes`);
    spawnSync("sleep", ["2"]);
    spawnSync("pkill", ["-9", "-f", wsRoot], { stdio: "pipe" });
  }
  return messages;
}

function restartServe(name, wsRoot) {
  if (!tmuxHasSession(name)) return;

  spawnSync("tmux", ["send-keys", "-t", `${name}:serve`, "C-c"], {
    stdio: "pipe",
  });
  spawnSync("sleep", ["2"]);
  spawnSync("pkill", ["-TERM", "-f", `BEND_WORKTREE=${name}`], {
    stdio: "pipe",
  });
  spawnSync("sleep", ["1"]);
  spawnSync("pkill", ["-9", "-f", `BEND_WORKTREE=${name}`], {
    stdio: "pipe",
  });

  const repos = getRepos(wsRoot);
  const serveCmd = buildServeCmd(name, wsRoot, repos);

  spawnSync("tmux", ["send-keys", "-t", `${name}:serve`, serveCmd, "Enter"], {
    stdio: "pipe",
  });
}

// ---------------------------------------------------------------------------
// Workspace lifecycle
// ---------------------------------------------------------------------------

// Returns messages[] describing what was torn down
function teardownWorkspace(name, wsRoot) {
  const messages = [];

  messages.push(...killProcesses(wsRoot));

  if (tmuxHasSession(name)) {
    spawnSync("tmux", ["kill-session", "-t", name], { stdio: "pipe" });
    messages.push(`Killed tmux session: ${name}`);
  }

  const repos = getRepos(wsRoot);
  for (const repo of repos) {
    const wtPath = path.join(wsRoot, repo);
    const result = removeWorktree(wtPath);
    if (result.status === "removed") {
      messages.push(`Removed worktree: ${repo}`);
    }
  }

  if (fs.existsSync(wsRoot)) {
    fs.rmSync(wsRoot, { recursive: true, force: true });
  }

  return messages;
}

// Returns [{ repoDir, branch, repo }]
function gatherBranchInfo(wsRoot) {
  const repos = getRepos(wsRoot);
  const info = [];
  for (const repo of repos) {
    const wtPath = path.join(wsRoot, repo);
    const repoDir = parentRepo(wtPath);
    if (repoDir) {
      const result = spawnSync(
        "git",
        ["-C", wtPath, "branch", "--show-current"],
        { encoding: "utf8", stdio: "pipe" }
      );
      const branch = result.stdout.trim();
      if (branch) info.push({ repoDir, branch, repo });
    }
  }
  return info;
}

// Returns { success: boolean }
function deleteBranch(repoDir, branch) {
  const del = spawnSync("git", ["-C", repoDir, "branch", "-D", branch], {
    stdio: "pipe",
  });
  return { success: del.status === 0 };
}

// ---------------------------------------------------------------------------
// tmux operations
// ---------------------------------------------------------------------------

function tmuxCreateSession(name, wsRoot, serveCmd) {
  spawnSync(
    "tmux",
    ["new-session", "-d", "-s", name, "-n", "serve", "-c", wsRoot],
    { stdio: "pipe" }
  );
  spawnSync(
    "tmux",
    ["send-keys", "-t", `${name}:serve`, serveCmd, "Enter"],
    { stdio: "pipe" }
  );

  spawnSync(
    "tmux",
    ["new-window", "-t", name, "-n", "shell", "-c", wsRoot],
    { stdio: "pipe" }
  );
  spawnSync(
    "tmux",
    ["send-keys", "-t", `${name}:shell`, `ws info ${name}`, "Enter"],
    { stdio: "pipe" }
  );

  spawnSync(
    "tmux",
    ["new-window", "-t", name, "-n", "claude", "-c", wsRoot],
    { stdio: "pipe" }
  );
  spawnSync(
    "tmux",
    ["send-keys", "-t", `${name}:claude`, "claude", "Enter"],
    { stdio: "pipe" }
  );

  spawnSync("tmux", ["select-window", "-t", `${name}:shell`], {
    stdio: "pipe",
  });
}

function tmuxAttachOrSwitch(name) {
  if (process.env.TMUX) {
    spawnSync("tmux", ["switch-client", "-t", name], { stdio: "inherit" });
  } else {
    spawnSync("tmux", ["attach", "-t", name], { stdio: "inherit" });
  }
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

module.exports = {
  HOME,
  SRC,
  WS_DIR,
  BRANCH_PREFIX,
  tmuxHasSession,
  getRepos,
  parentRepo,
  allWorkspaces,
  getSrcRepos,
  appUrl,
  testUrls,
  getCurrentBranch,
  switchBranch,
  createWorktree,
  removeWorktree,
  buildServeCmd,
  restartServe,
  teardownWorkspace,
  gatherBranchInfo,
  deleteBranch,
  tmuxCreateSession,
  tmuxAttachOrSwitch,
};
