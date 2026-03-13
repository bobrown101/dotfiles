const api = require("./api");
const model = require("./model");
const view = require("./view");

async function list(flags) {
  const params = {};
  let cachedProjects;

  if (flags.project) {
    cachedProjects = await api.listProjects();
    const id = model.resolveProjectId(
      flags.project,
      cachedProjects.map(model.formatProject)
    );
    if (!id) {
      view.printError(`Project not found: ${flags.project}`);
      process.exit(1);
    }
    params.project_id = id;
  }

  if (flags.filter) {
    params.filter = flags.filter;
  }

  const completedParams = { limit: 5 };
  if (params.project_id) completedParams.project_id = params.project_id;

  const fetches = [
    api.listTasks(Object.keys(params).length ? params : null),
    api.listCompletedTasks(completedParams),
  ];
  if (!cachedProjects) fetches.push(api.listProjects());

  const results = await Promise.all(fetches);
  const rawTasks = results[0];
  const rawCompleted = results[1];
  const rawProjects = cachedProjects || results[2];

  const tasks = model.sortTasks(rawTasks.map(model.formatTask));
  const completed = rawCompleted.map(model.formatTask);
  const projects = rawProjects.map(model.formatProject);

  if (params.project_id) {
    const rawSections = await api.listSections({ project_id: params.project_id });
    const sections = rawSections.map(model.formatSection);
    if (sections.length > 0) {
      const projectName = projects.find((p) => p.id === params.project_id)?.name;
      const groups = model.groupTasksBySection(tasks, sections);
      view.printTasksGroupedBySection(groups, projectName);
      if (completed.length > 0) view.printTasks({}, completed);
      return;
    }
  }

  const grouped = model.groupTasksByProject(tasks, projects);
  view.printTasks(grouped, completed);
}

async function add(flags) {
  if (!flags.content) {
    view.printError("Usage: todo add \"task\" [--project NAME] [--priority 1-4] [--due DATE]");
    process.exit(1);
  }

  if (flags.project) {
    const projects = await api.listProjects();
    const id = model.resolveProjectId(
      flags.project,
      projects.map(model.formatProject)
    );
    if (!id) {
      view.printError(`Project not found: ${flags.project}`);
      process.exit(1);
    }
    flags.projectId = id;

    if (flags.section) {
      const rawSections = await api.listSections({ project_id: id });
      const sections = rawSections.map(model.formatSection);
      const sectionId = model.resolveSectionId(flags.section, sections);
      if (!sectionId) {
        view.printError(`Section not found: ${flags.section}`);
        process.exit(1);
      }
      flags.sectionId = sectionId;
    }
  }

  const body = model.buildTaskBody(flags);
  const task = await api.createTask(body);
  view.printSuccess(`Created: ${task.content} (${task.id})`);
}

async function done(args) {
  if (args.length === 0) {
    view.printError("Usage: todo done <id> [id2 ...]");
    process.exit(1);
  }
  for (const id of args) {
    const task = await api.getTask(id);
    await api.closeTask(id);
    view.printSuccess(`Completed: ${task.content} (${id})`);
  }
}

async function del(args) {
  if (args.length === 0) {
    view.printError("Usage: todo delete <id> [id2 ...]");
    process.exit(1);
  }
  for (const id of args) {
    const task = await api.getTask(id);
    await api.deleteTask(id);
    view.printSuccess(`Deleted: ${task.content} (${id})`);
  }
}

async function edit(args, flags) {
  const id = args[0];
  if (!id) {
    view.printError("Usage: todo edit <id> [--content TEXT] [--priority 1-4] [--due DATE]");
    process.exit(1);
  }

  const body = model.buildTaskBody(flags);

  if (Object.keys(body).length === 0) {
    view.printError("Nothing to update. Use --content, --priority, --due, or --description.");
    process.exit(1);
  }

  const task = await api.updateTask(id, body);
  view.printSuccess(`Updated: ${task.content} (${task.id})`);
}

async function projects() {
  const rawProjects = await api.listProjects();
  const formatted = rawProjects.map(model.formatProject);
  formatted.sort((a, b) => a.order - b.order);
  view.printProjects(formatted);
}

async function board(flags) {
  if (!flags.project) {
    view.printError("Usage: todo board --project NAME");
    process.exit(1);
  }

  const rawProjects = await api.listProjects();
  const projects = rawProjects.map(model.formatProject);
  const projectId = model.resolveProjectId(flags.project, projects);
  if (!projectId) {
    view.printError(`Project not found: ${flags.project}`);
    process.exit(1);
  }

  const [rawTasks, rawSections] = await Promise.all([
    api.listTasks({ project_id: projectId }),
    api.listSections({ project_id: projectId }),
  ]);

  const tasks = model.sortTasks(rawTasks.map(model.formatTask));
  const sections = rawSections.map(model.formatSection);

  if (sections.length === 0) {
    view.printError("No sections in this project. Create some with: todo sections add <name> --project NAME");
    process.exit(1);
  }

  const groups = model.groupTasksBySection(tasks, sections);
  const termWidth = process.stdout.columns || 80;
  view.printBoard(groups, termWidth);
}

async function move(args, flags) {
  const id = args[0];
  const sectionName = args.slice(1).join(" ") || flags.section;
  if (!id || !sectionName) {
    view.printError('Usage: todo move <id> <section-name>  (use "none" to unsection)');
    process.exit(1);
  }

  const task = await api.getTask(id);

  if (sectionName.toLowerCase() === "none") {
    await api.moveTask(id, { project_id: task.project_id });
    view.printSuccess(`Moved "${task.content}" to no section`);
    return;
  }

  const rawSections = await api.listSections({ project_id: task.project_id });
  const sections = rawSections.map(model.formatSection);
  const sectionId = model.resolveSectionId(sectionName, sections);
  if (!sectionId) {
    view.printError(`Section not found: ${sectionName}`);
    process.exit(1);
  }

  await api.moveTask(id, { section_id: sectionId });
  const section = sections.find((s) => s.id === sectionId);
  view.printSuccess(`Moved "${task.content}" → ${section.name}`);
}

async function sections(args, flags) {
  const action = args[0] || "list";

  if (action === "list") {
    if (!flags.project) {
      view.printError("Usage: todo sections list --project NAME");
      process.exit(1);
    }
    const rawProjects = await api.listProjects();
    const projects = rawProjects.map(model.formatProject);
    const projectId = model.resolveProjectId(flags.project, projects);
    if (!projectId) {
      view.printError(`Project not found: ${flags.project}`);
      process.exit(1);
    }
    const rawSections = await api.listSections({ project_id: projectId });
    const formatted = rawSections.map(model.formatSection);
    formatted.sort((a, b) => a.order - b.order);
    const projectName = projects.find((p) => p.id === projectId)?.name;
    view.printSections(formatted, projectName);
    return;
  }

  if (action === "add") {
    const name = args[1];
    if (!name || !flags.project) {
      view.printError("Usage: todo sections add <name> --project NAME");
      process.exit(1);
    }
    const rawProjects = await api.listProjects();
    const projects = rawProjects.map(model.formatProject);
    const projectId = model.resolveProjectId(flags.project, projects);
    if (!projectId) {
      view.printError(`Project not found: ${flags.project}`);
      process.exit(1);
    }
    const section = await api.createSection({ name, project_id: projectId });
    view.printSuccess(`Created section: ${section.name} (${section.id})`);
    return;
  }

  if (action === "rename") {
    const id = args[1];
    if (!id || !flags.name) {
      view.printError("Usage: todo sections rename <id> --name NAME");
      process.exit(1);
    }
    const section = await api.updateSection(id, { name: flags.name });
    view.printSuccess(`Renamed section: ${section.name} (${section.id})`);
    return;
  }

  if (action === "delete") {
    const id = args[1];
    if (!id) {
      view.printError("Usage: todo sections delete <id>");
      process.exit(1);
    }
    await api.deleteSection(id);
    view.printSuccess(`Deleted section ${id}`);
    return;
  }

  view.printError(`Unknown sections action: ${action}`);
  process.exit(1);
}

module.exports = { list, add, done, del, edit, projects, board, move, sections };
