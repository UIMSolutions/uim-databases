// Verhalten der Admin-Seiten; alles funktioniert über data-Attribute der Diet-Templates.
(function () {
  const rowForm = document.getElementById('row-form');

  function setNull(index, isNull) {
    const field = rowForm.querySelector(`[data-field="${index}"]`);
    const box = rowForm.querySelector(`[data-null="${index}"]`);
    box.checked = isNull;
    field.disabled = isNull;
  }

  // Einfügen (values fehlt) und Bearbeiten teilen sich denselben Dialog.
  function openRowDialog(values, matchJson) {
    const editing = values !== null;
    rowForm.action = editing ? rowForm.dataset.update : rowForm.dataset.insert;
    document.getElementById('row-match').value = matchJson || '';
    document.getElementById('row-title').textContent = editing ? 'Edit row' : 'Add row';
    document.getElementById('row-duplicate-note').classList.toggle('hidden', !editing);
    rowForm.querySelectorAll('[data-field]').forEach((field) => {
      const index = Number(field.dataset.field);
      const value = editing ? values[index] : '';
      field.value = value === null ? '' : value;
      setNull(index, value === null);
    });
    document.getElementById('row_modal').showModal();
  }

  document.addEventListener('click', (event) => {
    const target = event.target.closest('button');
    if (!target) return;
    if (target.dataset.resetUser) {
      const name = target.dataset.resetUser;
      document.getElementById('reset-form').action = `/admin/users/${encodeURIComponent(name)}/password`;
      document.getElementById('reset-title').textContent = `Reset password for ${name}`;
      document.getElementById('reset_modal').showModal();
    }
    // Rollen: Anlegen und Bearbeiten teilen sich einen Dialog; der Name einer bestehenden Rolle bleibt fest
    if (target.dataset.roleNew !== undefined || target.dataset.roleEdit) {
      const editing = Boolean(target.dataset.roleEdit);
      const granted = editing ? target.dataset.rolePermissions.split(' ') : [];
      const name = document.getElementById('role-name');
      name.value = editing ? target.dataset.roleEdit : '';
      name.readOnly = editing;
      document.getElementById('role-description').value = editing ? target.dataset.roleDescription : '';
      document.getElementById('role-title').textContent = editing ? `Edit role ${target.dataset.roleEdit}` : 'New role';
      document.querySelectorAll('#role-form [data-permission]').forEach((box) => {
        box.checked = granted.includes(box.dataset.permission);
      });
      document.getElementById('role_modal').showModal();
    }
    if (target.dataset.rowInsert) openRowDialog(null, '');
    if (target.dataset.rowEdit) {
      const json = target.closest('tr').dataset.values;
      openRowDialog(JSON.parse(json), json);
    }
    if (target.dataset.addColumn) {
      const list = document.getElementById('column-list');
      const row = list.querySelector('[data-column-row]').cloneNode(true);
      row.querySelector('input').value = '';
      list.appendChild(row);
      row.querySelector('input').focus();
    }
    if (target.dataset.removeColumn) {
      const list = document.getElementById('column-list');
      if (list.children.length > 1) target.closest('[data-column-row]').remove();
    }
  });

  document.addEventListener('change', (event) => {
    const { target } = event;
    if (target.dataset.null !== undefined) setNull(target.dataset.null, target.checked);
    if (target.dataset.autosubmit) target.form.submit();
  });

  document.addEventListener('submit', (event) => {
    const form = event.target;
    if (form.dataset.confirm && !window.confirm(form.dataset.confirm)) event.preventDefault();
    if (form.dataset.confirmName) {
      const name = form.dataset.confirmName;
      const what = form.dataset.confirmWhat || 'the table';
      if (window.prompt(`This permanently removes ${what}. Type "${name}" to confirm.`) !== name) {
        event.preventDefault();
      }
    }
  });

  const sqlInput = document.getElementById('sql-input');
  if (sqlInput) {
    sqlInput.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
        event.preventDefault();
        sqlInput.form.requestSubmit();
      }
    });
  }

  lucide.createIcons();
})();
