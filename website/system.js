const chinese = document.documentElement.lang.startsWith('zh');
const copy = chinese ? {
  view: '允许阅读会话与查看文件，不允许发送提示。',
  control: '允许阅读会话、发送提示、停止工作和答复受支持的审批。',
  preparing: '正在准备…',
  busy: '忙碌示意：保留操作含义并阻止重复提交。',
  start: '开始配对 ↗',
  complete: '示意已完成。没有建立配对窗口或连接真实设备。',
  idle: '点击按钮可查看忙碌与完成状态；不会连接真实设备。',
} : {
  view: 'Read conversations and files. Sending prompts is not allowed.',
  control: 'Read conversations, send prompts, stop work, and respond to supported approvals.',
  preparing: 'Preparing…',
  busy: 'Busy preview: keep the action clear and prevent duplicate submissions.',
  start: 'Start pairing ↗',
  complete: 'Demo complete. No pairing window was opened and no real device was connected.',
  idle: 'Click to preview busy and completed states. No real device is connected.',
};
const themeButtons = [...document.querySelectorAll('[data-theme-choice]')];
function updateTokenLabels() {
  const style = getComputedStyle(document.documentElement);
  document.querySelectorAll('[data-color]').forEach(label => {
    label.textContent = style.getPropertyValue('--' + label.dataset.color).trim();
  });
}
themeButtons.forEach(button => button.addEventListener('click', () => {
  document.documentElement.dataset.theme = button.dataset.themeChoice;
  themeButtons.forEach(other => other.setAttribute('aria-pressed', String(other === button)));
  updateTokenLabels();
}));
updateTokenLabels();
document.querySelectorAll('[data-system-permission]').forEach(button => button.addEventListener('click', () => {
  document.querySelectorAll('[data-system-permission]').forEach(other => other.setAttribute('aria-pressed', String(other === button)));
  document.getElementById('system-permission-text').textContent = copy[button.dataset.systemPermission];
}));
const action = document.getElementById('sample-action');
const status = document.getElementById('action-status');
let busyTimer;
action.addEventListener('click', () => {
  action.disabled = true;
  action.setAttribute('aria-busy', 'true');
  action.textContent = copy.preparing;
  status.textContent = copy.busy;
  busyTimer = setTimeout(() => {
    action.disabled = false;
    action.removeAttribute('aria-busy');
    action.textContent = copy.start;
    status.textContent = copy.complete;
  }, 1100);
});
document.getElementById('reset-action').addEventListener('click', () => {
  clearTimeout(busyTimer);
  action.disabled = false;
  action.removeAttribute('aria-busy');
  action.textContent = copy.start;
  status.textContent = copy.idle;
});
