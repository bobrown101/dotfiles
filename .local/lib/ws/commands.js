const fs = require("fs");
const path = require("path");
const model = require("./model");
const view = require("./view");

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function parseRepoArgs(args, defaultBranch) {
  return args.map((arg) => {
    const idx = arg.indexOf(":");
    if (idx === -1) return { repo: arg, branch: defaultBranch };
    return { repo: arg.substring(0, idx), branch: arg.substring(idx + 1) };
  });
}

function ensureTmuxAndAttach(name, wsRoot) {
  if (!model.tmuxHasSession(name)) {
    const repos = model.getRepos(wsRoot);
    const serveCmd = model.buildServeCmd(name, wsRoot, repos);
    model.tmuxCreateSession(name, wsRoot, serveCmd);
  }
  model.tmuxAttachOrSwitch(name);
}

function validateReposExist(specs) {
  for (const spec of specs) {
    const repoDir = path.join(model.SRC, spec.repo);
    if (!fs.existsSync(repoDir)) {
      view.renderError(`  Error: repo not found at ${repoDir}`);
      process.exit(1);
    }
  }
}

// ---------------------------------------------------------------------------
// help
// ---------------------------------------------------------------------------

function cmdHelp() {
  view.renderHelp(model.BRANCH_PREFIX);
}

// ---------------------------------------------------------------------------
// ls
// ---------------------------------------------------------------------------

function cmdLs() {
  const names = model.allWorkspaces();
  const workspaces = names.map((name) => ({
    name,
    repos: model.getRepos(path.join(model.WS_DIR, name)),
    running: model.tmuxHasSession(name),
  }));
  view.renderLs(workspaces);
}

// ---------------------------------------------------------------------------
// info
// ---------------------------------------------------------------------------

function cmdInfo(args) {
  if (args.length < 1) {
    view.renderError("Usage: ws info <name>");
    process.exit(1);
  }
  const name = args[0];
  const wsRoot = path.join(model.WS_DIR, name);
  if (!fs.existsSync(wsRoot)) {
    view.renderError(`No workspace named '${name}'`);
    process.exit(1);
  }

  const repos = model.getRepos(wsRoot);
  const appBase = `https://${name}.local.app.hubspotqa.com`;
  const testBase = `https://${name}.local.hsappstatic.net`;

  view.renderInfo({
    name,
    root: wsRoot,
    repos: repos.map((repo) => {
      const wtPath = path.join(wsRoot, repo);
      return {
        name: repo,
        branch: model.getCurrentBranch(wtPath),
        appUrl: model.appUrl(repo, appBase),
        testUrls: model.testUrls(repo, testBase),
      };
    }),
  });
}

// ---------------------------------------------------------------------------
// attach
// ---------------------------------------------------------------------------

function cmdAttach(args) {
  if (args.length < 1) {
    view.renderError("Usage: ws attach <name>");
    process.exit(1);
  }
  const name = args[0];
  if (!model.tmuxHasSession(name)) {
    view.renderError(`No tmux session for workspace '${name}'`);
    process.exit(1);
  }
  model.tmuxAttachOrSwitch(name);
}

// ---------------------------------------------------------------------------
// down
// ---------------------------------------------------------------------------

function cmdDown(args) {
  if (args.length < 1) {
    view.renderError("Usage: ws down <name>");
    process.exit(1);
  }
  const name = args[0];
  const wsRoot = path.join(model.WS_DIR, name);

  if (!fs.existsSync(wsRoot)) {
    view.renderError(`No workspace named '${name}'`);
    process.exit(1);
  }

  const messages = model.teardownWorkspace(name, wsRoot);
  view.renderMessages(messages);
  console.log(`Workspace '${name}' torn down.`);
}

// ---------------------------------------------------------------------------
// nuke
// ---------------------------------------------------------------------------

function cmdNuke(args) {
  if (args.length < 1) {
    view.renderError("Usage: ws nuke <name>");
    process.exit(1);
  }
  const name = args[0];
  const wsRoot = path.join(model.WS_DIR, name);

  if (!fs.existsSync(wsRoot)) {
    view.renderError(`No workspace named '${name}'`);
    process.exit(1);
  }

  const branchInfo = model.gatherBranchInfo(wsRoot);
  view.renderNukePrompt(name, branchInfo);

  const readline = require("readline");
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  rl.question(`Nuke workspace '${name}'? [y/N] `, (answer) => {
    rl.close();
    if (answer.trim().toLowerCase() !== "y") {
      console.log("Aborted.");
      process.exit(0);
    }

    const messages = model.teardownWorkspace(name, wsRoot);
    view.renderMessages(messages);

    for (const { repoDir, branch, repo } of branchInfo) {
      const result = model.deleteBranch(repoDir, branch);
      if (result.success) {
        console.log(`Deleted branch: ${branch} (${repo})`);
      } else {
        console.log(`Could not delete branch: ${branch} (${repo})`);
      }
    }

    console.log(`Workspace '${name}' nuked.`);
  });
}

// ---------------------------------------------------------------------------
// up (create or update)
// ---------------------------------------------------------------------------

function createWorkspace(name, wsRoot, repoSpecs) {
  console.log(`Creating workspace: ${name}`);
  fs.mkdirSync(wsRoot, { recursive: true });

  for (const spec of repoSpecs) {
    const repoDir = path.join(model.SRC, spec.repo);
    const wtPath = path.join(wsRoot, spec.repo);
    const result = model.createWorktree(repoDir, wtPath, spec.branch);
    if (result) {
      console.log(
        `  Created: ${spec.repo} (${result.status} branch ${result.branch})`
      );
    } else {
      view.renderError(`  Error: could not create worktree for ${spec.repo}`);
      view.renderError(
        `  (branch '${spec.branch}' may already be checked out elsewhere)`
      );
      process.exit(1);
    }
  }

  const repos = repoSpecs.map((s) => s.repo);
  const serveCmd = model.buildServeCmd(name, wsRoot, repos);
  model.tmuxCreateSession(name, wsRoot, serveCmd);

  const base = `https://${name}.local.app.hubspotqa.com`;
  const repoUrls = repos.map((repo) => ({
    repo,
    url: model.appUrl(repo, base),
  }));
  view.renderWorkspaceReady(name, repoUrls);
  model.tmuxAttachOrSwitch(name);
}

function applyUpdates(name, wsRoot, toAdd, toSwitch) {
  for (const spec of toAdd) {
    const repoDir = path.join(model.SRC, spec.repo);
    const wtPath = path.join(wsRoot, spec.repo);
    const result = model.createWorktree(repoDir, wtPath, spec.branch);
    if (result) {
      console.log(
        `  Added: ${spec.repo} (${result.status} branch ${result.branch})`
      );
    } else {
      view.renderError(`  Error: could not create worktree for ${spec.repo}`);
      view.renderError(
        `  (branch '${spec.branch}' may already be checked out elsewhere)`
      );
      process.exit(1);
    }
  }

  for (const spec of toSwitch) {
    const wtPath = path.join(wsRoot, spec.repo);
    const result = model.switchBranch(wtPath, spec.branch);
    if (result.success) {
      console.log(`  Switched: ${spec.repo} → ${spec.branch}`);
    } else {
      view.renderError(`  Error switching ${spec.repo}: ${result.detail}`);
    }
  }

  if (toAdd.length > 0 || toSwitch.length > 0) {
    model.restartServe(name, wsRoot);
    console.log(`\nUpdated workspace '${name}'.`);
  }

  ensureTmuxAndAttach(name, wsRoot);
}

function cmdUp(args) {
  const name = args[0];
  const wsRoot = name ? path.join(model.WS_DIR, name) : null;
  const isUpdate = wsRoot && fs.existsSync(wsRoot);

  if (!isUpdate && args.length < 2) {
    view.renderError("Usage: ws up <name> <repo[:branch]...>");
    process.exit(1);
  }

  if (isUpdate && args.length < 2) {
    console.log(`Workspace '${name}' is up to date.`);
    ensureTmuxAndAttach(name, wsRoot);
    return;
  }

  const defaultBranch = `${model.BRANCH_PREFIX}/${name}`;
  const repoSpecs = parseRepoArgs(args.slice(1), defaultBranch);

  validateReposExist(repoSpecs);

  if (!isUpdate) {
    createWorkspace(name, wsRoot, repoSpecs);
    return;
  }

  // --- Update mode ---
  const existingRepos = model.getRepos(wsRoot);
  const toAdd = [];
  const toSwitch = [];

  for (const spec of repoSpecs) {
    if (!existingRepos.includes(spec.repo)) {
      toAdd.push(spec);
    } else {
      const wtPath = path.join(wsRoot, spec.repo);
      const currentBranch = model.getCurrentBranch(wtPath);
      if (currentBranch !== spec.branch) {
        toSwitch.push({ ...spec, currentBranch });
      }
    }
  }

  if (toAdd.length === 0 && toSwitch.length === 0) {
    console.log(`Workspace '${name}' is up to date.`);
    ensureTmuxAndAttach(name, wsRoot);
    return;
  }

  if (toSwitch.length === 0) {
    applyUpdates(name, wsRoot, toAdd, []);
    return;
  }

  console.log("Branch changes:");
  for (const spec of toSwitch) {
    console.log(`  ${spec.repo}: ${spec.currentBranch} → ${spec.branch}`);
  }

  const readline = require("readline");
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  rl.question("Switch branches? [y/N] ", (answer) => {
    rl.close();
    const confirmed = answer.trim().toLowerCase() === "y";
    applyUpdates(name, wsRoot, toAdd, confirmed ? toSwitch : []);
  });
}

// ---------------------------------------------------------------------------
// rm
// ---------------------------------------------------------------------------

function cmdRm(args) {
  if (args.length < 2) {
    view.renderError("Usage: ws rm <name> <repo...>");
    process.exit(1);
  }

  const name = args[0];
  const repos = args.slice(1);
  const wsRoot = path.join(model.WS_DIR, name);

  if (!fs.existsSync(wsRoot)) {
    view.renderError(`No workspace named '${name}'`);
    process.exit(1);
  }

  const removed = [];
  for (const repo of repos) {
    const wtPath = path.join(wsRoot, repo);
    if (!fs.existsSync(wtPath)) {
      console.log(`  Not found: ${repo} (not in workspace)`);
      continue;
    }
    const gitFile = path.join(wtPath, ".git");
    if (!fs.existsSync(gitFile) || fs.statSync(gitFile).isDirectory()) {
      console.log(`  Skipped: ${repo} (not a worktree)`);
      continue;
    }
    const result = model.removeWorktree(wtPath);
    if (result.status === "removed") {
      console.log(`  Removed: ${repo}`);
      removed.push(repo);
    } else {
      console.log(`  Error: ${result.detail} for ${repo}`);
    }
  }

  if (removed.length === 0) {
    console.log("No repos removed.");
    return;
  }

  model.restartServe(name, wsRoot);

  console.log("");
  console.log(`Removed from '${name}': ${removed.join(", ")}`);
}

// ---------------------------------------------------------------------------
// completions
// ---------------------------------------------------------------------------

function cmdCompletions(args) {
  const subcommand = args[0];
  const rest = args.slice(1);

  const SUBCOMMANDS = [
    "up\tCreate or update a workspace",
    "down\tTear down a workspace",
    "nuke\tNuke a workspace (delete everything)",
    "rm\tRemove repos from a workspace",
    "ls\tList all workspaces",
    "attach\tAttach to a workspace tmux session",
    "info\tShow workspace details",
    "help\tShow help",
  ];

  if (!subcommand) {
    SUBCOMMANDS.forEach((s) => console.log(s));
    return;
  }

  const workspaces = model.allWorkspaces();
  const srcRepos = model.getSrcRepos();

  switch (subcommand) {
    case "up":
      if (rest.length === 0) {
        workspaces.forEach((w) => console.log(w));
      } else {
        srcRepos.forEach((r) => console.log(r));
      }
      break;
    case "down":
    case "nuke":
    case "attach":
    case "info":
      workspaces.forEach((w) => console.log(w));
      break;
    case "rm": {
      if (rest.length === 0) {
        workspaces.forEach((w) => console.log(w));
      } else {
        const wsName = rest[0];
        const wsPath = path.join(model.WS_DIR, wsName);
        model.getRepos(wsPath).forEach((r) => console.log(r));
      }
      break;
    }
  }
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

module.exports = {
  help: cmdHelp,
  ls: cmdLs,
  info: cmdInfo,
  attach: cmdAttach,
  down: cmdDown,
  nuke: cmdNuke,
  up: cmdUp,
  rm: cmdRm,
  completions: cmdCompletions,
};
