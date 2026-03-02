const express = require('express');
const { requirePermission } = require('../middleware');
const { listUsers, assignRole, getUserRoleName, writeAuditLog, getAuditLog, getRolePermissionMatrix, setRolePermissions } = require('../rbac');

const router = express.Router();

// UUID v4 regex for input validation
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Also accept guest:uuid format
const USER_ID_RE = /^(guest:)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// GET /auth/users - list all users with roles (admin only)
router.get('/', requirePermission('users.list'), async (req, res) => {
  try {
    const users = await listUsers();
    res.json({ users });
  } catch (err) {
    console.error('[users] listUsers error:', err.message);
    res.status(500).json({ error: 'Failed to list users' });
  }
});

// POST /auth/users/:id/role - assign role (admin only)
router.post('/:id/role', requirePermission('users.manage'), async (req, res) => {
  try {
    // Validate user ID format
    if (!USER_ID_RE.test(req.params.id)) {
      return res.status(400).json({ error: 'Invalid user ID format' });
    }

    // Validate Content-Type
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'Content-Type must be application/json' });
    }

    const { role } = req.body || {};
    if (!role) return res.status(400).json({ error: 'role is required' });

    const allowedRoles = ['guest', 'user', 'admin'];
    if (!allowedRoles.includes(role)) {
      return res.status(400).json({ error: `Invalid role. Allowed: ${allowedRoles.join(', ')}` });
    }

    // Prevent self-demotion from superadmin
    if (req.params.id === req.user.id && req.user.role === 'superadmin') {
      return res.status(400).json({ error: 'Cannot change own superadmin role' });
    }

    // Prevent demoting a superadmin (only other superadmins can do this)
    const targetRole = await getUserRoleName(req.params.id);
    if (targetRole === 'superadmin' && req.user.role !== 'superadmin') {
      return res.status(403).json({ error: 'Only superadmins can change a superadmin\'s role' });
    }

    await assignRole(req.params.id, role, req.user.id);
    await writeAuditLog(
      req.user.id,
      'users.role.assign',
      `user:${req.params.id}`,
      { newRole: role, previousRole: targetRole },
      req.ip
    ).catch((err) => console.error('[users] Audit log write failed:', err.message));

    res.json({ success: true, userId: req.params.id, role });
  } catch (err) {
    console.error('[users] assignRole error:', err.message);
    res.status(500).json({ error: 'Failed to assign role' });
  }
});

// GET /auth/audit - audit log (admin only)
router.get('/audit', requirePermission('audit.read'), async (req, res) => {
  try {
    const limit = parseInt(req.query.limit || '100', 10);
    const offset = parseInt(req.query.offset || '0', 10);

    // Bounds are clamped inside getAuditLog, but reject obvious junk here
    if (isNaN(limit) || isNaN(offset)) {
      return res.status(400).json({ error: 'limit and offset must be numbers' });
    }

    const logs = await getAuditLog(limit, offset);
    res.json({ logs });
  } catch (err) {
    console.error('[users] getAuditLog error:', err.message);
    res.status(500).json({ error: 'Failed to retrieve audit log' });
  }
});

// GET /auth/users/roles/permissions - role-permission matrix (admin only)
router.get('/roles/permissions', requirePermission('users.list'), async (req, res) => {
  try {
    const matrix = await getRolePermissionMatrix();
    res.json(matrix);
  } catch (err) {
    console.error('[users] getRolePermissionMatrix error:', err.message);
    res.status(500).json({ error: 'Failed to retrieve role permissions' });
  }
});

// PUT /auth/users/roles/:role/permissions - update role permissions (admin only)
router.put('/roles/:role/permissions', requirePermission('users.manage'), async (req, res) => {
  try {
    // Validate Content-Type
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'Content-Type must be application/json' });
    }

    const { role } = req.params;
    const { permissions } = req.body || {};

    if (!permissions || !Array.isArray(permissions)) {
      return res.status(400).json({ error: 'permissions array is required' });
    }

    // Cap permissions array size to prevent DoS
    if (permissions.length > 100) {
      return res.status(400).json({ error: 'Too many permissions (max 100)' });
    }

    // Validate all entries are strings
    if (!permissions.every(p => typeof p === 'string' && p.length > 0 && p.length < 100)) {
      return res.status(400).json({ error: 'Each permission must be a non-empty string' });
    }

    // Prevent modifying superadmin permissions directly
    if (role === 'superadmin') {
      return res.status(400).json({ error: 'superadmin inherits all permissions and cannot be modified directly' });
    }

    const allowedRoles = ['guest', 'user', 'admin'];
    if (!allowedRoles.includes(role)) {
      return res.status(400).json({ error: `Invalid role. Allowed: ${allowedRoles.join(', ')}` });
    }

    await setRolePermissions(role, permissions);
    await writeAuditLog(
      req.user.id,
      'permissions.updated',
      `role:${role}`,
      { permissions, count: permissions.length },
      req.ip
    ).catch((err) => console.error('[users] Audit log write failed:', err.message));

    res.json({ success: true, role, permissions });
  } catch (err) {
    console.error('[users] setRolePermissions error:', err.message);
    res.status(500).json({ error: 'Failed to update role permissions' });
  }
});

module.exports = router;
