const { pool } = require('./db');

function log(level, message, meta = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    service: 'auth-service',
    message,
    ...meta,
  };
  if (level === 'error') {
    console.error(JSON.stringify(entry));
  } else {
    console.log(JSON.stringify(entry));
  }
}

async function getEffectivePermissions(userId) {
  const result = await pool.query(
    'SELECT action FROM rbac.effective_permissions($1)',
    [userId]
  );
  return result.rows.map(r => r.action);
}

async function hasPermission(userId, action) {
  const result = await pool.query(
    'SELECT rbac.has_permission($1, $2) AS allowed',
    [userId, action]
  );
  return result.rows[0]?.allowed === true;
}

async function getUserRoleName(userId) {
  const result = await pool.query(
    'SELECT rbac.user_role_name($1) AS role_name',
    [userId]
  );
  return result.rows[0]?.role_name || null;
}

// Fixed: wrap DELETE+INSERT in a transaction to prevent users from being left with zero roles
async function assignRole(userId, roleName, grantedBy) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const roleResult = await client.query(
      'SELECT id FROM rbac.roles WHERE name = $1',
      [roleName]
    );
    if (roleResult.rows.length === 0) {
      await client.query('ROLLBACK');
      throw new Error(`Role not found: ${roleName}`);
    }

    await client.query('DELETE FROM rbac.user_roles WHERE user_id = $1', [userId]);
    await client.query(
      'INSERT INTO rbac.user_roles (user_id, role_id, granted_by) VALUES ($1, $2, $3)',
      [userId, roleResult.rows[0].id, grantedBy]
    );

    await client.query('COMMIT');

    log('info', 'RBAC: role assigned', { userId, role: roleName, grantedBy, action: 'role.assigned' });

    // Audit log is best-effort -- don't let failures crash the flow
    writeAuditLog(grantedBy || userId, 'role.assigned', `user:${userId}`, { role: roleName }, null)
      .catch((err) => log('error', 'Audit log write failed', { error: err.message }));
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

async function ensureUserRole(userId, defaultRole = 'user') {
  const existing = await getUserRoleName(userId);
  if (!existing) {
    await assignRole(userId, defaultRole, null);
    return defaultRole;
  }
  return existing;
}

async function listUsers() {
  const result = await pool.query(`
    SELECT
      ur.user_id,
      r.name AS role_name,
      ur.granted_at
    FROM rbac.user_roles ur
    JOIN rbac.roles r ON r.id = ur.role_id
    ORDER BY ur.granted_at DESC
  `);
  return result.rows;
}

async function writeAuditLog(userId, action, resource, metadata, ip) {
  await pool.query(
    'INSERT INTO rbac.audit_log (user_id, action, resource, metadata, ip) VALUES ($1, $2, $3, $4, $5)',
    [userId, action, resource, metadata ? JSON.stringify(metadata) : '{}', ip]
  );
}

async function getAuditLog(limit = 100, offset = 0) {
  // Clamp limit/offset to prevent DoS via huge result sets
  const safeLimit = Math.max(1, Math.min(parseInt(limit, 10) || 100, 1000));
  const safeOffset = Math.max(0, parseInt(offset, 10) || 0);

  const result = await pool.query(
    'SELECT * FROM rbac.audit_log ORDER BY created_at DESC LIMIT $1 OFFSET $2',
    [safeLimit, safeOffset]
  );
  return result.rows;
}

async function findRoleIdByName(roleName) {
  const result = await pool.query(
    'SELECT id FROM rbac.roles WHERE name = $1 LIMIT 1',
    [roleName]
  );
  return result.rows[0]?.id || null;
}

async function ensureRole(userId, roleName, grantedBy = null) {
  const roleId = await findRoleIdByName(roleName);
  if (!roleId) throw new Error(`Role not found: ${roleName}`);

  const result = await pool.query(
    `INSERT INTO rbac.user_roles (user_id, role_id, granted_by)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id, role_id) DO NOTHING
     RETURNING user_id`,
    [userId, roleId, grantedBy]
  );

  if (result.rows.length > 0) {
    log('info', 'RBAC: role ensured', { userId, role: roleName, grantedBy, action: 'role.ensured' });
    writeAuditLog(grantedBy || userId, 'role.ensured', `user:${userId}`, { role: roleName }, null)
      .catch((err) => log('error', 'Audit log write failed', { error: err.message }));
  }
}

/**
 * Get the full role-permission matrix from the database.
 * Returns: { roles: [{name, permissions: [action]}], allPermissions: [action] }
 */
async function getRolePermissionMatrix() {
  const rolesResult = await pool.query(
    'SELECT id, name FROM rbac.roles ORDER BY CASE name WHEN \'superadmin\' THEN 0 WHEN \'admin\' THEN 1 WHEN \'user\' THEN 2 WHEN \'guest\' THEN 3 ELSE 4 END'
  );
  const permsResult = await pool.query(
    'SELECT id, action, description FROM rbac.permissions ORDER BY action'
  );
  const mappingResult = await pool.query(
    'SELECT r.name AS role_name, p.action FROM rbac.role_permissions rp JOIN rbac.roles r ON r.id = rp.role_id JOIN rbac.permissions p ON p.id = rp.permission_id'
  );

  const mappingByRole = {};
  for (const row of mappingResult.rows) {
    if (!mappingByRole[row.role_name]) mappingByRole[row.role_name] = [];
    mappingByRole[row.role_name].push(row.action);
  }

  return {
    roles: rolesResult.rows.map(r => ({
      name: r.name,
      permissions: mappingByRole[r.name] || [],
    })),
    allPermissions: permsResult.rows.map(p => ({ action: p.action, description: p.description })),
  };
}

/**
 * Set the direct permissions for a role. Replaces all existing role_permissions for that role.
 * Does NOT affect inherited permissions (those come from the recursive CTE).
 * @param {string} roleName
 * @param {string[]} permissionActions - list of permission action strings to assign
 */
async function setRolePermissions(roleName, permissionActions) {
  const roleId = await findRoleIdByName(roleName);
  if (!roleId) throw new Error(`Role not found: ${roleName}`);

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Delete all existing direct permissions for this role
    await client.query('DELETE FROM rbac.role_permissions WHERE role_id = $1', [roleId]);

    // Insert new permissions
    if (permissionActions.length > 0) {
      const permResult = await client.query(
        'SELECT id, action FROM rbac.permissions WHERE action = ANY($1)',
        [permissionActions]
      );

      // Warn if some permissions were not found
      const found = permResult.rows.map(p => p.action);
      const missing = permissionActions.filter(a => !found.includes(a));
      if (missing.length > 0) {
        log('warn', 'Some permissions not found in DB', { missing, action: 'permissions.partial' });
      }

      for (const perm of permResult.rows) {
        await client.query(
          'INSERT INTO rbac.role_permissions (role_id, permission_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
          [roleId, perm.id]
        );
      }
    }

    await client.query('COMMIT');
    log('info', 'RBAC: role permissions updated', { role: roleName, count: permissionActions.length, action: 'permissions.updated' });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

module.exports = {
  getEffectivePermissions,
  hasPermission,
  getUserRoleName,
  assignRole,
  ensureRole,
  ensureUserRole,
  listUsers,
  writeAuditLog,
  getAuditLog,
  getRolePermissionMatrix,
  setRolePermissions,
};
