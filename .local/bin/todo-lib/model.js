function formatTask(task) {
  return {
    id: task.id,
    content: task.content,
    description: task.description || "",
    priority: task.priority,
    projectId: task.project_id,
    due: task.due ? task.due.date : null,
    dueString: task.due ? task.due.string : null,
    completed: task.is_completed || task.checked || false,
    completedAt: task.completed_at ? task.completed_at.slice(0, 10) : null,
    order: task.order,
    url: task.url,
  };
}

function formatProject(project) {
  return {
    id: project.id,
    name: project.name,
    color: project.color,
    order: project.child_order,
    isFavorite: project.is_favorite,
  };
}

function sortTasks(tasks) {
  return tasks.slice().sort((a, b) => {
    if (b.priority !== a.priority) return b.priority - a.priority;
    if (a.due && b.due) return a.due.localeCompare(b.due);
    if (a.due) return -1;
    if (b.due) return 1;
    return a.order - b.order;
  });
}

function groupTasksByProject(tasks, projects) {
  const projectMap = {};
  for (const p of projects) {
    projectMap[p.id] = p.name;
  }

  const groups = {};
  for (const task of tasks) {
    const name = projectMap[task.projectId] || "Unknown";
    if (!groups[name]) groups[name] = [];
    groups[name].push(task);
  }
  return groups;
}

function resolveProjectId(name, projects) {
  const lower = name.toLowerCase();
  const exact = projects.find((p) => p.name.toLowerCase() === lower);
  if (exact) return exact.id;
  const partial = projects.find((p) => p.name.toLowerCase().includes(lower));
  return partial ? partial.id : null;
}

function userToApiPriority(p) {
  const n = parseInt(p, 10);
  if (n >= 1 && n <= 4) return 5 - n;
  return 1;
}

function buildTaskBody(flags) {
  const body = {};
  if (flags.content) body.content = flags.content;
  if (flags.description) body.description = flags.description;
  if (flags.priority) body.priority = userToApiPriority(flags.priority);
  if (flags.due) body.due_string = flags.due;
  if (flags.projectId) body.project_id = flags.projectId;
  return body;
}

module.exports = {
  formatTask,
  formatProject,
  sortTasks,
  groupTasksByProject,
  resolveProjectId,
  buildTaskBody,
};
