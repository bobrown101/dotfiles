#!/usr/bin/env node

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const os = require("os");

const WS = path.join(__dirname, "ws");
const HOME = os.homedir();
const SRC = path.join(HOME, "src");
const WS_DIR = path.join(HOME, "src", "workspaces");
const TEST_REPO = "ws-test-fixture";
const TEST_REPO2 = "ws-test-fixture-2";
const TEST_WS = "ws-test-run";

let passed = 0;
let failed = 0;
let skipped = 0;

function assert(ok, msg) {
  if (ok) {
    passed++;
    console.log(`  \x1b[32m✓\x1b[0m ${msg}`);
  } else {
    failed++;
    console.log(`  \x1b[31m✗\x1b[0m ${msg}`);
  }
}

function skip(msg) {
  skipped++;
  console.log(`  \x1b[33m⊘\x1b[0m ${msg} (skipped)`);
}

function ws(...args) {
  const result = spawnSync(process.execPath, [WS, ...args], {
    encoding: "utf8",
    stdio: "pipe",
    env: { ...process.env, NO_COLOR: "1" },
  });
  return {
    stdout: result.stdout,
    stderr: result.stderr,
    status: result.status,
    output: result.stdout + result.stderr,
  };
}

function wsWithStdin(stdinData, ...args) {
  const result = spawnSync(process.execPath, [WS, ...args], {
    encoding: "utf8",
    stdio: "pipe",
    input: stdinData,
    env: { ...process.env, NO_COLOR: "1" },
  });
  return {
    stdout: result.stdout,
    stderr: result.stderr,
    status: result.status,
    output: result.stdout + result.stderr,
  };
}

function tmuxHasSession(name) {
  return (
    spawnSync("tmux", ["has-session", "-t", name], { stdio: "pipe" })
      .status === 0
  );
}

function createTestRepo(name) {
  const repoPath = path.join(SRC, name);
  if (fs.existsSync(repoPath)) return false;
  fs.mkdirSync(repoPath, { recursive: true });
  spawnSync("git", ["init", "-b", "master"], { cwd: repoPath, stdio: "pipe" });
  spawnSync("git", ["commit", "--allow-empty", "-m", "init"], {
    cwd: repoPath,
    stdio: "pipe",
  });
  spawnSync("git", ["remote", "add", "origin", repoPath], {
    cwd: repoPath,
    stdio: "pipe",
  });
  spawnSync("git", ["fetch", "origin"], { cwd: repoPath, stdio: "pipe" });
  return true;
}

function removeTestRepo(name) {
  const repoPath = path.join(SRC, name);
  if (fs.existsSync(repoPath)) {
    fs.rmSync(repoPath, { recursive: true, force: true });
  }
}

function ensureTestWsClean() {
  if (tmuxHasSession(TEST_WS)) {
    spawnSync("tmux", ["kill-session", "-t", TEST_WS], { stdio: "pipe" });
  }
  const wsPath = path.join(WS_DIR, TEST_WS);
  if (fs.existsSync(wsPath)) {
    for (const repoName of [TEST_REPO, TEST_REPO2]) {
      const repoDir = path.join(SRC, repoName);
      if (fs.existsSync(repoDir)) {
        spawnSync(
          "git",
          ["-C", repoDir, "worktree", "remove", path.join(wsPath, repoName), "--force"],
          { stdio: "pipe" }
        );
      }
    }
    fs.rmSync(wsPath, { recursive: true, force: true });
  }
}

// ---------------------------------------------------------------------------
// Tests: basic commands (no side effects)
// ---------------------------------------------------------------------------

function testHelp() {
  console.log("\nhelp");

  const r1 = ws();
  assert(r1.status === 1, "no args exits 1");
  assert(r1.output.includes("ws - parallel multi-repo"), "no args shows help text");

  const r2 = ws("help");
  assert(r2.status === 0, "help exits 0");
  assert(r2.output.includes("ws up <name>"), "help lists commands");
  assert(r2.output.includes("ws down <name>"), "help lists down");
  assert(r2.output.includes("Examples:"), "help shows examples");
  assert(r2.output.includes("Layout:"), "help shows layout");
  assert(r2.output.includes("repo[:branch]"), "help shows repo:branch syntax");
}

function testUnknownCommand() {
  console.log("\nunknown command");

  const r = ws("bogus");
  assert(r.status === 1, "unknown command exits 1");
  assert(r.output.includes("Unknown command: bogus"), "shows unknown command name");
  assert(r.output.includes("ws - parallel multi-repo"), "shows help after error");
}

function testUsageErrors() {
  console.log("\nusage errors");

  const up = ws("up");
  assert(up.status === 1, "up with no args exits 1");
  assert(up.output.includes("Usage: ws up"), "up shows usage");

  const down = ws("down");
  assert(down.status === 1, "down with no args exits 1");
  assert(down.output.includes("Usage: ws down"), "down shows usage");

  const nuke = ws("nuke");
  assert(nuke.status === 1, "nuke with no args exits 1");
  assert(nuke.output.includes("Usage: ws nuke"), "nuke shows usage");

  const attach = ws("attach");
  assert(attach.status === 1, "attach with no args exits 1");
  assert(attach.output.includes("Usage: ws attach"), "attach shows usage");

  const info = ws("info");
  assert(info.status === 1, "info with no args exits 1");
  assert(info.output.includes("Usage: ws info"), "info shows usage");

  const rm = ws("rm");
  assert(rm.status === 1, "rm with no args exits 1");
  assert(rm.output.includes("Usage: ws rm"), "rm shows usage");
}

function testNonexistent() {
  console.log("\nnonexistent workspace");

  const info = ws("info", "ws-does-not-exist-xyz");
  assert(info.status === 1, "info exits 1");
  assert(info.output.includes("No workspace named"), "info shows error");

  const down = ws("down", "ws-does-not-exist-xyz");
  assert(down.status === 1, "down exits 1");
  assert(down.output.includes("No workspace named"), "down shows error");

  const attach = ws("attach", "ws-does-not-exist-xyz");
  assert(attach.status === 1, "attach exits 1");
  assert(attach.output.includes("No tmux session"), "attach shows error");

  const rm = ws("rm", "ws-does-not-exist-xyz", "some-repo");
  assert(rm.status === 1, "rm exits 1");
  assert(rm.output.includes("No workspace named"), "rm shows error");

  const nuke = ws("nuke", "ws-does-not-exist-xyz");
  assert(nuke.status === 1, "nuke exits 1");
  assert(nuke.output.includes("No workspace named"), "nuke shows error");
}

function testBadRepo() {
  console.log("\nnonexistent repo");

  const badWs = "ws-test-bad-repo";
  const r = ws("up", badWs, "repo-that-does-not-exist-xyz");
  assert(r.status === 1, "up exits 1 for missing repo");
  assert(r.output.includes("Error: repo not found"), "shows repo not found");

  const leftover = path.join(WS_DIR, badWs);
  if (fs.existsSync(leftover)) fs.rmSync(leftover, { recursive: true, force: true });
}

function testLs() {
  console.log("\nls");

  const r = ws("ls");
  assert(r.status === 0, "ls exits 0");

  const wsNames = fs.existsSync(WS_DIR)
    ? fs.readdirSync(WS_DIR, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name)
    : [];

  if (wsNames.length === 0) {
    assert(r.output.includes("No workspaces"), "ls shows no workspaces when empty");
  } else {
    for (const name of wsNames) {
      assert(r.output.includes(name), `ls includes workspace '${name}'`);
    }
    assert(
      r.output.includes("[running]") || r.output.includes("[stopped]"),
      "ls shows status labels"
    );
  }
}

function testInfo() {
  console.log("\ninfo (existing workspaces)");

  const wsNames = fs.existsSync(WS_DIR)
    ? fs.readdirSync(WS_DIR, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name)
    : [];

  if (wsNames.length === 0) {
    skip("no workspaces to test info against");
    return;
  }

  const name = wsNames[0];
  const r = ws("info", name);
  assert(r.status === 0, `info ${name} exits 0`);
  assert(r.output.includes(path.join(WS_DIR, name)), "shows root path");
  assert(r.output.includes(`ws down ${name}`), "shows teardown command");
}

// ---------------------------------------------------------------------------
// Tests: lifecycle (creates real worktrees + tmux session)
// ---------------------------------------------------------------------------

function testLifecycle() {
  console.log("\nlifecycle (up → info → ls → up update → rm → down)");

  const tmuxCheck = spawnSync("tmux", ["list-sessions"], { stdio: "pipe" });
  if (tmuxCheck.status !== 0 && !process.env.TMUX) {
    const startResult = spawnSync("tmux", ["new-session", "-d", "-s", "ws-test-bg"], { stdio: "pipe" });
    if (startResult.status !== 0) {
      skip("tmux server not running, cannot test lifecycle");
      return;
    }
    spawnSync("tmux", ["kill-session", "-t", "ws-test-bg"], { stdio: "pipe" });
  }

  const created1 = createTestRepo(TEST_REPO);
  const created2 = createTestRepo(TEST_REPO2);
  ensureTestWsClean();

  try {
    // -- up --
    const up = ws("up", TEST_WS, TEST_REPO);
    assert(up.status === 0, "up exits 0");
    assert(up.output.includes(`Creating workspace: ${TEST_WS}`), "up prints creation message");
    assert(up.output.includes(`Created: ${TEST_REPO}`), "up prints repo created");
    assert(up.output.includes(`Workspace '${TEST_WS}' ready`), "up prints ready");

    const wsPath = path.join(WS_DIR, TEST_WS);
    assert(fs.existsSync(wsPath), "workspace dir created");
    assert(
      fs.existsSync(path.join(wsPath, TEST_REPO, ".git")),
      "worktree .git file exists"
    );
    assert(tmuxHasSession(TEST_WS), "tmux session created");

    // -- up again with same repos (should say up to date) --
    const upAgain = ws("up", TEST_WS, TEST_REPO);
    assert(upAgain.status === 0, "up again exits 0");
    assert(upAgain.output.includes("up to date"), "up again shows up to date");

    // -- info shows per-repo branches --
    const info = ws("info", TEST_WS);
    assert(info.status === 0, "info exits 0");
    assert(info.output.includes(TEST_REPO), "info lists the repo");
    assert(info.output.includes(`brbrown/${TEST_WS}`), "info shows branch");

    // -- ls includes test workspace --
    const ls = ws("ls");
    assert(ls.output.includes(TEST_WS), "ls includes test workspace");
    assert(ls.output.includes("[running]"), "ls shows running status");

    // -- up with repo:branch syntax to add second repo --
    const upAdd = ws("up", TEST_WS, `${TEST_REPO2}:custom-test-branch`);
    assert(upAdd.status === 0, "up-add exits 0");
    assert(upAdd.output.includes(`Added: ${TEST_REPO2}`), "up-add confirms addition");
    assert(upAdd.output.includes("custom-test-branch"), "up-add shows custom branch");
    assert(
      fs.existsSync(path.join(wsPath, TEST_REPO2, ".git")),
      "second worktree created"
    );

    // -- up with branch switch (decline) --
    const upSwitchNo = wsWithStdin("n\n", "up", TEST_WS, `${TEST_REPO}:other-branch`);
    assert(upSwitchNo.status === 0, "up branch-switch decline exits 0");
    assert(upSwitchNo.output.includes("Branch changes:"), "shows branch change prompt");

    // -- up with branch switch (accept) --
    const upSwitchYes = wsWithStdin("y\n", "up", TEST_WS, `${TEST_REPO}:test-switched`);
    assert(upSwitchYes.status === 0, "up branch-switch accept exits 0");
    assert(upSwitchYes.output.includes("Switched:"), "confirms branch switch");

    // -- verify branch actually switched --
    const branchResult = spawnSync(
      "git", ["-C", path.join(wsPath, TEST_REPO), "branch", "--show-current"],
      { encoding: "utf8", stdio: "pipe" }
    );
    assert(branchResult.stdout.trim() === "test-switched", "branch was actually switched");

    // -- rm --
    const rm = ws("rm", TEST_WS, TEST_REPO);
    assert(rm.status === 0, "rm exits 0");
    assert(rm.output.includes(`Removed: ${TEST_REPO}`), "rm confirms removal");
    assert(
      !fs.existsSync(path.join(wsPath, TEST_REPO)),
      "worktree dir removed after rm"
    );

    // -- rm nonexistent repo --
    const rmMissing = ws("rm", TEST_WS, "not-there");
    assert(rmMissing.output.includes("Not found"), "rm shows not found for missing repo");

    // -- down --
    const down = ws("down", TEST_WS);
    assert(down.status === 0, "down exits 0");
    assert(down.output.includes("Killed tmux session"), "down killed tmux");
    assert(down.output.includes(`Workspace '${TEST_WS}' torn down`), "down confirms teardown");
    assert(!fs.existsSync(wsPath), "workspace dir removed");
    assert(!tmuxHasSession(TEST_WS), "tmux session gone");

    // -- verify no orphan processes --
    const psResult = spawnSync("pgrep", ["-f", path.join(WS_DIR, TEST_WS)], {
      encoding: "utf8",
      stdio: "pipe",
    });
    assert(
      psResult.status !== 0 || psResult.stdout.trim() === "",
      "no orphan processes after down"
    );
  } finally {
    ensureTestWsClean();
    if (created1) removeTestRepo(TEST_REPO);
    if (created2) removeTestRepo(TEST_REPO2);
  }
}

function testNukeLifecycle() {
  console.log("\nnuke lifecycle (up → nuke abort → nuke confirm → verify branch deleted)");

  const tmuxCheck = spawnSync("tmux", ["list-sessions"], { stdio: "pipe" });
  if (tmuxCheck.status !== 0 && !process.env.TMUX) {
    const startResult = spawnSync("tmux", ["new-session", "-d", "-s", "ws-test-bg"], { stdio: "pipe" });
    if (startResult.status !== 0) {
      skip("tmux server not running, cannot test nuke lifecycle");
      return;
    }
    spawnSync("tmux", ["kill-session", "-t", "ws-test-bg"], { stdio: "pipe" });
  }

  const created = createTestRepo(TEST_REPO);
  ensureTestWsClean();

  try {
    const up = ws("up", TEST_WS, TEST_REPO);
    assert(up.status === 0, "up exits 0");

    const wsPath = path.join(WS_DIR, TEST_WS);
    const branch = `brbrown/${TEST_WS}`;
    const repoDir = path.join(SRC, TEST_REPO);

    const branchBefore = spawnSync("git", ["-C", repoDir, "branch", "--list", branch], {
      encoding: "utf8",
      stdio: "pipe",
    });
    assert(branchBefore.stdout.trim().length > 0, "branch exists before nuke");

    const nukeAbort = wsWithStdin("n\n", "nuke", TEST_WS);
    assert(nukeAbort.status === 0, "nuke abort exits 0");
    assert(nukeAbort.output.includes("Aborted"), "nuke abort shows aborted");
    assert(fs.existsSync(wsPath), "workspace dir still exists after abort");
    assert(tmuxHasSession(TEST_WS), "tmux session still exists after abort");

    const nukeConfirm = wsWithStdin("y\n", "nuke", TEST_WS);
    assert(nukeConfirm.status === 0, "nuke confirm exits 0");
    assert(nukeConfirm.output.includes("Killed tmux session"), "nuke killed tmux");
    assert(nukeConfirm.output.includes(`Deleted branch: ${branch}`), "nuke deleted branch");
    assert(nukeConfirm.output.includes(`Workspace '${TEST_WS}' nuked`), "nuke confirms completion");
    assert(!fs.existsSync(wsPath), "workspace dir removed after nuke");
    assert(!tmuxHasSession(TEST_WS), "tmux session gone after nuke");

    const branchAfter = spawnSync("git", ["-C", repoDir, "branch", "--list", branch], {
      encoding: "utf8",
      stdio: "pipe",
    });
    assert(branchAfter.stdout.trim().length === 0, "branch deleted from parent repo");
  } finally {
    ensureTestWsClean();
    if (created) removeTestRepo(TEST_REPO);
  }
}

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------

console.log("ws tests");

testHelp();
testUnknownCommand();
testUsageErrors();
testNonexistent();
testBadRepo();
testLs();
testInfo();
testLifecycle();
testNukeLifecycle();

console.log(`\n${passed} passed, ${failed} failed, ${skipped} skipped\n`);
process.exit(failed > 0 ? 1 : 0);
