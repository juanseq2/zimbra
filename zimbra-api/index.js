require('dotenv').config();

const cors = require('cors');
const express = require('express');
const mysql = require('mysql2/promise');

const port = Number(process.env.PORT || 3000);
const frontendUrl = new URL(process.env.FRONTEND_URL || 'http://localhost:5173').origin;
const crmWebhookUrl = process.env.CRM_WEBHOOK_URL || '';
const crmWebhookToken = process.env.CRM_WEBHOOK_TOKEN || '';
const puntajeMinimoAsignacion = Number(process.env.PUNTAJE_MINIMO_ASIGNACION || 50);
const limiteProspectosVendedor = Number(process.env.LIMITE_PROSPECTOS_VENDEDOR || 30);

const databaseConfig = {
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'avnadmin',
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || 'defaultdb',
  ssl: { rejectUnauthorized: false },
};

if (
  !databaseConfig.password ||
  /^(CAMBIA|PEGA_AQUI|CHANGE_ME|YOUR_PASSWORD|tu_contraseña)/i.test(databaseConfig.password)
) {
  throw new Error('Configura DB_PASSWORD con tu contraseña de Aiven en D:\\zimbra\\zimbra-api\\.env.');
}

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('PORT debe ser un número entre 1 y 65535.');
}

if (!Number.isInteger(databaseConfig.port) || databaseConfig.port < 1 || databaseConfig.port > 65535) {
  throw new Error('DB_PORT debe ser un número entre 1 y 65535.');
}

if (!Number.isInteger(puntajeMinimoAsignacion) || puntajeMinimoAsignacion < 1 || puntajeMinimoAsignacion > 100) {
  throw new Error('PUNTAJE_MINIMO_ASIGNACION debe estar entre 1 y 100.');
}

if (!Number.isInteger(limiteProspectosVendedor) || limiteProspectosVendedor < 1) {
  throw new Error('LIMITE_PROSPECTOS_VENDEDOR debe ser un entero positivo.');
}

if (crmWebhookUrl) {
  const webhook = new URL(crmWebhookUrl);
  if (webhook.protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(webhook.hostname)) {
    throw new Error('CRM_WEBHOOK_URL debe usar HTTPS.');
  }
}

const pool = mysql.createPool({
  ...databaseConfig,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

const appMiddleware = express();
appMiddleware.disable('x-powered-by');
appMiddleware.use(cors({ origin: frontendUrl }));
appMiddleware.use(express.json({ limit: '32kb' }));

const reportarError = (res, contexto, error, status = 500) => {
  console.error(`${contexto}:`, error);
  res.status(status).json({ error: 'Ocurrió un error en la API. Revisa la terminal para más detalles.' });
};

const idPositivo = (valor) => Number.isSafeInteger(valor) && valor > 0;
const uuidValido = (valor) =>
  typeof valor === 'string' &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(valor);
const eventosPermitidos = new Set([
  'page_view',
  'visita',
  'pagina_precio',
  'solicitud_demo',
  'descarga_prueba',
]);

const calcularPuntaje = async (connection, idCliente) => {
  const [rows] = await connection.query(
    `SELECT LEAST(100, COALESCE(SUM(
       CASE tipo_evento
         WHEN 'registro_prueba' THEN 5
         WHEN 'page_view' THEN 5
         WHEN 'visita' THEN 5
         WHEN 'pagina_precio' THEN 20
         WHEN 'solicitud_demo' THEN 25
         WHEN 'descarga_prueba' THEN 10
         WHEN 'propuesta_enviada' THEN 15
         WHEN 'propuesta_aceptada' THEN 30
         ELSE 0
       END
     ), 0)) AS puntaje
     FROM actividad_web
     WHERE id_cliente = ?`,
    [idCliente],
  );
  return Number(rows[0].puntaje);
};

const encolarEventoCrm = async (connection, tipoEvento, payload) => {
  await connection.query(
    `INSERT INTO crm_outbox (clave_idempotencia, tipo_evento, payload)
     VALUES (UUID(), ?, ?)`,
    [tipoEvento, JSON.stringify({ evento: tipoEvento, ...payload })],
  );
};

const asignarProspectoAutomaticamente = async (connection, idCliente, puntaje) => {
  if (puntaje < puntajeMinimoAsignacion) return null;

  const [clientes] = await connection.query(
    'SELECT id_usuario_asignado FROM cliente_prospecto WHERE id_cliente = ? FOR UPDATE',
    [idCliente],
  );
  if (!clientes.length) return null;
  if (clientes[0].id_usuario_asignado) {
    await connection.query(
      'UPDATE cliente_prospecto SET puntaje_interes = ? WHERE id_cliente = ?',
      [puntaje, idCliente],
    );
    return clientes[0].id_usuario_asignado;
  }

  const [vendedores] = await connection.query(
    `SELECT id_usuario
       FROM usuario_sistema
      WHERE rol = 'vendedor' AND activo = TRUE
      ORDER BY id_usuario
      FOR UPDATE`,
  );

  let mejorVendedor = null;
  for (const vendedor of vendedores) {
    const [conteo] = await connection.query(
      `SELECT COUNT(*) AS total
         FROM cliente_prospecto
        WHERE id_usuario_asignado = ?
          AND estado_prospecto IN ('nuevo', 'calificado')
          AND DATE_ADD(fecha_registro, INTERVAL duracion_prueba_dias DAY) > NOW()`,
      [vendedor.id_usuario],
    );
    const total = Number(conteo[0].total);
    if (total >= limiteProspectosVendedor) continue;
    if (!mejorVendedor || total < mejorVendedor.total) {
      mejorVendedor = { id: vendedor.id_usuario, total };
    }
  }

  if (!mejorVendedor) return null;

  await connection.query(
    `UPDATE cliente_prospecto
        SET id_usuario_asignado = ?,
            puntaje_interes = ?,
            estado_prospecto = CASE WHEN estado_prospecto = 'nuevo' THEN 'calificado' ELSE estado_prospecto END
      WHERE id_cliente = ?`,
    [mejorVendedor.id, puntaje, idCliente],
  );
  await connection.query(
    `INSERT INTO notificacion (id_usuario, id_cliente, tipo, mensaje)
     VALUES (?, ?, 'prospecto_asignado', ?)`,
    [mejorVendedor.id, idCliente, `Se te asignó el prospecto #${idCliente}.`],
  );
  await encolarEventoCrm(connection, 'prospecto.asignado', {
    id_cliente: idCliente,
    id_usuario_asignado: mejorVendedor.id,
    puntaje_interes: puntaje,
  });
  return mejorVendedor.id;
};

const ejecutarTransaccion = async (trabajo) => {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const resultado = await trabajo(connection);
    await connection.commit();
    return resultado;
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
};

appMiddleware.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', database: 'connected' });
  } catch (error) {
    reportarError(res, 'Error al comprobar la conexión con MySQL', error, 503);
  }
});

appMiddleware.get('/api/configuracion', (req, res) => {
  res.json({
    puntaje_minimo_asignacion: puntajeMinimoAsignacion,
    limite_prospectos_vendedor: limiteProspectosVendedor,
  });
});

appMiddleware.get('/api/campanias', async (req, res) => {
  try {
    const [rows] = await pool.query(
      'SELECT id_campania, nombre_campania, canal FROM campania_marketing ORDER BY nombre_campania',
    );
    res.json(rows);
  } catch (error) {
    reportarError(res, 'Error al consultar campañas', error);
  }
});

appMiddleware.get('/api/vendedores', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT u.id_usuario, u.nombre, u.email,
              COUNT(cp.id_cliente) AS prospectos_activos
         FROM usuario_sistema AS u
         LEFT JOIN cliente_prospecto AS cp
           ON cp.id_usuario_asignado = u.id_usuario
          AND cp.estado_prospecto IN ('nuevo', 'calificado')
          AND DATE_ADD(cp.fecha_registro, INTERVAL cp.duracion_prueba_dias DAY) > NOW()
        WHERE u.rol = 'vendedor' AND u.activo = TRUE
        GROUP BY u.id_usuario, u.nombre, u.email
        ORDER BY u.nombre`,
    );
    res.json(rows);
  } catch (error) {
    reportarError(res, 'Error al consultar vendedores', error);
  }
});

appMiddleware.get('/api/prospectos', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT cp.id_cliente, cp.correo_electronico, cp.nombre, cp.empresa,
              cp.estado_prospecto, cp.puntaje_interes, cp.fecha_registro,
              DATE_ADD(cp.fecha_registro, INTERVAL cp.duracion_prueba_dias DAY) AS fecha_fin_prueba,
              CASE WHEN DATE_ADD(cp.fecha_registro, INTERVAL cp.duracion_prueba_dias DAY) <= NOW()
                   THEN 'vencida' ELSE 'activa' END AS estado_prueba,
              cp.id_campania, cm.nombre_campania,
              cp.id_usuario_asignado, us.nombre AS vendedor,
              COUNT(DISTINCT aw.id_actividad) AS actividades
         FROM cliente_prospecto AS cp
         LEFT JOIN campania_marketing AS cm ON cm.id_campania = cp.id_campania
         LEFT JOIN usuario_sistema AS us ON us.id_usuario = cp.id_usuario_asignado
         LEFT JOIN actividad_web AS aw ON aw.id_cliente = cp.id_cliente
        GROUP BY cp.id_cliente, cm.nombre_campania, us.nombre
        ORDER BY cp.fecha_registro DESC`,
    );
    res.json(rows);
  } catch (error) {
    reportarError(res, 'Error al consultar prospectos', error);
  }
});

appMiddleware.post('/api/prospectos', async (req, res) => {
  const { correo_electronico, nombre, empresa, id_campania, visitor_id } = req.body || {};
  const correo = typeof correo_electronico === 'string' ? correo_electronico.trim().toLowerCase() : '';
  const nombreLimpio = typeof nombre === 'string' ? nombre.trim() : '';
  const empresaLimpia = typeof empresa === 'string' ? empresa.trim() : null;
  const campaniaId = id_campania === '' || id_campania == null ? null : Number(id_campania);

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo) || correo.length > 150) {
    return res.status(400).json({ error: 'Ingresa un correo electrónico válido (máximo 150 caracteres).' });
  }
  if (!nombreLimpio || nombreLimpio.length > 120) {
    return res.status(400).json({ error: 'El nombre es obligatorio y debe tener máximo 120 caracteres.' });
  }
  if (empresaLimpia && empresaLimpia.length > 120) {
    return res.status(400).json({ error: 'La empresa debe tener máximo 120 caracteres.' });
  }
  if (campaniaId !== null && (!Number.isSafeInteger(campaniaId) || campaniaId < 1)) {
    return res.status(400).json({ error: 'La campaña seleccionada no es válida.' });
  }
  if (visitor_id && !uuidValido(visitor_id)) {
    return res.status(400).json({ error: 'El identificador de seguimiento no es válido.' });
  }

  try {
    const resultado = await ejecutarTransaccion(async (connection) => {
      const [insert] = await connection.query(
        `INSERT INTO cliente_prospecto
           (correo_electronico, nombre, empresa, estado_prospecto, duracion_prueba_dias, id_campania)
         VALUES (?, ?, ?, 'nuevo', 60, ?)`,
        [correo, nombreLimpio, empresaLimpia || null, campaniaId],
      );
      const idCliente = insert.insertId;
      await encolarEventoCrm(connection, 'prospecto.creado', {
        id_cliente: idCliente,
        correo_electronico: correo,
        nombre: nombreLimpio,
        empresa: empresaLimpia || null,
        id_campania: campaniaId,
        duracion_prueba_dias: 60,
      });
      await connection.query(
        `INSERT INTO actividad_web (id_cliente, url_visitada, tipo_evento, ip_origen)
         VALUES (?, '/registro-prueba', 'registro_prueba', ?)`,
        [idCliente, req.ip || null],
      );

      if (visitor_id) {
        await connection.query(
          `UPDATE actividad_web
              SET id_cliente = ?, visitor_id = NULL
            WHERE visitor_id = ? AND id_cliente IS NULL`,
          [idCliente, visitor_id],
        );
      }

      const puntaje = await calcularPuntaje(connection, idCliente);
      await connection.query(
        'UPDATE cliente_prospecto SET puntaje_interes = ? WHERE id_cliente = ?',
        [puntaje, idCliente],
      );
      const vendedorAsignado = await asignarProspectoAutomaticamente(connection, idCliente, puntaje);
      return { id_cliente: idCliente, puntaje_interes: puntaje, id_usuario_asignado: vendedorAsignado };
    });

    res.status(201).json({
      ...resultado,
      duracion_prueba_dias: 60,
      mensaje: resultado.id_usuario_asignado
        ? 'Prospecto registrado y asignado a un vendedor.'
        : 'Prospecto registrado. La asignación se realizará al alcanzar el puntaje mínimo.',
    });
  } catch (error) {
    if (error.errno === 1062) {
      return res.status(409).json({ error: 'Ya existe un prospecto registrado con ese correo.' });
    }
    if (error.errno === 1452) {
      return res.status(400).json({ error: 'La campaña seleccionada no existe.' });
    }
    reportarError(res, 'Error al registrar prospecto', error);
  }
});

appMiddleware.get('/api/prospectos/:id/actividades', async (req, res) => {
  const idCliente = Number(req.params.id);
  if (!idPositivo(idCliente)) return res.status(400).json({ error: 'El ID del prospecto no es válido.' });

  try {
    const [rows] = await pool.query(
      `SELECT id_actividad, url_visitada, tipo_evento, fecha_actividad
         FROM actividad_web
        WHERE id_cliente = ?
        ORDER BY fecha_actividad DESC
        LIMIT 100`,
      [idCliente],
    );
    res.json(rows);
  } catch (error) {
    reportarError(res, 'Error al consultar actividad web', error);
  }
});

appMiddleware.post('/api/actividad', async (req, res) => {
  const { id_cliente, visitor_id, url_visitada, tipo_evento } = req.body || {};
  const idCliente = id_cliente == null ? null : Number(id_cliente);
  const evento = typeof tipo_evento === 'string' ? tipo_evento : '';
  const url = typeof url_visitada === 'string' ? url_visitada.trim() : '';

  if (!eventosPermitidos.has(evento)) {
    return res.status(400).json({ error: 'El tipo de actividad no está permitido.' });
  }
  if (!url.startsWith('/') || url.startsWith('//') || url.length > 500) {
    return res.status(400).json({ error: 'La URL debe ser una ruta local válida de máximo 500 caracteres.' });
  }
  if (idCliente === null && !uuidValido(visitor_id)) {
    return res.status(400).json({ error: 'Se requiere un identificador de visitante válido.' });
  }
  if (idCliente !== null && !idPositivo(idCliente)) {
    return res.status(400).json({ error: 'El ID del prospecto no es válido.' });
  }

  try {
    const resultado = await ejecutarTransaccion(async (connection) => {
      if (idCliente === null) {
        await connection.query(
          `INSERT INTO actividad_web (visitor_id, url_visitada, tipo_evento, ip_origen)
           VALUES (?, ?, ?, ?)`,
          [visitor_id, url, evento, null],
        );
        return { puntaje_interes: null, id_usuario_asignado: null };
      }

      const [clientes] = await connection.query(
        'SELECT id_cliente FROM cliente_prospecto WHERE id_cliente = ? FOR UPDATE',
        [idCliente],
      );
      if (!clientes.length) {
        const error = new Error('El prospecto indicado no existe.');
        error.status = 404;
        throw error;
      }
      await connection.query(
        `INSERT INTO actividad_web (id_cliente, url_visitada, tipo_evento, ip_origen)
         VALUES (?, ?, ?, ?)`,
        [idCliente, url, evento, req.ip || null],
      );
      const puntaje = await calcularPuntaje(connection, idCliente);
      const [actual] = await connection.query(
        'SELECT id_usuario_asignado FROM cliente_prospecto WHERE id_cliente = ?',
        [idCliente],
      );
      await connection.query(
        'UPDATE cliente_prospecto SET puntaje_interes = ? WHERE id_cliente = ?',
        [puntaje, idCliente],
      );
      const vendedor = actual[0].id_usuario_asignado
        ? actual[0].id_usuario_asignado
        : await asignarProspectoAutomaticamente(connection, idCliente, puntaje);
      return { puntaje_interes: puntaje, id_usuario_asignado: vendedor };
    });

    res.status(201).json(resultado);
  } catch (error) {
    if (error.status === 404) return res.status(404).json({ error: error.message });
    reportarError(res, 'Error al registrar actividad web', error);
  }
});

appMiddleware.patch('/api/prospectos/:id/asignacion', async (req, res) => {
  const idCliente = Number(req.params.id);
  const idUsuario = Number(req.body?.id_usuario);
  if (!idPositivo(idCliente) || !idPositivo(idUsuario)) {
    return res.status(400).json({ error: 'El prospecto y el vendedor deben tener IDs válidos.' });
  }

  try {
    const idAsignado = await ejecutarTransaccion(async (connection) => {
      const [clientes] = await connection.query(
        'SELECT id_cliente, id_usuario_asignado FROM cliente_prospecto WHERE id_cliente = ? FOR UPDATE',
        [idCliente],
      );
      if (!clientes.length) {
        const error = new Error('El prospecto indicado no existe.');
        error.status = 404;
        throw error;
      }

      const [vendedores] = await connection.query(
        `SELECT id_usuario FROM usuario_sistema
          WHERE id_usuario = ? AND rol = 'vendedor' AND activo = TRUE
          FOR UPDATE`,
        [idUsuario],
      );
      if (!vendedores.length) {
        const error = new Error('El vendedor no existe o no está activo.');
        error.status = 404;
        throw error;
      }

      if (clientes[0].id_usuario_asignado === idUsuario) return idUsuario;

      const [conteo] = await connection.query(
        `SELECT COUNT(*) AS total FROM cliente_prospecto
          WHERE id_usuario_asignado = ?
            AND estado_prospecto IN ('nuevo', 'calificado')
            AND DATE_ADD(fecha_registro, INTERVAL duracion_prueba_dias DAY) > NOW()`,
        [idUsuario],
      );
      if (Number(conteo[0].total) >= limiteProspectosVendedor) {
        const error = new Error(`El vendedor ya alcanzó el límite de ${limiteProspectosVendedor} prospectos activos.`);
        error.status = 409;
        throw error;
      }

      await connection.query(
        `UPDATE cliente_prospecto
            SET id_usuario_asignado = ?,
                estado_prospecto = CASE WHEN estado_prospecto = 'nuevo' THEN 'calificado' ELSE estado_prospecto END
          WHERE id_cliente = ?`,
        [idUsuario, idCliente],
      );
      await connection.query(
        `INSERT INTO notificacion (id_usuario, id_cliente, tipo, mensaje)
         VALUES (?, ?, 'prospecto_asignado', ?)`,
        [idUsuario, idCliente, `Se te asignó el prospecto #${idCliente}.`],
      );
      await encolarEventoCrm(connection, 'prospecto.asignado', {
        id_cliente: idCliente,
        id_usuario_asignado: idUsuario,
        puntaje_interes: clientes[0].puntaje_interes,
      });
      return idUsuario;
    });
    res.json({ id_cliente: idCliente, id_usuario_asignado: idAsignado });
  } catch (error) {
    if (error.status) return res.status(error.status).json({ error: error.message });
    reportarError(res, 'Error al asignar prospecto', error);
  }
});

appMiddleware.get('/api/notificaciones', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT n.id_notificacion, n.id_cliente, n.tipo, n.mensaje, n.leida, n.creada_en,
              cp.nombre AS nombre_prospecto
         FROM notificacion AS n
         LEFT JOIN cliente_prospecto AS cp ON cp.id_cliente = n.id_cliente
        ORDER BY n.creada_en DESC
        LIMIT 50`,
    );
    res.json(rows);
  } catch (error) {
    reportarError(res, 'Error al consultar notificaciones', error);
  }
});

appMiddleware.patch('/api/notificaciones/:id/leida', async (req, res) => {
  const id = Number(req.params.id);
  if (!idPositivo(id)) return res.status(400).json({ error: 'El ID de la notificación no es válido.' });
  try {
    const [resultado] = await pool.query(
      'UPDATE notificacion SET leida = TRUE WHERE id_notificacion = ?',
      [id],
    );
    if (!resultado.affectedRows) return res.status(404).json({ error: 'La notificación no existe.' });
    res.json({ id_notificacion: id, leida: true });
  } catch (error) {
    reportarError(res, 'Error al actualizar notificación', error);
  }
});

appMiddleware.get('/api/propuestas', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT p.id_propuesta, p.id_cliente, cp.nombre AS nombre_prospecto,
              p.id_usuario, u.nombre AS vendedor, p.monto_estimado,
              p.estado_propuesta, p.fecha_creacion,
              (v.id_venta IS NOT NULL) AS venta_cerrada
         FROM propuesta AS p
         JOIN cliente_prospecto AS cp ON cp.id_cliente = p.id_cliente
         JOIN usuario_sistema AS u ON u.id_usuario = p.id_usuario
         LEFT JOIN venta AS v ON v.id_propuesta = p.id_propuesta
        ORDER BY p.fecha_creacion DESC`,
    );
    res.json(rows);
  } catch (error) {
    reportarError(res, 'Error al consultar propuestas', error);
  }
});

appMiddleware.post('/api/propuestas', async (req, res) => {
  const idCliente = Number(req.body?.id_cliente);
  const idUsuario = Number(req.body?.id_usuario);
  const monto = Number(req.body?.monto_estimado);
  if (!idPositivo(idCliente) || !idPositivo(idUsuario)) {
    return res.status(400).json({ error: 'El prospecto y el vendedor deben ser válidos.' });
  }
  if (!Number.isFinite(monto) || monto <= 0 || monto > 999999999999.99) {
    return res.status(400).json({ error: 'El monto estimado debe ser mayor que cero y válido.' });
  }

  try {
    const idPropuesta = await ejecutarTransaccion(async (connection) => {
      const [result] = await connection.query(
        `INSERT INTO propuesta (id_cliente, id_usuario, monto_estimado, estado_propuesta)
         VALUES (?, ?, ?, 'borrador')`,
        [idCliente, idUsuario, monto],
      );
      await encolarEventoCrm(connection, 'propuesta.creada', {
        id_propuesta: result.insertId,
        id_cliente: idCliente,
        id_usuario: idUsuario,
        monto_estimado: monto,
      });
      return result.insertId;
    });
    res.status(201).json({ id_propuesta: idPropuesta });
  } catch (error) {
    if (error.errno === 1452) {
      return res.status(400).json({ error: 'El prospecto o el vendedor no existen.' });
    }
    reportarError(res, 'Error al crear propuesta', error);
  }
});

appMiddleware.patch('/api/propuestas/:id/estado', async (req, res) => {
  const idPropuesta = Number(req.params.id);
  const estado = req.body?.estado_propuesta;
  const estadosValidos = new Set(['borrador', 'enviada', 'aceptada', 'rechazada']);
  if (!idPositivo(idPropuesta) || !estadosValidos.has(estado)) {
    return res.status(400).json({ error: 'La propuesta o el estado indicados no son válidos.' });
  }

  try {
    const resultado = await ejecutarTransaccion(async (connection) => {
      const [propuestas] = await connection.query(
        'SELECT id_cliente, estado_propuesta FROM propuesta WHERE id_propuesta = ? FOR UPDATE',
        [idPropuesta],
      );
      if (!propuestas.length) {
        const error = new Error('La propuesta indicada no existe.');
        error.status = 404;
        throw error;
      }
      const propuesta = propuestas[0];
      if (propuesta.estado_propuesta === estado) return { id_propuesta: idPropuesta, estado_propuesta: estado };

      const [ventas] = await connection.query(
        'SELECT id_venta FROM venta WHERE id_propuesta = ?',
        [idPropuesta],
      );
      if (ventas.length) {
        const error = new Error('No se puede cambiar el estado de una propuesta con una venta cerrada.');
        error.status = 409;
        throw error;
      }

      await connection.query(
        'UPDATE propuesta SET estado_propuesta = ? WHERE id_propuesta = ?',
        [estado, idPropuesta],
      );
      await encolarEventoCrm(connection, 'propuesta.estado_cambiado', {
        id_propuesta: idPropuesta,
        id_cliente: propuesta.id_cliente,
        estado_propuesta: estado,
      });
      if (estado === 'enviada' || estado === 'aceptada') {
        const evento = estado === 'aceptada' ? 'propuesta_aceptada' : 'propuesta_enviada';
        await connection.query(
          `INSERT INTO actividad_web (id_cliente, url_visitada, tipo_evento)
           VALUES (?, '/propuestas', ?)`,
          [propuesta.id_cliente, evento],
        );
        const puntaje = await calcularPuntaje(connection, propuesta.id_cliente);
        await connection.query(
          'UPDATE cliente_prospecto SET puntaje_interes = ? WHERE id_cliente = ?',
          [puntaje, propuesta.id_cliente],
        );
        await asignarProspectoAutomaticamente(connection, propuesta.id_cliente, puntaje);
      }
      return { id_propuesta: idPropuesta, estado_propuesta: estado };
    });
    res.json(resultado);
  } catch (error) {
    if (error.status) return res.status(error.status).json({ error: error.message });
    reportarError(res, 'Error al actualizar estado de propuesta', error);
  }
});

appMiddleware.get('/api/propuestas-pendientes', async (req, res) => {
  try {
    const [rows] = await pool.query(`
      SELECT p.id_propuesta, p.id_cliente, p.id_usuario, p.monto_estimado, p.estado_propuesta,
             cp.nombre AS nombre_prospecto
        FROM propuesta p
        JOIN cliente_prospecto cp ON cp.id_cliente = p.id_cliente
        LEFT JOIN venta v ON v.id_propuesta = p.id_propuesta
       WHERE p.estado_propuesta = 'aceptada' AND v.id_venta IS NULL
       ORDER BY p.id_propuesta
    `);
    res.json(rows);
  } catch (error) {
    reportarError(res, 'Error al consultar propuestas pendientes', error);
  }
});

appMiddleware.post('/api/cerrar-venta', async (req, res) => {
  const { id_propuesta, id_usuario, monto_final, metodo_pago } = req.body || {};
  const monto = Number(monto_final);
  if (!idPositivo(id_propuesta)) {
    return res.status(400).json({ error: 'El ID de la propuesta debe ser un entero positivo.' });
  }
  if (!idPositivo(id_usuario)) {
    return res.status(400).json({ error: 'El ID del usuario debe ser un entero positivo.' });
  }
  if (!Number.isFinite(monto) || monto <= 0) {
    return res.status(400).json({ error: 'El monto final debe ser un número mayor que cero.' });
  }
  if (typeof metodo_pago !== 'string' || !metodo_pago.trim() || metodo_pago.trim().length > 40) {
    return res.status(400).json({ error: 'El método de pago es obligatorio y debe tener máximo 40 caracteres.' });
  }

  let connection;
  try {
    connection = await pool.getConnection();
    await connection.query('CALL sp_cerrar_venta(?, ?, ?, ?, @venta_creada_id)', [
      id_propuesta,
      id_usuario,
      monto,
      metodo_pago.trim(),
    ]);
    const [[outRow]] = await connection.query(
      `SELECT @venta_creada_id AS venta_creada_id,
              f.id_factura, f.numero_factura, f.estado AS estado_factura
         FROM factura AS f
        WHERE f.id_venta = @venta_creada_id`,
    );
    res.status(201).json({
      ...outRow,
      sincronizacion_crm: crmWebhookUrl ? 'pendiente' : 'sin_configurar',
    });
  } catch (error) {
    if (error.errno === 1644 || error.sqlState === '45000') {
      return res.status(400).json({ error: error.sqlMessage || error.message });
    }
    if (error.errno === 1062) {
      return res.status(409).json({ error: 'Esta propuesta ya tiene una venta registrada.' });
    }
    if (error.errno === 1452 || error.errno === 3819) {
      return res.status(400).json({ error: 'Los datos enviados no corresponden a un usuario o propuesta válidos.' });
    }
    reportarError(res, 'Error al cerrar la venta', error);
  } finally {
    if (connection) connection.release();
  }
});

appMiddleware.get('/api/crm/sincronizacion', async (req, res) => {
  try {
    const [conteos] = await pool.query(
      `SELECT estado, COUNT(*) AS total
         FROM crm_outbox
        GROUP BY estado`,
    );
    const [eventos] = await pool.query(
      `SELECT id_evento, tipo_evento, estado, intentos, ultimo_error, creado_en
         FROM crm_outbox
        ORDER BY id_evento DESC
        LIMIT 20`,
    );
    res.json({
      configurado: Boolean(crmWebhookUrl),
      webhook: crmWebhookUrl ? 'activo' : 'pendiente_de_configuracion',
      conteos,
      eventos,
    });
  } catch (error) {
    reportarError(res, 'Error al consultar sincronización CRM', error);
  }
});

appMiddleware.post('/api/crm/sincronizacion/:id/reintentar', async (req, res) => {
  const id = Number(req.params.id);
  if (!idPositivo(id)) return res.status(400).json({ error: 'El ID del evento no es válido.' });
  try {
    const [result] = await pool.query(
      `UPDATE crm_outbox
          SET estado = 'pendiente', intentos = 0, proximo_intento = NOW(), ultimo_error = NULL
        WHERE id_evento = ? AND estado = 'error'`,
      [id],
    );
    if (!result.affectedRows) {
      return res.status(404).json({ error: 'No existe un evento fallido con ese ID.' });
    }
    res.json({ id_evento: id, estado: 'pendiente' });
  } catch (error) {
    reportarError(res, 'Error al reintentar sincronización CRM', error);
  }
});

appMiddleware.get('/api/reporte-mensual', async (req, res) => {
  try {
    const [resultSets] = await pool.query(
      'CALL sp_reporte_mensual_ventas(MONTH(CURRENT_DATE()), YEAR(CURRENT_DATE()))',
    );
    res.json(resultSets[0] || []);
  } catch (error) {
    reportarError(res, 'Error al consultar el reporte mensual', error);
  }
});

appMiddleware.get('/api/tasa-conversion', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM v_tasa_conversion ORDER BY id_campania');
    res.json(rows);
  } catch (error) {
    reportarError(res, 'Error al consultar la tasa de conversión', error);
  }
});

appMiddleware.get('/api/ventas', async (req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT v.id_venta, v.fecha_cierre, v.monto_final,
              f.id_factura, f.numero_factura, f.estado AS estado_factura
         FROM venta AS v
         LEFT JOIN factura AS f ON f.id_venta = v.id_venta
        ORDER BY v.id_venta DESC`,
    );
    res.json(rows);
  } catch (error) {
    reportarError(res, 'Error al consultar las ventas', error);
  }
});

const sincronizarSiguienteEvento = async () => {
  if (!crmWebhookUrl) return;

  let evento;
  try {
    evento = await ejecutarTransaccion(async (connection) => {
      const [rows] = await connection.query(
        `SELECT id_evento, clave_idempotencia, tipo_evento, payload, intentos
           FROM crm_outbox
          WHERE intentos < 8
            AND ((estado = 'pendiente' AND proximo_intento <= NOW())
              OR (estado = 'procesando' AND actualizado_en < DATE_SUB(NOW(), INTERVAL 5 MINUTE)))
          ORDER BY id_evento
          LIMIT 1
          FOR UPDATE SKIP LOCKED`,
      );
      if (!rows.length) return null;
      const item = rows[0];
      await connection.query(
        `UPDATE crm_outbox
            SET estado = 'procesando', intentos = intentos + 1
          WHERE id_evento = ?`,
        [item.id_evento],
      );
      return item;
    });
    if (!evento) return;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    let response;
    try {
      response = await fetch(crmWebhookUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Idempotency-Key': evento.clave_idempotencia,
          ...(crmWebhookToken ? { Authorization: `Bearer ${crmWebhookToken}` } : {}),
        },
        body: JSON.stringify(typeof evento.payload === 'string' ? JSON.parse(evento.payload) : evento.payload),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      const detalle = (await response.text()).slice(0, 800);
      throw new Error(`CRM respondió HTTP ${response.status}: ${detalle}`);
    }
    await pool.query(
      `UPDATE crm_outbox
          SET estado = 'sincronizado', ultimo_error = NULL
        WHERE id_evento = ?`,
      [evento.id_evento],
    );
    console.info(`Evento CRM ${evento.id_evento} sincronizado.`);
  } catch (error) {
    if (!evento) {
      console.error('No se pudo procesar la cola CRM:', error);
      return;
    }
    const intentos = Number(evento.intentos) + 1;
    const estado = intentos >= 8 ? 'error' : 'pendiente';
    try {
      await pool.query(
        `UPDATE crm_outbox
            SET estado = ?,
                ultimo_error = ?,
                proximo_intento = DATE_ADD(NOW(), INTERVAL LEAST(60, POW(2, intentos)) MINUTE)
          WHERE id_evento = ?`,
        [estado, String(error.message || error).slice(0, 1000), evento.id_evento],
      );
    } catch (updateError) {
      console.error(`No se pudo actualizar el evento CRM ${evento.id_evento}:`, updateError);
    }
    console.error(`Falló la sincronización del evento CRM ${evento.id_evento}:`, error);
  }
};

appMiddleware.use((error, req, res, next) => {
  if (error instanceof SyntaxError && 'body' in error) {
    return res.status(400).json({ error: 'El cuerpo de la solicitud debe ser JSON válido.' });
  }
  reportarError(res, 'Error inesperado en la solicitud', error);
});

const server = appMiddleware.listen(port, async () => {
  try {
    await pool.query('SELECT 1');
    console.log(`API de Zimbra disponible en http://localhost:${port}`);
    console.log(`Conectada a MySQL (Aiven): ${databaseConfig.database} en ${databaseConfig.host}:${databaseConfig.port}`);
    if (!crmWebhookUrl) {
      console.warn('CRM_WEBHOOK_URL no está configurado; los eventos de venta quedarán en la cola CRM.');
    } else {
      await sincronizarSiguienteEvento();
      setInterval(sincronizarSiguienteEvento, 15000);
    }
  } catch (error) {
    console.error('No se pudo conectar con MySQL en Aiven. Revisa la configuración del archivo .env.', error);
    server.close(async () => {
      await pool.end();
      process.exitCode = 1;
    });
  }
});

const cerrarServidor = async () => {
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
};

process.on('SIGINT', cerrarServidor);
process.on('SIGTERM', cerrarServidor);
