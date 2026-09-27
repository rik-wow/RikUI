export const clientScript = `document.documentElement.classList.add("enhanced");
const controls = [...document.querySelectorAll('[data-view][aria-pressed]')];
const stage = document.querySelector('.preview-stage');
const scene = document.querySelector('.game-scene');
const views = { combat: '700 650 590 500', layout: '0 0 2048 1152', quests: '1730 0 330 625' };
function activate(button) {
  const view = button.dataset.view;
  stage.dataset.view = view;
  scene.setAttribute('viewBox', views[view]);
  for (const control of controls) {
    control.setAttribute('aria-pressed', String(control === button));
    document.getElementById('copy-' + control.dataset.view).hidden = control !== button;
  }
}
for (const button of controls) {
  button.addEventListener('click', () => activate(button));
  button.addEventListener('keydown', event => {
    const index = controls.indexOf(button);
    const next = { ArrowRight: (index + 1) % controls.length,
      ArrowLeft: (index + controls.length - 1) % controls.length,
      Home: 0, End: controls.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    controls[next].focus();
    activate(controls[next]);
  });
}
`;
